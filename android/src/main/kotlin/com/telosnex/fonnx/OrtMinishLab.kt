package com.telosnex.fonnx

import ai.onnxruntime.*
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import kotlinx.coroutines.*
import java.nio.LongBuffer
import java.util.*

class OrtMinishLab(private val modelPath: String) {
    private val model: OrtSessionObjects by lazy {
        OrtSessionObjects(modelPath)
    }

    fun getEmbedding(wordpieces: LongArray): Array<FloatArray> {
        val startTime = System.nanoTime()

        // For MinishLab, the input shape is different - using 1D tensor
        val inputLength = wordpieces.size.toLong()

        // Step 1: Create the tensor for input_ids (1D tensor)
        val inputShape = longArrayOf(inputLength)
        val inputTensor =
            OnnxTensor.createTensor(
                model.ortEnv,
                LongBuffer.wrap(wordpieces),
                inputShape,
            )

        // Step 2: Create the tensor for offsets (1D tensor with single value)
        val offsetsShape = longArrayOf(1)
        val offsetsArray = LongArray(1) { 0 }
        val offsetsTensor =
            OnnxTensor.createTensor(
                model.ortEnv,
                LongBuffer.wrap(offsetsArray),
                offsetsShape,
            )

        inputTensor.use { inputTensor ->
            offsetsTensor.use { offsetsTensor ->
                // Step 3: Call the ort inferenceSession run
                val inputMap = mutableMapOf<String, OnnxTensor>()
                inputMap["input_ids"] = inputTensor
                inputMap["offsets"] = offsetsTensor

                val outputName = "embeddings"

                val output = model.ortSession.run(inputMap, setOf(outputName))

                val wrappedResult =
                    output.get(outputName).get().value as Array<FloatArray>

                val stopTime = System.nanoTime()

                return wrappedResult
            }
        }
    }
}