/// Reads a file under test/ on the VM and in the browser. The browser test
/// server serves test/ at the root.
library;

export 'test_files_io.dart' if (dart.library.js_interop) 'test_files_web.dart';
