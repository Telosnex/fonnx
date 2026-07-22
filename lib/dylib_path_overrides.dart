// Diagnostic escape hatches for hosts that intentionally provide their own
// ONNX Runtime libraries. Normal Flutter builds must leave these null: the
// package's native-assets hook supplies pinned, SHA-256-verified libraries.
//
// Kept in a dart:ffi-free file so packages with native and web tests can import
// configuration without making the web compiler parse FFI declarations.

String? fonnxOrtDylibPathOverride;
String? fonnxOrtExtensionsDylibPathOverride;
