import 'dart:convert';
import 'dart:typed_data';

/// The SentencePiece word boundary, U+2581.
const metaspace = '\u2581';

/// "WDTK", little-endian.
const wolfDefenderTokenizerMagic = 0x4B544457;
const wolfDefenderTokenizerVersion = 1;

/// The tokenizer of Wolf Defender Edge: the Gemma-style BPE of its base
/// model, mmBERT. It gives the same IDs as Hugging Face `tokenizers` for its
/// `tokenizer.json`, without special tokens.
///
/// 1. Added tokens split the text first: the leftmost match, and at one
///    position the longest. They match the original text. Examples are
///    `<bos>`, `\n\n`, `\t\t` and `<b>`.
/// 2. Each other part: " " becomes "▁", and "▁" is prepended if the part does
///    not start with it. The part splits before each "▁".
/// 3. BPE on each word, by merge rank. A character that is not in the
///    vocabulary becomes its UTF-8 byte tokens (`<0x0A>`), or `<unk>` if a
///    byte token is missing. Adjacent unknowns become one `<unk>`.
///
/// The file, little-endian: magic, version, the token count and each token
/// (UTF-8 byte length as uint16, then the bytes; IDs 0, 1, 2, ...), the merge
/// count and each merge in rank order (left ID, right ID; uint32), the added
/// token count and each added token ID (uint32).
/// `tool/wolf_defender/convert_tokenizer.dart` writes it.
final class WolfDefenderTokenizer {
  WolfDefenderTokenizer._(
    this._tokens,
    this._ids,
    this._mergeRanks,
    this._mergeResults,
    this._added,
    this._addedFirstUnits,
    this._addedMaxLength,
    this._byteTokens,
    this.unkId,
  );

  factory WolfDefenderTokenizer.fromBytes(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    var offset = 0;
    int u32() {
      final value = data.getUint32(offset, Endian.little);
      offset += 4;
      return value;
    }

    if (bytes.length < 8 ||
        u32() != wolfDefenderTokenizerMagic ||
        u32() != wolfDefenderTokenizerVersion) {
      throw const FormatException('Not a Wolf Defender tokenizer file');
    }
    final count = u32();
    if (count > _pairBase) {
      throw FormatException('$count tokens; at most $_pairBase');
    }
    final tokens = List<String>.filled(count, '');
    final ids = <String, int>{};
    for (var id = 0; id < count; id++) {
      final length = data.getUint16(offset, Endian.little);
      offset += 2;
      final token = _decodeKeepingBom(
        Uint8List.sublistView(bytes, offset, offset + length),
      );
      offset += length;
      tokens[id] = token;
      ids[token] = id;
    }
    final mergeCount = u32();
    final mergeRanks = <int, int>{};
    final mergeResults = Int32List(mergeCount);
    for (var rank = 0; rank < mergeCount; rank++) {
      final left = u32(), right = u32();
      if (left >= count || right >= count) {
        throw FormatException('Merge $rank has an unknown ID');
      }
      final result = ids[tokens[left] + tokens[right]];
      if (result == null) {
        throw FormatException('Merge $rank has no result token');
      }
      // The first (lowest) rank of a pair wins, as in `tokenizers`.
      mergeRanks.putIfAbsent(_pair(left, right), () => rank);
      mergeResults[rank] = result;
    }
    final addedCount = u32();
    final added = <String, int>{};
    final firstUnits = <int>{};
    var maxLength = 0;
    for (var i = 0; i < addedCount; i++) {
      final id = u32();
      if (id >= count) throw FormatException('Added token $id is unknown');
      final token = tokens[id];
      if (token.isEmpty) continue;
      added[token] = id;
      firstUnits.add(token.codeUnitAt(0));
      if (token.length > maxLength) maxLength = token.length;
    }
    if (offset != bytes.length) {
      throw FormatException('${bytes.length - offset} bytes after the end');
    }
    final unk = ids['<unk>'];
    if (unk == null) throw const FormatException('No <unk> token');
    final byteTokens = Int32List(256);
    for (var b = 0; b < 256; b++) {
      byteTokens[b] =
          ids['<0x${b.toRadixString(16).toUpperCase().padLeft(2, '0')}>'] ?? -1;
    }
    return WolfDefenderTokenizer._(
      tokens,
      ids,
      mergeRanks,
      mergeResults,
      added,
      firstUnits,
      maxLength,
      byteTokens,
      unk,
    );
  }

  /// IDs and pairs fit in a key: left × [_pairBase] + right. Arithmetic, not
  /// shifts: on web, shifts truncate to 32 bits.
  static const _pairBase = 1 << 17;
  static int _pair(int left, int right) => left * _pairBase + right;

  /// Heap entries are rank × [_heapBase] + position.
  static const _heapBase = 4294967296;

  final List<String> _tokens;
  final Map<String, int> _ids;
  final Map<int, int> _mergeRanks;
  final Int32List _mergeResults;
  final Map<String, int> _added;
  final Set<int> _addedFirstUnits;
  final int _addedMaxLength;
  final Int32List _byteTokens;
  final int unkId;
  final _cache = <String, List<int>>{};
  static const _cacheLimit = 50000;

  int get vocabularySize => _tokens.length;

  /// The ID of [token], or null.
  int? id(String token) => _ids[token];

