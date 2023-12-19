// Useful for unit testing things that depend on this package.
//
// Unit tests can only look up assets from their package or in the depending
// package.
//
// Fonnx shouldn't list all of the ORT dylibs as assets: then, every build would
// contain the ~60 MB of dylibs.
//
// You can set these global constants to point to the dylib path in the
// cache created by `flutter pub get`.
//
// Luckily, Flutter creates symlinks to the cache from the app's folder.
//
// For example, in my app running on Windows, I can set the path to:
//  fonnxOrtDylibPathOverride =
//          '${Directory.current.path}\\windows\\flutter\\ephemeral\\.plugin_symlinks\\fonnx\\windows\\onnx_runtime\\onnxruntime-x64.dll';
//
// Directory.current.path seems to always be the apps root folder.
//
//
// One last note: this is in a separate file to prevent issues with apps that
// run on web and native. For example, a more natural place is ort.dart.
// However, if ort.dart is imported into a test file, and that test file runs
// on web, then the test will fail to compile because the dart:ffi library is
// not available on web, and ort.dart imports it.

String? fonnxOrtDylibPathOverride;
String? fonnxOrtExtensionsDylibPathOverride;
