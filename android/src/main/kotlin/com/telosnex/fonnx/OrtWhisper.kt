package com.telosnex.fonnx

import ai.onnxruntime.*
import android.util.Log
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.IntBuffer
import java.nio.LongBuffer


class OrtWhisper(private val modelPath: String) {
    private val model: OrtSessionObjects by lazy {
        OrtSessionObjects(modelPath, true)
    }

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

    fun getTranscription(audioBytes: ByteArray): String? {
        try {
            val ortEnv = model.ortEnv
            val session = model.ortSession
            val maxLengthData = OnnxTensor.createTensor(ortEnv, IntBuffer.wrap(intArrayOf(200)), longArrayOf(1))
            val minLengthData = OnnxTensor.createTensor(ortEnv, IntBuffer.wrap(intArrayOf(0)), longArrayOf(1))
            val numBeamsData = OnnxTensor.createTensor(ortEnv, IntBuffer.wrap(intArrayOf(2)), longArrayOf(1))
            val numReturnSequencesData = OnnxTensor.createTensor(ortEnv, IntBuffer.wrap(intArrayOf(1)), longArrayOf(1))
            val lengthPenaltyData = OnnxTensor.createTensor(ortEnv, FloatBuffer.wrap(floatArrayOf(1.0f)), longArrayOf(1))
            val repetitionPenaltyData = OnnxTensor.createTensor(ortEnv, FloatBuffer.wrap(floatArrayOf(1.0f)), longArrayOf(1))
            val logitsProcessorData = OnnxTensor.createTensor(ortEnv, IntBuffer.wrap(intArrayOf(0)), longArrayOf(1))
            val audioFloats = convertAudioBytesToFloats(audioBytes)
            val audioPcmTensor = OnnxTensor.createTensor(ortEnv, FloatBuffer.wrap(audioFloats), longArrayOf(1, audioFloats.size.toLong()))

            val inputs = mapOf(
                "audio_pcm" to audioPcmTensor,
                "max_length" to maxLengthData,
                "min_length" to minLengthData,
                "num_beams" to numBeamsData,
                "num_return_sequences" to numReturnSequencesData,
                "length_penalty" to lengthPenaltyData,
                "repetition_penalty" to repetitionPenaltyData,
                "logits_processor" to logitsProcessorData
            )

            val outputNames = setOf("str")
            val startTimestamp = System.currentTimeMillis()
            val result = session.run(inputs, outputNames)
            val endTimestamp = System.currentTimeMillis()
            Log.d("[OrtWhisper.kt]", "Time taken to run inference: ${endTimestamp - startTimestamp}ms")
            val output = result.get("str").get().value as Array<Array<String>> // Assuming output is non-null and has at least one element
            // Assuming output is non-null and has at least one element
            val transcript = output?.firstOrNull()?.firstOrNull()
            return transcript
        } catch (e: Exception) {
            Log.e("[OrtWhisper.kt]", "Error in getTranscription: ${e.message}")
            return null
        }
    }
}