  /// The token with [id].
  String token(int id) => _tokens[id];

  /// The IDs of [text], without special tokens at the ends.
  List<int> encode(String text) {
    final out = <int>[];
    var start = 0;
    var i = 0;
    while (i < text.length) {
      if (_addedFirstUnits.contains(text.codeUnitAt(i))) {
        final match = _addedAt(text, i);
        if (match != null) {
          _encodePart(text.substring(start, i), out);
          out.add(match.$1);
          i += match.$2;
          start = i;
          continue;
        }
      }
      i++;
    }
    _encodePart(text.substring(start), out);
    return out;
  }

  /// The longest added token at [i]: its ID and length.
  (int, int)? _addedAt(String text, int i) {
    final longest = text.length - i < _addedMaxLength
        ? text.length - i
        : _addedMaxLength;
    for (var length = longest; length > 0; length--) {
      final id = _added[text.substring(i, i + length)];
      if (id != null) return (id, length);
    }
    return null;
  }

  void _encodePart(String part, List<int> out) {
    if (part.isEmpty) return;
    var normalized = part.replaceAll(' ', metaspace);
    if (!normalized.startsWith(metaspace)) normalized = '$metaspace$normalized';
    var start = 0;
    for (var i = 1; i < normalized.length; i++) {
      if (normalized.codeUnitAt(i) == 0x2581) {
        _encodeWord(normalized.substring(start, i), out);
        start = i;
      }
    }
    _encodeWord(normalized.substring(start), out);
  }

  void _encodeWord(String word, List<int> out) {
    final cached = _cache[word];
    if (cached != null) {
      out.addAll(cached);
      return;
    }
    final ids = _bpe(word);
    if (_cache.length >= _cacheLimit) _cache.clear();
    _cache[word] = ids;
    out.addAll(ids);
  }

  List<int> _bpe(String word) {
    // The initial symbols: characters, byte tokens, and fused unknowns.
    final symbols = <int>[];
    var pendingUnk = false;
    for (final rune in word.runes) {
      final char = String.fromCharCode(rune);
      final id = _ids[char];
      if (id != null) {
        if (pendingUnk) symbols.add(unkId);
        pendingUnk = false;
        symbols.add(id);
        continue;
      }
      final bytes = utf8.encode(char);
      if (bytes.every((b) => _byteTokens[b] >= 0)) {
        if (pendingUnk) symbols.add(unkId);
        pendingUnk = false;
        for (final b in bytes) {
          symbols.add(_byteTokens[b]);
        }
        continue;
      }
      pendingUnk = true;
    }
    if (pendingUnk) symbols.add(unkId);
    final n = symbols.length;
    if (n < 2) return symbols;

    // Merges by rank, then position, in a linked list of symbols.
    final next = Int32List(n), prev = Int32List(n);
    final alive = Uint8List(n)..fillRange(0, n, 1);
    for (var i = 0; i < n; i++) {
      prev[i] = i - 1;
      next[i] = i + 1 < n ? i + 1 : -1;
    }
    final heap = _MinHeap();
    void push(int position) {
      final right = next[position];
      if (right < 0) return;
      final rank = _mergeRanks[_pair(symbols[position], symbols[right])];
      if (rank != null) heap.push(rank * _heapBase + position);
    }

    for (var i = 0; i < n - 1; i++) {
      push(i);
    }
    while (heap.isNotEmpty) {
      final top = heap.pop();
      final rank = top ~/ _heapBase;
      final position = top - rank * _heapBase;
      if (alive[position] == 0) continue;
      final right = next[position];
      if (right < 0) continue;
      // The entry is stale if the pair changed.
      if (_mergeRanks[_pair(symbols[position], symbols[right])] != rank) {
        continue;
      }
      symbols[position] = _mergeResults[rank];
      alive[right] = 0;
      next[position] = next[right];
      if (next[right] >= 0) prev[next[right]] = position;
      if (prev[position] >= 0) push(prev[position]);
      push(position);
    }
    return [for (var i = 0; i >= 0; i = next[i]) symbols[i]];
  }
}

/// UTF-8 to a string. `utf8.decode` drops a leading byte order mark, but
/// U+FEFF is a token of its own.
String _decodeKeepingBom(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return '\uFEFF${utf8.decode(Uint8List.sublistView(bytes, 3))}';
  }
  return utf8.decode(bytes);
}

final class _MinHeap {
  final _values = <int>[];

  bool get isNotEmpty => _values.isNotEmpty;

  void push(int value) {
    _values.add(value);
    var i = _values.length - 1;
    while (i > 0) {
      final parent = (i - 1) ~/ 2;
      if (_values[parent] <= value) break;
      _values[i] = _values[parent];
      i = parent;
    }
    _values[i] = value;
  }

  int pop() {
    final top = _values.first;
    final last = _values.removeLast();
    if (_values.isEmpty) return top;
    var i = 0;
    final length = _values.length;
    while (true) {
      final left = 2 * i + 1;
      if (left >= length) break;
      final right = left + 1;
      final child = right < length && _values[right] < _values[left]
          ? right
          : left;
      if (_values[child] >= last) break;
      _values[i] = _values[child];
      i = child;
    }
    _values[i] = last;
    return top;
  }
}
