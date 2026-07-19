package com.telosnex.fonnx

import ai.onnxruntime.OnnxTensor
import android.util.Log

/** Official Silero VAD v6.2.1 streaming inference. */
class OrtVad(private val modelPath: String) {
    private val model: OrtSessionObjects by lazy {
        OrtSessionObjects(modelPath, false)
    }

    fun doInference(
        audioBytes: ByteArray,
        previousState: HashMap<String, Any> = HashMap(),
    ): HashMap<String, Any>? {
        return try {
            require(audioBytes.isNotEmpty() && audioBytes.size % 2 == 0) {
                "Audio must contain a non-empty, even number of PCM16 bytes"
            }
            val audio = pcm16ToFloats(audioBytes)
            var state = previousState.floatArray("state", STATE_SIZE)
            var context = previousState.floatArray("context", CONTEXT_SAMPLES)
            val probabilities = ArrayList<Float>((audio.size + CHUNK_SAMPLES - 1) / CHUNK_SAMPLES)

            var offset = 0
            while (offset < audio.size) {
                val chunk = FloatArray(CHUNK_SAMPLES)
                val count = minOf(CHUNK_SAMPLES, audio.size - offset)
                audio.copyInto(chunk, 0, offset, offset + count)
                val input = FloatArray(CONTEXT_SAMPLES + CHUNK_SAMPLES)
                context.copyInto(input, 0)
                chunk.copyInto(input, CONTEXT_SAMPLES)

                val inputs = mutableMapOf<String, OnnxTensor>()
                inputs["input"] = OnnxTensor.createTensor(model.ortEnv, arrayOf(input))
                inputs["state"] = OnnxTensor.createTensor(
                    model.ortEnv,
                    arrayOf(arrayOf(state.copyOfRange(0, 128)), arrayOf(state.copyOfRange(128, 256))),
                )
                // The graph declares a scalar but accepts this one-value tensor.
                inputs["sr"] = OnnxTensor.createTensor(model.ortEnv, longArrayOf(SAMPLE_RATE.toLong()))

                inputs.values.useAll {
                    model.ortSession!!.run(inputs, setOf("output", "stateN")).use { result ->
                        val output = result.get("output").get().value as Array<FloatArray>
                        val stateN = result.get("stateN").get().value as Array<Array<FloatArray>>
                        probabilities.add(output[0][0])
                        state = FloatArray(STATE_SIZE)
                        stateN[0][0].copyInto(state, 0)
                        stateN[1][0].copyInto(state, 128)
                    }
                }
                context = chunk.copyOfRange(CHUNK_SAMPLES - CONTEXT_SAMPLES, CHUNK_SAMPLES)
                offset += CHUNK_SAMPLES
            }

            hashMapOf(
                "output" to probabilities.toFloatArray(),
                "state" to state,
                "context" to context,
            )
        } catch (error: Exception) {
            Log.e("[OrtVad.kt]", "Silero VAD v6 inference failed", error)
            null
        }
    }

    private fun pcm16ToFloats(bytes: ByteArray): FloatArray {
        return FloatArray(bytes.size / 2) { index ->
            val low = bytes[index * 2].toInt() and 0xff
            val high = bytes[index * 2 + 1].toInt()
            val signed = (high shl 8) or low
            signed.toShort().toFloat() / 32767.0f
        }
    }

    private fun HashMap<String, Any>.floatArray(key: String, length: Int): FloatArray {
        val value = this[key]
        val result = when (value) {
            is FloatArray -> value.copyOf()
            is List<*> -> value.map { (it as Number).toFloat() }.toFloatArray()
            else -> FloatArray(length)
        }
        return if (result.size == length) result else FloatArray(length)
    }

    private inline fun Collection<AutoCloseable>.useAll(block: () -> Unit) {
        try {
            block()
        } finally {
            forEach { it.close() }
        }
    }

    private companion object {
        const val SAMPLE_RATE = 16000
        const val CHUNK_SAMPLES = 512
        const val CONTEXT_SAMPLES = 64
        const val STATE_SIZE = 256
    }
}
