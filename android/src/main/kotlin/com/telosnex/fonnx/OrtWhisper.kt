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

            val byteBuffer = ByteBuffer.wrap(audioBytes).order(ByteOrder.nativeOrder())
            val audioStreamTensor = OnnxTensor.createTensor(ortEnv, byteBuffer, longArrayOf(1, audioBytes.size.toLong()), OnnxJavaType.UINT8)
            // val audioStreamTensor = OnnxTensor.createTensor(ortEnv, ByteBuffer.wrap(audioBytes), longArrayOf(1, audioBytes.size.toLong()))

            val inputs = mapOf(
                "audio_stream" to audioStreamTensor,
                "max_length" to maxLengthData,
                "min_length" to minLengthData,
                "num_beams" to numBeamsData,
                "num_return_sequences" to numReturnSequencesData,
                "length_penalty" to lengthPenaltyData,
                "repetition_penalty" to repetitionPenaltyData
            )

            val outputNames = setOf("str")
            val result = session.run(inputs, outputNames)
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