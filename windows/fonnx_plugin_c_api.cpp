#include "include/fonnx/fonnx_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "fonnx_plugin.h"

void FonnxPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  fonnx::FonnxPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
