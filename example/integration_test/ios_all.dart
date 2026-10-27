// Every integration test in one app, for iOS: each flutter test target is
// an Xcode build, an install of the 1.5 GB app and a launch (about 5 min on
// a CI simulator). Not *_test.dart, so the desktop and Android loops over
// integration_test/*_test.dart skip it.
import 'keyword_spotter_integration_test.dart' as keyword_spotter;
import 'plugin_integration_test.dart' as plugin;

void main() {
  plugin.main();
  keyword_spotter.main();
}
