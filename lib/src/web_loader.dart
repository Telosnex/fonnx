import 'dart:js_interop';

import 'web_config.dart';
import 'web_runtime.g.dart';

final _loaded = <String, Future<void>>{};

/// Imports the init module [name] of the FONNX web runtime once, with the
/// query `v=<webRuntimeVersion>` (ADR 002 D7). The module defines the
/// `window` functions of its model. A failed import is retried on the next
/// call.
Future<void> loadFonnxWebModule(String name) {
  return _loaded[name] ??= () async {
    try {
      await importModule(fonnxWebModuleUrl(name).toString().toJS).toDart;
    } catch (_) {
      _loaded.remove(name);
      rethrow;
    }
  }();
}

/// The URL of the web runtime file [name]: [FonnxWeb.runtimeUri] resolved
/// against the document base URI, with the query `v=<webRuntimeVersion>`.
Uri fonnxWebModuleUrl(String name, {String? baseUri}) =>
    Uri.parse(baseUri ?? _documentBaseUri)
        .resolveUri(FonnxWeb.runtimeUri)
        .resolve(name)
        .replace(queryParameters: {'v': webRuntimeVersion});

@JS('document.baseURI')
external String get _documentBaseUri;
