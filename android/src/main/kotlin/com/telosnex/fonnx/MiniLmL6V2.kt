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

class MiniLmL6V2(private val modelPath: String) {
    private val model: OrtSessionObjects by lazy {
        OrtSessionObjects(modelPath)
    }

    fun getEmbedding(wordpieces: LongArray): Array<FloatArray> {
        val startTime = System.nanoTime()

        val batchCount = 1L
        val inputLength = wordpieces.size.toLong()

        // Step 1: Create the tensor for input_ids.
        val shape = longArrayOf(batchCount, inputLength)
        val inputTensor =
            OnnxTensor.createTensor(
                model.ortEnv,
                LongBuffer.wrap(wordpieces),
                shape,
            )

        // Step 2: Create the tensor for token_type_ids
        val tokenTypeIdsBytes = LongArray(inputLength.toInt()) { 0 }
        val tokenTypeIdsTensor =
            OnnxTensor.createTensor(
                model.ortEnv,
                LongBuffer.wrap(tokenTypeIdsBytes),
                shape,
            )

        // Step 3: Create the tensor for attention_mask
        val attentionMaskBytes = LongArray(inputLength.toInt()) { 1 }
        val attentionMaskTensor =
            OnnxTensor.createTensor(
                model.ortEnv,
                LongBuffer.wrap(attentionMaskBytes),
                shape,
            )
        inputTensor.use { inputTensor ->
            tokenTypeIdsTensor.use { tokenTypeIdsTensor ->
                attentionMaskTensor.use { attentionMaskTensor ->
                    // Step 3: Call the ort inferenceSession run
                    val inputMap = mutableMapOf<String, OnnxTensor>()
                    inputMap["input_ids"] = inputTensor
                    inputMap["token_type_ids"] = tokenTypeIdsTensor
                    inputMap["attention_mask"] = attentionMaskTensor

                    val outputName = "embeddings"

                    val output = model.ortSession.run(inputMap, setOf(outputName))

                    val wrappedResult =
                        output.get(outputName).get().value as Array<FloatArray>

                    val stopTime = System.nanoTime()

                    Log.v("MiniLmL6V2", "Time taken: ${(stopTime - startTime) / 1_000_000.0} ms")
                    return wrappedResult
                }
            } 
        } 
    }
}
