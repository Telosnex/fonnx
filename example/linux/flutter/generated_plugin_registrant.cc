//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <fonnx/fonnx_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) fonnx_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FonnxPlugin");
  fonnx_plugin_register_with_registrar(fonnx_registrar);
}
