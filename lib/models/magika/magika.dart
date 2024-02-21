import 'dart:math' as math;
import 'dart:typed_data';

import 'magika_abstract.dart'
    if (dart.library.io) 'magika_native.dart'
    if (dart.library.js) 'magika_web.dart';

abstract class Magika {
  static Magika? _instance;

  static Magika load(String path) {
    _instance ??= getMagika(path);
    return _instance!;
  }

  Future<MagikaType> getType(List<int> bytes);
}

class ModelFeatures {
  Uint8List beg;
  Uint8List mid;
  Uint8List end;
  Uint8List get all => Uint8List.fromList([...beg, ...mid, ...end]);

  ModelFeatures({required this.beg, required this.mid, required this.end});
}

ModelFeatures extractFeaturesFromBytes(Uint8List content,
    {int paddingToken = 255,
    int begSize = 512,
    int midSize = 512,
    int endSize = 512}) {
  // Initialize the arrays with padding
  List<int> beg = List<int>.filled(begSize, paddingToken);
  List<int> mid = List<int>.filled(midSize, paddingToken);
  List<int> end = List<int>.filled(endSize, paddingToken);

  // Beginning chunk
  for (int i = 0; i < math.min(content.length, begSize); i++) {
    beg[i] = content[i];
    // print('beg using $i for content.length ${content.length} and begSize $begSize');
  }

  // Middle chunk
  int midPoint = ((content.length / 2).round()) * 2; // Ensuring it's even
  int startHalf = math.max(0, midPoint - (midSize ~/ 2));
  int endHalf = math.min(content.length, startHalf + midSize);

  for (int i = startHalf; i < endHalf; i++) {
    mid[(i - startHalf) + (midSize - (endHalf - startHalf)) ~/ 2] = content[i];
    // print('mid using $i for startHalf $startHalf and endHalf $endHalf');
  }

  // End chunk
  for (int i = math.max(0, content.length - endSize), j = 0;
      i < content.length;
      i++, j++) {
    end[j + (endSize - math.min(content.length, endSize))] = content[i];
    // print('end using $i for content.length ${content.length} and endSize $endSize');
  }

  // Convert lists back to Uint8List
  return ModelFeatures(
    beg: Uint8List.fromList(beg),
    mid: Uint8List.fromList(mid),
    end: Uint8List.fromList(end),
  );
}

