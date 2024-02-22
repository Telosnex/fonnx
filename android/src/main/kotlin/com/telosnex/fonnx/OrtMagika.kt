package com.telosnex.fonnx

import ai.onnxruntime.*
import android.util.Log

class OrtMagika(private val modelPath: String) {
    private val model: OrtSessionObjects by lazy {
        OrtSessionObjects(modelPath, false)
    }

    fun doInference(fileBytes: FloatArray): FloatArray? {
        try {
            val ortEnv = model.ortEnv
            val session = model.ortSession
            val batchSize = 1
            val inputs = mutableMapOf<String, OnnxTensor>()
            inputs["bytes"] = OnnxTensor.createTensor(ortEnv, arrayOf(fileBytes))
            val outputName = "target_label"
            val outputNames = setOf(outputName)
            session?.let {
                val startTime = System.currentTimeMillis()
                val rawResult = it.run(inputs, outputNames)
                val endTime = System.currentTimeMillis()
                Log.d("[OrtMagika.kt]", "Inference time: ${endTime - startTime} ms")
                val targetLabel = rawResult.get(outputName).get().value as? Array<FloatArray>
                return targetLabel?.get(0)
            }
            return null
        } catch (e: Exception) {
            Log.e("[OrtMagika.kt]", "Error in doInference: ${e.message}")
            return null
        }
    }
}
