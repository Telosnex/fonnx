#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint fonnx.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'fonnx'
  s.version          = '0.0.1'
  s.summary          = 'Flutter plugin for ONNX runtime'
  s.description      = <<-DESC
A new Flutter plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Telanexus' => 'jpohhhh@gmail.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'

  s.vendored_libraries = "onnx_runtime/**/*.dylib"
  s.static_framework = true
end
