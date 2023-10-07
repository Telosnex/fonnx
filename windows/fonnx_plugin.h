#ifndef FLUTTER_PLUGIN_FONNX_PLUGIN_H_
#define FLUTTER_PLUGIN_FONNX_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace fonnx {

class FonnxPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  FonnxPlugin();

  virtual ~FonnxPlugin();

  // Disallow copy and assign.
  FonnxPlugin(const FonnxPlugin&) = delete;
  FonnxPlugin& operator=(const FonnxPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace fonnx

#endif  // FLUTTER_PLUGIN_FONNX_PLUGIN_H_
