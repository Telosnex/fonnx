#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint fonnx.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'fonnx'
  s.version          = '1.0.0'
  s.summary          = 'Flutter iOS plugin implementing ONNX runtime.'
  s.description      = <<-DESC
Your model, everywhere.

Fonnx brings the power of ONNX runtime to Flutter. It allows you to run your ONNX models on every platform supported by Flutter.
                       DESC
  s.homepage         = 'http://telosnex.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Telosnex' => 'info@telosnex.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'onnxruntime-objc'
  # For ONNX runtime: Addresses build error [!] The 'Pods-Runner' target has transitive dependencies that include statically linked binaries: (onnxruntime-objc and onnxruntime-c)
  s.static_framework = true
  # Originally: 11.0. 
  # Upgrade to 13.0 to get Swift async support.
  # Upgrade to 14.0 to get os_log support.
  s.platform = :ios, '14.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
