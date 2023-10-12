package com.telosnex.fonnx

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class FonnxPlugin : FlutterPlugin, MethodCallHandler {
    var cachedMiniLmL6V2Path: String? = null
    var cachedMiniLmL6V2: MiniLmL6V2? = null

    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "fonnx")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        if (call.method == "getPlatformVersion") {
            result.success("Android ${android.os.Build.VERSION.RELEASE}")
        } else if (call.method == "miniLmL6V2") {
            val list = call.arguments as List<Any>
            val modelPath = list[0] as String
            val wordpieces = list[1] as List<Int>

            if (cachedMiniLmL6V2Path != modelPath) {
                cachedMiniLmL6V2 = MiniLmL6V2(modelPath)
                cachedMiniLmL6V2Path = modelPath
            }

            val miniLmL6V2 = cachedMiniLmL6V2
            if (miniLmL6V2 != null) {
                val embedding = miniLmL6V2.getEmbedding(wordpieces.map { it.toLong() }.toLongArray())
                result.success(embedding.first())
            } else {
                result.error("MiniLmL6V2", "Could not instantiate model", null)
            }
        } else {
            result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
