package com.telosnex.fonnx
import kotlinx.coroutines.*
import kotlin.coroutines.*

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class FonnxPlugin : FlutterPlugin, MethodCallHandler {
    private val mainScope = CoroutineScope(Dispatchers.Main)

    var cachedMiniLmPath: String? = null
    var cachedMiniLm: OrtMiniLm? = null
    var cachedWhisperPath: String? = null
    var cachedWhisper: OrtWhisper? = null
    var cachedSileroVadPath: String? = null
    var cachedSileroVad: OrtVad? = null

    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "fonnx")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        mainScope.launch {
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
                    launch(Dispatchers.Default) {
                        val audio = audioBytes.map { it.toByte() }.toByteArray()
                        val resultBytes = whisper.getTranscription(audio)
                        launch(Dispatchers.Main) {
                            result.success(resultBytes)
                        }
                    }
                } else {
                    result.error("Whisper", "Could not instantiate model", null)
                }
            } else if (call.method == "sileroVad") {
                val list = call.arguments as List<Any>
                val modelPath = list[0] as String
                val audioBytes = list[1] as ByteArray
                val previousState = list[2] as HashMap<String, Any>
                if (cachedSileroVadPath != modelPath) {
                    cachedSileroVad = OrtVad(modelPath)
                    cachedSileroVadPath = modelPath
                }
                val vad = cachedSileroVad

                if (vad != null) {
                    launch(Dispatchers.Default) {
                        val audio = audioBytes.map { it.toByte() }.toByteArray()
                        val resultBytes = vad.doInference(audio, previousState)
                        launch(Dispatchers.Main) {
                            result.success(resultBytes)
                        }
                    }
                } else {
                    result.error("SileroVad", "Could not instantiate model", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
