#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint fonnx.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'fonnx'
  s.version          = '1.0.0'
  s.summary          = 'Flutter macOS plugin implementing ONNX runtime.'
  s.description      = <<-DESC
Your model, everywhere.

Fonnx brings the power of ONNX runtime to Flutter. It allows you to run your ONNX models on every platform supported by Flutter.
                       DESC
  s.homepage         = 'http://telosnex.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Telosnex' => 'info@telosnex.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.13'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'

  s.vendored_libraries = "onnx_runtime/osx/*.dylib"
  s.static_framework = true
end
