import 'dart:ffi';

import 'wolf_defender.dart';
import 'wolf_defender_isolate.dart';

WolfDefender getWolfDefender(WolfDefenderBundle bundle) =>
    WolfDefenderNative(bundle);

WolfDefenderModel wolfDefenderModelForPlatform() => switch (Abi.current()) {
  Abi.androidX64 ||
  Abi.androidIA32 ||
  Abi.linuxX64 ||
  Abi.linuxIA32 ||
  Abi.macosX64 ||
  Abi.windowsX64 ||
  Abi.windowsIA32 ||
  Abi.iosX64 ||
  Abi.fuchsiaX64 => WolfDefenderModel.int8Int4X86,
  _ => WolfDefenderModel.int8Int4,
};

class WolfDefenderNative implements WolfDefender {
  WolfDefenderNative(this.bundle);

  final WolfDefenderIsolateManager _manager = WolfDefenderIsolateManager();
  Future<void> _pending = Future<void>.value();

  @override
  final WolfDefenderBundle bundle;

  @override
  Future<WolfDefenderResult> classify(String text) => _enqueue(() async {
    await _manager.start(bundle);
    return _manager.classify(text);
  });

  /// Runs one classification at a time in the isolate.
  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }
}
