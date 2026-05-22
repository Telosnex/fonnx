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

class OrtMiniLm(private val modelPath: String) {
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

                    // Try different output names in order of preference
                    // The model might have "last_hidden_state" (3D) or "sentence_embedding" (2D) or "embeddings" (2D)
                    val outputNames = listOf("last_hidden_state", "sentence_embedding", "embeddings")
                    var outputName: String? = null
                    var output: OrtSession.Result? = null
                    var outputValue: Any? = null
                    
                    // Find the first available output name by trying to run inference
                    for (name in outputNames) {
                        try {
                            output = model.ortSession.run(inputMap, setOf(name))
                            outputName = name
                            outputValue = output.get(name).get().value
                            break
                        } catch (e: Exception) {
                            // Try next output name
                            continue
                        }
                    }
                    
                    if (output == null || outputName == null || outputValue == null) {
                        throw IllegalStateException("Could not find valid output name. Tried: $outputNames")
                    }
                    
                    // Handle different output shapes:
                    // - 3D: [batch, sequence_length, hidden_size] - extract first token (CLS) at index [0][0]
                    // - 2D: [batch, hidden_size] - use first batch element [0]
                    // - 1D: [hidden_size] - use directly
                    val embedding: FloatArray = try {
                        when {
                            // Check for 3D array: Array<Array<FloatArray>> - shape [batch][sequence][hidden]
                            outputValue is Array<*> && 
                            outputValue.isNotEmpty() && 
                            outputValue[0] is Array<*> -> {
                                // 3D array: [1][128][384] -> extract [0][0] -> [384]
                                val batch = outputValue[0] as Array<*>
                                val firstToken = batch[0]
                                when (firstToken) {
                                    is FloatArray -> firstToken
                                    else -> throw IllegalStateException("Expected FloatArray in 3D output[0][0], got: ${firstToken?.let { it::class.java } ?: "null"}")
                                }
                            }
                            // Check for 2D array: Array<FloatArray> - shape [batch][hidden]
                            outputValue is Array<*> && 
                            outputValue.isNotEmpty() && 
                            outputValue[0] is FloatArray -> {
                                // 2D array: [1][384] -> extract [0] -> [384]
                                outputValue[0] as FloatArray
                            }
                            // Check for 1D array: FloatArray - shape [hidden]
                            outputValue is FloatArray -> {
                                // 1D array: [384] -> use directly
                                outputValue
                            }
                            else -> throw IllegalStateException("Unexpected output type or shape: ${outputValue::class.java}")
                        }
                    } catch (e: ClassCastException) {
                        throw IllegalStateException(
                            "Failed to extract embedding from model output. " +
                            "Output type: ${outputValue::class.java}, " +
                            "Output name: $outputName. " +
                            "Expected: FloatArray, Array<FloatArray>, or Array<Array<FloatArray>>. " +
                            "Error: ${e.message}"
                        )
                    }

                    val stopTime = System.nanoTime()

                    return arrayOf(embedding)
                }
            } 
        } 
    }
}
