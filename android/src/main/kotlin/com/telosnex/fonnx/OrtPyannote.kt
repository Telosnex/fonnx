package com.telosnex.fonnx

import ai.onnxruntime.*
import android.util.Log
import kotlin.math.exp
import kotlin.math.min

class OrtPyannote(private val modelPath: String) {
    private val model: OrtSessionObjects by lazy {
        OrtSessionObjects(modelPath, true)
    }

    companion object {
        private const val SAMPLE_RATE = 16000
        private const val DURATION = 160000 // 10 seconds window
        private const val NUM_SPEAKERS = 3
    }

    fun process(audioData: FloatArray): List<Map<String, Any>>? {
        try {
            val ortEnv = model.ortEnv
            val session = model.ortSession
            val step = min(DURATION / 2, (0.9 * DURATION).toInt())
            val results = mutableListOf<Map<String, Any>>()
            
            val isActive = BooleanArray(NUM_SPEAKERS) { false }
            val startSamples = IntArray(NUM_SPEAKERS) { 0 }
            var currentSamples = 721

            // Calculate overlap size
            val overlap = sampleToFrame(DURATION - step)
            var overlapChunk = Array(overlap) { DoubleArray(NUM_SPEAKERS) { 0.0 } }

            // Create sliding windows
            val windows = createSlidingWindows(audioData, DURATION, step)

            session?.let {
                for ((windowIndex, window) in windows.withIndex()) {
                    val (windowSize, windowData) = window
                    // Log.d("[OrtPyannote.kt]", "Processing window $windowIndex of ${windows.size}; this window has ${windowData.size} samples")
                    // Prepare input tensor
                    val inputs = mutableMapOf<String, OnnxTensor>()
                    inputs["input_values"] = OnnxTensor.createTensor(
                        ortEnv,
                        arrayOf(arrayOf(windowData))
                    )

                    val startTime = System.currentTimeMillis()
                    val rawResult = it.run(inputs, setOf("logits"))
                    val endTime = System.currentTimeMillis()
                    // Log.d("[OrtPyannote.kt]", "Inference time: ${endTime - startTime} ms")

                    // Process output
                    val logits = rawResult.get("logits").get().value as Array<Array<FloatArray>>
                    // Log.d("[OrtPyannote.kt]", "Logits shape: ${logits.size} x ${logits[0].size} x ${logits[0][0].size}")
                    // Log.d("[OrtPyannote.kt]", "Logits: ${logits[0][0].joinToString(", ")}")
                    var frameOutputs = processOutputData(logits)
                    // Log.d("[OrtPyannote.kt]", "Frame outputs: ${frameOutputs.size}")

                    // Handle overlapping
                    if (windowIndex > 0) {
                        frameOutputs = reorderAndBlend(overlapChunk, frameOutputs)
                    }

                    if (windowIndex < windows.size - 1) {
                        overlapChunk = frameOutputs.takeLast(overlap).toTypedArray()
                        frameOutputs = frameOutputs.dropLast(overlap)
                    } else {
                        frameOutputs = frameOutputs.take(
                            min(frameOutputs.size, sampleToFrame(windowSize))
                        )
                    }

                    // Track speaker segments
                    for (probs in frameOutputs) {
                        currentSamples += 270
                        for (speaker in 0 until NUM_SPEAKERS) {
                            if (isActive[speaker]) {
                                if (probs[speaker] < 0.5) {
                                    results.add(mapOf(
                                        "speaker" to speaker,
                                        "start" to (startSamples[speaker].toDouble() / SAMPLE_RATE),
                                        "stop" to (currentSamples.toDouble() / SAMPLE_RATE)
                                    ))
                                    isActive[speaker] = false
                                }
                            } else if (probs[speaker] > 0.5) {
                                startSamples[speaker] = currentSamples
                                isActive[speaker] = true
                            }
                        }
                    }
                }
            }

            // Handle any remaining active speakers
            for (speaker in 0 until NUM_SPEAKERS) {
                if (isActive[speaker]) {
                    results.add(mapOf(
                        "speaker" to speaker,
                        "start" to (startSamples[speaker].toDouble() / SAMPLE_RATE),
                        "stop" to (currentSamples.toDouble() / SAMPLE_RATE)
                    ))
                }
            }

            return results
        } catch (e: Exception) {
            Log.e("[OrtPyannote.kt]", "Error in process: ${e.message}")
            e.printStackTrace()
            return null
        }
    }

