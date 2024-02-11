package com.telosnex.fonnx

import ai.onnxruntime.*
import android.util.Log

class OrtVad(private val modelPath: String) {
    private val model: OrtSessionObjects by lazy {
        OrtSessionObjects(modelPath, false)
    }

    fun doInference(
        audioBytes: ByteArray,
        previousState: HashMap<String, Any> = HashMap(),
    ): HashMap<String, Any>? {
        try {
            val ortEnv = model.ortEnv
            val session = model.ortSession
            val resultMap = HashMap<String, Any>()

            fun convertAudioBytesToFloats(audioBytes: ByteArray): FloatArray {
                // Initialize a FloatArray of half the size of audioBytes,
                // since we're combining each pair of bytes into one float.
                val audioData = FloatArray(audioBytes.size / 2)

                for (i in audioData.indices) {
                    // Combine two bytes to form a 16-bit integer value
                    var valInt = (
                        (audioBytes[i * 2].toInt() and 0xFF) or
                            (audioBytes[i * 2 + 1].toInt() shl 8)
                    )

                    // Interpret the 16-bit integer as a signed value and normalize
                    if (valInt > 0x7FFF) {
                        valInt -= 0x10000
                    }

                    // Normalize to [-1.0, 1.0] range for float32 representation
                    audioData[i] = valInt / 32767.0f
                }

                return audioData
            }

            val audioData = convertAudioBytesToFloats(audioBytes)
            val batchSize = 1
            val sampleRate = longArrayOf(16000)
            var h: Array<Array<FloatArray>>? = transformToFloatArray3D(previousState["hn"])
            var c: Array<Array<FloatArray>>? = transformToFloatArray3D(previousState["cn"])

            if (h == null || c == null) {
                Log.d("[OrtVad.kt]", "previous LTSM state is null, initializing them to zero arrays.")
                Log.d("[OrtVad.kt]", "keys: ${previousState.keys}")
                Log.d("[OrtVad.kt]", "runtime types: ${previousState["hn"]?.javaClass?.name}, ${previousState["cn"]?.javaClass?.name}")
                h = Array(2) { Array(batchSize) { FloatArray(64) { 0f } } } // Assuming h and c have same dimensions
                c = h.clone()
            }

            val inputs = mutableMapOf<String, OnnxTensor>()
            inputs["input"] = OnnxTensor.createTensor(ortEnv, arrayOf(audioData))
            inputs["sr"] = OnnxTensor.createTensor(ortEnv, longArrayOf(16000))
            inputs["h"] = OnnxTensor.createTensor(ortEnv, h)
            inputs["c"] = OnnxTensor.createTensor(ortEnv, c)

            val outputNames = setOf("output", "hn", "cn")

            session?.let {
                val startTime = System.currentTimeMillis()
                val rawResult = it.run(inputs, outputNames)
                val endTime = System.currentTimeMillis()
                Log.d("[OrtVad.kt]", "Inference time: ${endTime - startTime} ms")

                // Directly extracting values using keys from 'outputNames' to avoid 'keys' reference issue
                val output = rawResult.get("output").get().value as? Array<FloatArray>
                val hn = rawResult.get("hn").get().value as? Array<Array<FloatArray>>
                val cn = rawResult.get("cn").get().value as? Array<Array<FloatArray>>

                val processedMap = hashMapOf<String, Any>()
                output?.let { processedMap["output"] = it.toList().first() }
                hn?.let { processedMap["hn"] = it.toList().map { it.toList().map { it.toList() } } } // Adjust as per the reshaping logic
                cn?.let { processedMap["cn"] = it.toList().map { it.toList().map { it.toList() } } } // Adjust as per the reshaping logic

                return processedMap
            }

            return resultMap
        } catch (e: Exception) {
            Log.e("[OrtVad.kt]", "Error in doInference: ${e.message}")
            return null
        }
    }

    @Suppress("UNCHECKED_CAST")
fun transformToFloatArray3D(list: Any?): Array<Array<FloatArray>>? {
    return try {
        (list as? List<List<List<Float>>>)?.map { layer2 ->
            layer2.map { layer1 ->
                layer1.toFloatArray()
            }.toTypedArray()
        }?.toTypedArray()
    } catch (e: Exception) {
        null // Return null if the conversion fails
    }
}
}