enum MagikaType {
  ai(
    modelIndex: 1,
    label: 'ai',
    mimetype: 'application/pdf',
    description: 'Adobe Illustrator Artwork',
  ),
  apk(
    modelIndex: 2,
    label: 'apk',
    mimetype: 'application/vnd.android.package-archive',
    description: 'Android package',
  ),
  appleplist(
    modelIndex: 3,
    label: 'appleplist',
    mimetype: 'application/x-plist',
    description: 'Apple property list',
  ),
  asm(
    modelIndex: 4,
    label: 'asm',
    mimetype: 'text/x-asm',
    description: 'Assembly',
  ),
  asp(
    modelIndex: 5,
    label: 'asp',
    mimetype: 'text/html',
    description: 'ASP source',
  ),
  batch(
    modelIndex: 6,
    label: 'batch',
    mimetype: 'text/x-msdos-batch',
    description: 'DOS batch file',
  ),
  bmp(
    modelIndex: 7,
    label: 'bmp',
    mimetype: 'image/bmp',
    description: 'BMP image data',
  ),
  bzip(
    modelIndex: 8,
    label: 'bzip',
    mimetype: 'application/x-bzip2',
    description: 'bzip2 compressed data',
  ),
  c(
    modelIndex: 9,
    label: 'c',
    mimetype: 'text/x-c',
    description: 'C source',
  ),
  cab(
    modelIndex: 10,
    label: 'cab',
    mimetype: 'application/vnd.ms-cab-compressed',
    description: 'Microsoft Cabinet archive data',
  ),
  cat(
    modelIndex: 11,
    label: 'cat',
    mimetype: 'application/octet-stream',
    description: 'Windows Catalog file',
  ),
  chm(
    modelIndex: 12,
    label: 'chm',
    mimetype: 'application/chm',
    description: 'MS Windows HtmlHelp Data',
  ),
  coff(
    modelIndex: 13,
    label: 'coff',
    mimetype: 'application/x-coff',
    description: 'Intel 80386 COFF',
  ),
  crx(
    modelIndex: 14,
    label: 'crx',
    mimetype: 'application/x-chrome-extension',
    description: 'Google Chrome extension',
  ),
  cs(
    modelIndex: 15,
    label: 'cs',
    mimetype: 'text/plain',
    description: 'C# source',
  ),
  css(
    modelIndex: 16,
    label: 'css',
    mimetype: 'text/css',
    description: 'CSS source',
  ),
  csv(
    modelIndex: 17,
    label: 'csv',
    mimetype: 'text/csv',
    description: 'CSV document',
  ),
  deb(
    modelIndex: 18,
    label: 'deb',
    mimetype: 'application/vnd.debian.binary-package',
    description: 'Debian binary package',
  ),
  dex(
    modelIndex: 19,
    label: 'dex',
    mimetype: 'application/x-android-dex',
    description: 'Dalvik dex file',
  ),
  directory(
    modelIndex: 20,
    label: 'directory',
    mimetype: 'inode/directory',
    description: 'A directory',
  ),
  dmg(
    modelIndex: 21,
    label: 'dmg',
    mimetype: 'application/x-apple-diskimage',
    description: 'Apple disk image',
  ),
  doc(
    modelIndex: 22,
    label: 'doc',
    mimetype: 'application/msword',
    description: 'Microsoft Word CDF document',
  ),
  docx(
    modelIndex: 23,
    label: 'docx',
    mimetype:
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    description: 'Microsoft Word 2007+ document',
  ),
  elf(
    modelIndex: 24,
    label: 'elf',
    mimetype: 'application/x-executable-elf',
    description: 'ELF executable',
  ),
  emf(
    modelIndex: 25,
    label: 'emf',
    mimetype: 'application/octet-stream',
    description: 'Windows Enhanced Metafile image data',
  ),
  eml(
    modelIndex: 26,
    label: 'eml',
    mimetype: 'message/rfc822',
    description: 'RFC 822 mail',
  ),
  empty(
    modelIndex: 27,
    label: 'empty',
    mimetype: 'inode/x-empty',
    description: 'Empty file',
  ),
  epub(
    modelIndex: 28,
    label: 'epub',
    mimetype: 'application/epub+zip',
    description: 'EPUB document',
  ),
  flac(
    modelIndex: 29,
    label: 'flac',
    mimetype: 'audio/flac',
    description: 'FLAC audio bitstream data',
  ),
  gif(
    modelIndex: 30,
    label: 'gif',
    mimetype: 'image/gif',
    description: 'GIF image data',
  ),
  go(
    modelIndex: 31,
    label: 'go',
    mimetype: 'text/x-golang',
    description: 'Golang source',
  ),
  gzip(
    modelIndex: 32,
    label: 'gzip',
    mimetype: 'application/gzip',
    description: 'gzip compressed data',
  ),
  hlp(
    modelIndex: 33,
    label: 'hlp',
    mimetype: 'application/winhlp',
    description: 'MS Windows help',
  ),
  html(
    modelIndex: 34,
    label: 'html',
    mimetype: 'text/html',
    description: 'HTML document',
  ),
  ico(
    modelIndex: 35,
    label: 'ico',
    mimetype: 'image/vnd.microsoft.icon',
    description: 'MS Windows icon resource',
  ),
  ini(
    modelIndex: 36,
    label: 'ini',
    mimetype: 'text/plain',
    description: 'INI configuration file',
  ),
  internetshortcut(
    modelIndex: 37,
    label: 'internetshortcut',
    mimetype: 'application/x-mswinurl',
    description: 'MS Windows Internet shortcut',
  ),
  iso(
    modelIndex: 38,
    label: 'iso',
    mimetype: 'application/x-iso9660-image',
    description: 'ISO 9660 CD-ROM filesystem data',
  ),
  jar(
    modelIndex: 39,
    label: 'jar',
    mimetype: 'application/java-archive',
    description: 'Java archive data (JAR)',
  ),
  java(
    modelIndex: 40,
    label: 'java',
    mimetype: 'text/x-java',
    description: 'Java source',
  ),
  javabytecode(
    modelIndex: 41,
    label: 'javabytecode',
    mimetype: 'application/x-java-applet',
    description: 'Java compiled bytecode',
  ),
  javascript(
    modelIndex: 42,
    label: 'javascript',
    mimetype: 'application/javascript',
    description: 'JavaScript source',
  ),
  jpeg(
    modelIndex: 43,
    label: 'jpeg',
    mimetype: 'image/jpeg',
    description: 'JPEG image data',
  ),
  json(
    modelIndex: 44,
    label: 'json',
    mimetype: 'application/json',
    description: 'JSON document',
  ),
  latex(
    modelIndex: 45,
    label: 'latex',
    mimetype: 'text/x-tex',
    description: 'LaTeX document',
  ),
  lisp(
    modelIndex: 46,
    label: 'lisp',
    mimetype: 'text/x-lisp',
    description: 'Lisp source',
  ),
  lnk(
    modelIndex: 47,
    label: 'lnk',
    mimetype: 'application/x-ms-shortcut',
    description: 'MS Windows shortcut',
  ),
  m3u(
    modelIndex: 48,
    label: 'm3u',
    mimetype: 'text/plain',
    description: 'M3U playlist',
  ),
  macho(
    modelIndex: 49,
    label: 'macho',
    mimetype: 'application/x-mach-o',
    description: 'Mach-O executable',
  ),
  makefile(
    modelIndex: 50,
    label: 'makefile',
    mimetype: 'text/x-makefile',
    description: 'Makefile source',
  ),
  markdown(
    modelIndex: 51,
    label: 'markdown',
    mimetype: 'text/markdown',
    description: 'Markdown document',
  ),
  mht(
    modelIndex: 52,
    label: 'mht',
    mimetype: 'application/x-mimearchive',
    description: 'MHTML document',
  ),
  mp3(
    modelIndex: 53,
    label: 'mp3',
    mimetype: 'audio/mpeg',
    description: 'MP3 media file',
  ),
  mp4(
    modelIndex: 54,
    label: 'mp4',
    mimetype: 'video/mp4',
    description: 'MP4 media file',
  ),
  mscompress(
    modelIndex: 55,
    label: 'mscompress',
    mimetype: 'application/x-ms-compress-szdd',
    description: 'MS Compress archive data',
  ),
  msi(
    modelIndex: 56,
    label: 'msi',
    mimetype: 'application/x-msi',
    description: 'Microsoft Installer file',
  ),
  mum(
    modelIndex: 57,
    label: 'mum',
    mimetype: 'text/xml',
    description: 'Windows Update Package file',
  ),
  odex(
    modelIndex: 58,
    label: 'odex',
    mimetype: 'application/x-executable-elf',
    description: 'ODEX ELF executable',
  ),
  odp(
    modelIndex: 59,
    label: 'odp',
    mimetype: 'application/vnd.oasis.opendocument.presentation',
    description: 'OpenDocument Presentation',
  ),
  ods(
    modelIndex: 60,
    label: 'ods',
    mimetype: 'application/vnd.oasis.opendocument.spreadsheet',
    description: 'OpenDocument Spreadsheet',
  ),
  odt(
    modelIndex: 61,
    label: 'odt',
    mimetype: 'application/vnd.oasis.opendocument.text',
    description: 'OpenDocument Text',
  ),
  ogg(
    modelIndex: 62,
    label: 'ogg',
    mimetype: 'audio/ogg',
    description: 'Ogg data',
  ),
  outlook(
    modelIndex: 63,
    label: 'outlook',
    mimetype: 'application/vnd.ms-outlook',
    description: 'MS Outlook Message',
  ),
  pcap(
    modelIndex: 64,
    label: 'pcap',
    mimetype: 'application/vnd.tcpdump.pcap',
    description: 'pcap capture file',
  ),
  pdf(
    modelIndex: 65,
    label: 'pdf',
    mimetype: 'application/pdf',
    description: 'PDF document',
  ),
  pebin(
    modelIndex: 66,
    label: 'pebin',
    mimetype: 'application/x-dosexec',
    description: 'PE executable',
  ),
  pem(
    modelIndex: 67,
    label: 'pem',
    mimetype: 'application/x-pem-file',
    description: 'PEM certificate',
  ),
  perl(
    modelIndex: 68,
    label: 'perl',
    mimetype: 'text/x-perl',
    description: 'Perl source',
  ),
  php(
    modelIndex: 69,
    label: 'php',
    mimetype: 'text/x-php',
    description: 'PHP source',
  ),
  png(
    modelIndex: 70,
    label: 'png',
    mimetype: 'image/png',
    description: 'PNG image data',
  ),
  postscript(
    modelIndex: 71,
    label: 'postscript',
    mimetype: 'application/postscript',
    description: 'PostScript document',
  ),
  powershell(
    modelIndex: 72,
    label: 'powershell',
    mimetype: 'application/x-powershell',
    description: 'Powershell source',
  ),
  ppt(
    modelIndex: 73,
    label: 'ppt',
    mimetype: 'application/vnd.ms-powerpoint',
    description: 'Microsoft PowerPoint CDF document',
  ),
  pptx(
    modelIndex: 74,
    label: 'pptx',
    mimetype:
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    description: 'Microsoft PowerPoint 2007+ document',
  ),
  python(
    modelIndex: 75,
    label: 'python',
    mimetype: 'text/x-python',
    description: 'Python source',
  ),
  pythonbytecode(
    modelIndex: 76,
    label: 'pythonbytecode',
    mimetype: 'application/x-bytecode.python',
    description: 'Python compiled bytecode',
  ),
  rar(
    modelIndex: 77,
    label: 'rar',
    mimetype: 'application/x-rar',
    description: 'RAR archive data',
  ),
  rdf(
    modelIndex: 78,
    label: 'rdf',
    mimetype: 'application/rdf+xml',
    description: 'Resource Description Framework document (RDF)',
  ),
  rpm(
    modelIndex: 79,
    label: 'rpm',
    mimetype: 'application/x-rpm',
    description: 'RedHat Package Manager archive (RPM)',
  ),
  rst(
    modelIndex: 80,
    label: 'rst',
    mimetype: 'text/x-rst',
    description: 'ReStructuredText document',
  ),
  rtf(
    modelIndex: 81,
    label: 'rtf',
    mimetype: 'text/rtf',
    description: 'Rich Text Format document',
  ),
  ruby(
    modelIndex: 82,
    label: 'ruby',
    mimetype: 'application/x-ruby',
    description: 'Ruby source',
  ),
  rust(
    modelIndex: 83,
    label: 'rust',
    mimetype: 'application/x-rust',
    description: 'Rust source',
  ),
  scala(
    modelIndex: 84,
    label: 'scala',
    mimetype: 'application/x-scala',
    description: 'Scala source',
  ),
  sevenzip(
    modelIndex: 85,
    label: 'sevenzip',
    mimetype: 'application/x-7z-compressed',
    description: '7-zip archive data',
  ),
  shell(
    modelIndex: 86,
    label: 'shell',
    mimetype: 'text/x-shellscript',
    description: 'Shell script',
  ),
  smali(
    modelIndex: 87,
    label: 'smali',
    mimetype: 'application/x-smali',
    description: 'Smali source',
  ),
  sql(
    modelIndex: 88,
    label: 'sql',
    mimetype: 'application/x-sql',
    description: 'SQL source',
  ),
  squashfs(
    modelIndex: 89,
    label: 'squashfs',
    mimetype: 'application/octet-stream',
    description: 'Squash filesystem',
  ),
  svg(
    modelIndex: 90,
    label: 'svg',
    mimetype: 'image/svg+xml',
    description: 'SVG Scalable Vector Graphics image data',
  ),
  swf(
    modelIndex: 91,
    label: 'swf',
    mimetype: 'application/x-shockwave-flash',
    description: 'Macromedia Flash data',
  ),
  symlink(
    modelIndex: 92,
    label: 'symlink',
    mimetype: 'inode/symlink',
    description: 'Symbolic link to <path>',
  ),
  symlinktext(
    modelIndex: 93,
    label: 'symlinktext',
    mimetype: 'text/plain',
    description: 'Symbolic link (textual representation)',
  ),
  tar(
    modelIndex: 94,
    label: 'tar',
    mimetype: 'application/x-tar',
    description: 'POSIX tar archive',
  ),
  tga(
    modelIndex: 95,
    label: 'tga',
    mimetype: 'image/x-tga',
    description: 'Targa image data',
  ),
  tiff(
    modelIndex: 96,
    label: 'tiff',
    mimetype: 'image/tiff',
    description: 'TIFF image data',
  ),
  torrent(
    modelIndex: 97,
    label: 'torrent',
    mimetype: 'application/x-bittorrent',
    description: 'BitTorrent file',
  ),
  ttf(
    modelIndex: 98,
    label: 'ttf',
    mimetype: 'font/sfnt',
    description: 'TrueType Font data',
  ),
  txt(
    modelIndex: 99,
    label: 'txt',
    mimetype: 'text/plain',
    description: 'Generic text document',
  ),
  unknown(
    modelIndex: 100,
    label: 'unknown',
    mimetype: 'application/octet-stream',
    description: 'Unknown binary data',
  ),
  vba(
    modelIndex: 101,
    label: 'vba',
    mimetype: 'text/vbscript',
    description: 'MS Visual Basic source (VBA)',
  ),
  wav(
    modelIndex: 102,
    label: 'wav',
    mimetype: 'audio/x-wav',
    description: 'Waveform Audio file (WAV)',
  ),
  webm(
    modelIndex: 103,
    label: 'webm',
    mimetype: 'video/webm',
    description: 'WebM data',
  ),
  webp(
    modelIndex: 104,
    label: 'webp',
    mimetype: 'image/webp',
    description: 'WebP data',
  ),
  winregistry(
    modelIndex: 105,
    label: 'winregistry',
    mimetype: 'text/x-ms-regedit',
    description: 'Windows Registry text',
  ),
  wmf(
    modelIndex: 106,
    label: 'wmf',
    mimetype: 'image/wmf',
    description: 'Windows metafile',
  ),
  xar(
    modelIndex: 107,
    label: 'xar',
    mimetype: 'application/x-xar',
    description: 'XAR archive compressed data',
  ),
  xls(
    modelIndex: 108,
    label: 'xls',
    mimetype: 'application/vnd.ms-excel',
    description: 'Microsoft Excel CDF document',
  ),
  xlsb(
    modelIndex: 109,
    label: 'xlsb',
    mimetype:
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    description: 'Microsoft Excel 2007+ document (binary format)',
  ),
  xlsx(
    modelIndex: 110,
    label: 'xlsx',
    mimetype:
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    description: 'Microsoft Excel 2007+ document',
  ),
  xml(
    modelIndex: 111,
    label: 'xml',
    mimetype: 'text/xml',
    description: 'XML document',
  ),
  xpi(
    modelIndex: 112,
    label: 'xpi',
    mimetype: 'application/zip',
    description: 'Compressed installation archive (XPI)',
  ),
  xz(
    modelIndex: 113,
    label: 'xz',
    mimetype: 'application/x-xz',
    description: 'XZ compressed data',
  ),
  yaml(
    modelIndex: 114,
    label: 'yaml',
    mimetype: 'application/x-yaml',
    description: 'YAML source',
  ),
  zip(
    modelIndex: 115,
    label: 'zip',
    mimetype: 'application/zip',
    description: 'Zip archive data',
  ),
  zlibstream(
      modelIndex: 116,
      label: 'zlibstream',
      mimetype: 'application/zlib',
      description: 'zlib compressed data');

  const MagikaType(
      {required this.modelIndex,
      required this.label,
      required this.mimetype,
      required this.description});

  final int modelIndex;
  final String label;
  final String mimetype;
  final String description;
}