    private fun sampleToFrame(samples: Int): Int {
        return (samples - 721) / 270
    }

    private fun frameToSample(frames: Int): Int {
        return (frames * 270) + 721
    }

    private fun createSlidingWindows(
        audioData: FloatArray,
        windowSize: Int,
        stepSize: Int
    ): List<Pair<Int, FloatArray>> {
        val windows = mutableListOf<Pair<Int, FloatArray>>()
        var start = 0

        while (start <= audioData.size - windowSize) {
            windows.add(Pair(
                windowSize,
                audioData.slice(start until start + windowSize).toFloatArray()
            ))
            start += stepSize
        }

        // Handle last window if needed
        if (audioData.size < windowSize || (audioData.size - windowSize) % stepSize > 0) {
            val lastWindow = audioData.slice(start until audioData.size).toFloatArray()
            val lastWindowSize = lastWindow.size

            if (lastWindow.size < windowSize) {
                val paddedWindow = FloatArray(windowSize)
                lastWindow.copyInto(paddedWindow)
                windows.add(Pair(lastWindowSize, paddedWindow))
            } else {
                windows.add(Pair(lastWindowSize, lastWindow))
            }
        }

        return windows
    }

    private fun processOutputData(logits: Array<Array<FloatArray>>): List<DoubleArray> {
        val frameOutputs = mutableListOf<DoubleArray>()
        val batchLogits = logits[0]  // First batch
        
        // Process each frame (589 frames)
        for (frame in batchLogits.indices) {
            val frameLogits = batchLogits[frame]  // Get the 7 logits for this frame
            val probs = frameLogits.map { exp(it.toDouble()) }
            
            val speakerProbs = DoubleArray(NUM_SPEAKERS)
            // Combine probabilities for each speaker
            // spk1: solo (1) + with_spk2 (4) + with_spk3 (5)
            speakerProbs[0] = probs[1] + probs[4] + probs[5]
            // spk2: solo (2) + with_spk1 (4) + with_spk3 (6)
            speakerProbs[1] = probs[2] + probs[4] + probs[6]
            // spk3: solo (3) + with_spk1 (5) + with_spk2 (6)
            speakerProbs[2] = probs[3] + probs[5] + probs[6]
            
            frameOutputs.add(speakerProbs)
        }
    
        return frameOutputs
    }

    private fun reorderAndBlend(
        overlapChunk: Array<DoubleArray>,
        newFrames: List<DoubleArray>
    ): List<DoubleArray> {
        val reorderedFrames = reorder(overlapChunk.toList(), newFrames)
        
        // Blend overlapping sections
        for (i in overlapChunk.indices) {
            for (j in 0 until NUM_SPEAKERS) {
                reorderedFrames[i][j] = (reorderedFrames[i][j] + overlapChunk[i][j]) / 2.0
            }
        }
        
        return reorderedFrames
    }

    private fun reorder(
        x: List<DoubleArray>,
        y: List<DoubleArray>
    ): List<DoubleArray> {
        val perms = generatePermutations(NUM_SPEAKERS)
        val yTransposed = transpose(y)
        
        var minDiff = Double.POSITIVE_INFINITY
        var bestPerm = y
        
        for (perm in perms) {
            val permuted = List(y.size) { i ->
                DoubleArray(NUM_SPEAKERS) { j ->
                    yTransposed[perm[j]][i]
                }
            }
            
            var diff = 0.0
            for (i in x.indices) {
                for (j in 0 until NUM_SPEAKERS) {
                    diff += kotlin.math.abs(x[i][j] - permuted[i][j])
                }
            }
            
            if (diff < minDiff) {
                minDiff = diff
                bestPerm = permuted
            }
        }
        
        return bestPerm
    }

    private fun generatePermutations(n: Int): List<List<Int>> {
        if (n == 1) {
            return listOf(listOf(0))
        }
        
        val result = mutableListOf<List<Int>>()
        for (i in 0 until n) {
            val subPerms = generatePermutations(n - 1)
            for (perm in subPerms) {
                val newPerm = listOf(i) + perm.map { if (it >= i) it + 1 else it }
                result.add(newPerm)
            }
        }
        return result
    }

    private fun transpose(matrix: List<DoubleArray>): List<DoubleArray> {
        if (matrix.isEmpty()) return emptyList()
        val rows = matrix.size
        val cols = matrix[0].size
        
        return List(cols) { j ->
            DoubleArray(rows) { i ->
                matrix[i][j]
            }
        }
    }
}