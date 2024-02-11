package com.telosnex.fonnx

import android.util.Log
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import ai.onnxruntime.extensions.OrtxPackage
import ai.onnxruntime.providers.NNAPIFlags
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import kotlinx.coroutines.*
import java.nio.LongBuffer
import java.util.*

internal class OrtSessionObjects(private val modelPath: String, private val isOrtExtensionsEnabled: Boolean = false) {
    private var _ortSession: OrtSession? = null
    public val ortSession: OrtSession
        get() = _ortSession ?: throw UninitializedPropertyAccessException("OrtSession has not been initialized")

    private val _ortEnv: OrtEnvironment = OrtEnvironment.getEnvironment()
    public val ortEnv: OrtEnvironment 
        get() = _ortEnv

    init {
        val sessionOptions: OrtSession.SessionOptions = OrtSession.SessionOptions()
        if (isOrtExtensionsEnabled) {
            sessionOptions.registerCustomOpLibrary(OrtxPackage.getLibraryPath());
        }        
        _ortSession = ortEnv.createSession(modelPath, sessionOptions)
    }
}