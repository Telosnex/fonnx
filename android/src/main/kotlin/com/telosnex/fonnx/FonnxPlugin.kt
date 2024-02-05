package com.telosnex.fonnx

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class FonnxPlugin : FlutterPlugin, MethodCallHandler {
    var cachedMiniLmPath: String? = null
    var cachedMiniLm: OrtMiniLm? = null
    var cachedWhisperPath: String? = null
    var cachedWhisper: OrtWhisper? = null

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
        } else if (call.method == "miniLm") {
            val list = call.arguments as List<Any>
            val modelPath = list[0] as String
            val wordpieces = list[1] as List<Int>

            if (cachedMiniLmPath != modelPath) {
                cachedMiniLm = OrtMiniLm(modelPath)
                cachedMiniLmPath = modelPath
            }

            val miniLm = cachedMiniLm
            if (miniLm != null) {
                val embedding = miniLm.getEmbedding(wordpieces.map { it.toLong() }.toLongArray())
                result.success(embedding.first())
            } else {
                result.error("MiniLm", "Could not instantiate model", null)
            }
        } else if (call.method == "whisper") {
            val list = call.arguments as List<Any>
            val modelPath = list[0] as String
            val audioBytes = list[1] as ByteArray
            if (cachedWhisperPath != modelPath) {
                cachedWhisper = OrtWhisper(modelPath)
                cachedWhisperPath = modelPath
            }
            val whisper = cachedWhisper
            if (whisper != null) {
                val audio = audioBytes.map { it.toByte() }.toByteArray()
                val resultBytes = whisper.getTranscription(audio)
                result.success(resultBytes)
            } else {
                result.error("Whisper", "Could not instantiate model", null)
            }
        } else {
            result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
