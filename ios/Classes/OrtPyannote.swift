import Flutter
import Foundation
import onnxruntime_objc
import os.log

/// OrtPyannote is a class responsible for performing speaker diarization using ONNX Runtime.
class OrtPyannote {
    /// The path to the ONNX model file.
    private let modelPath: String
    
    /// Sample rate required by Pyannote models (16kHz)
    private let sampleRate: Int64 = 16000
    
    /// Duration in samples (10 seconds window)
    private let duration: Int = 160000
    
    /// Number of speakers to detect
    private let numSpeakers: Int = 3
    
    /// Lazy instantiation of OrtSessionObjects used to manage the ONNX session.
    private lazy var model: OrtSessionObjects = {
        OrtSessionObjects(modelPath: modelPath, includeOrtExtensions: true)!
    }()
    
    /// Initializes the OrtPyannote instance with a provided model path.
    /// - Parameter modelPath: The path to the ONNX model file.
    init(modelPath: String) {
        self.modelPath = modelPath
    }
    
    /// Converts sample count to frame count.
    /// - Parameter samples: Number of samples
    /// - Returns: Number of frames
    private func sampleToFrame(_ samples: Int) -> Int {
        return (samples - 721) / 270
    }
    
    /// Converts frame count to sample count.
    /// - Parameter frames: Number of frames
    /// - Returns: Number of samples
    private func frameToSample(_ frames: Int) -> Int {
        return (frames * 270) + 721
    }
    
    /// Process audio data and return speaker segments
    /// - Parameter audioData: Array of audio samples as floating point values
    /// - Returns: Dictionary containing speaker segments with start/stop times
    func process(audioData: [Float]) -> [[String: Any]]? {
        os_log("Processing audio data")
        do {
            let session = model.session
            let step = min(duration / 2, Int(0.9 * Double(duration)))
            var results: [[String: Any]] = []
            var isActive = Array(repeating: false, count: numSpeakers)
            var startSamples = Array(repeating: 0, count: numSpeakers)
            var currentSamples = 721
            
            // Calculate overlap size
            let overlap = sampleToFrame(duration - step)
            var overlapChunk = Array(repeating: Array(repeating: 0.0, count: numSpeakers), count: overlap)
            
            // Create sliding windows
            let windows = createSlidingWindows(audioData: audioData, windowSize: duration, stepSize: step)
            
            for (windowIndex, (windowSize, window)) in windows.enumerated() {
                // Prepare input tensor
                let inputTensor = try createORTValue(
                    from: [window], elementType: .float,
                    shape: [NSNumber(value: 1), NSNumber(value: 1), NSNumber(value: window.count)])
                
                let inputs = ["input_values": inputTensor]
                let outputNames = Set(["logits"])
                os_log("Running inference for window %{public}d of %{public}d", windowIndex + 1, windows.count)
                // Run inference
                let outputs = try session.run(withInputs: inputs, outputNames: outputNames, runOptions: nil)
                
                guard let outputTensor = outputs["logits"],
                      let outputData = try? outputTensor.tensorData() as Data else {
                    continue
                }
                
                // Process output frames
                let frameOutputs = processOutputData(outputData)
                var processedFrames = frameOutputs
                
                // Handle frame overlapping
                if windowIndex > 0 {
                    processedFrames = reorderAndBlend(overlapChunk: overlapChunk, newFrames: frameOutputs)
                }
                
                if windowIndex < windows.count - 1 {
                    overlapChunk = Array(processedFrames.suffix(overlap))
                    processedFrames = Array(processedFrames.dropLast(overlap))
                } else {
                    processedFrames = Array(processedFrames.prefix(min(processedFrames.count, sampleToFrame(windowSize))))
                }
                
                // Track speaker segments
                for probs in processedFrames {
                    currentSamples += 270
                    for speaker in 0..<numSpeakers {
                        if isActive[speaker] {
                            if probs[speaker] < 0.5 {
                                results.append([
                                    "speaker": speaker,
                                    "start": Double(startSamples[speaker]) / Double(sampleRate),
                                    "stop": Double(currentSamples) / Double(sampleRate)
                                ])
                                isActive[speaker] = false
                            }
                        } else if probs[speaker] > 0.5 {
                            startSamples[speaker] = currentSamples
                            isActive[speaker] = true
                        }
                    }
                }
            }
            
            // Handle any remaining active speakers
            for speaker in 0..<numSpeakers {
                if isActive[speaker] {
                    results.append([
                        "speaker": speaker,
                        "start": Double(startSamples[speaker]) / Double(sampleRate),
                        "stop": Double(currentSamples) / Double(sampleRate)
                    ])
                }
            }
            
            return results
            
        } catch {
            os_log("Error in process: %{public}s", error.localizedDescription)
            for symbol in Thread.callStackSymbols {
                os_log("Stack trace: %{public}s", symbol)
            }
            return nil
        }
    }
    
    /// Creates sliding windows over the audio data
    /// - Parameters:
    ///   - audioData: Input audio samples
    ///   - windowSize: Size of each window
    ///   - stepSize: Step size between windows
    /// - Returns: Array of tuples containing window size and window data
    private func createSlidingWindows(audioData: [Float], windowSize: Int, stepSize: Int) -> [(Int, [Float])] {
        var windows: [(Int, [Float])] = []
        var start = 0
        
        while start <= audioData.count - windowSize {
            let window = Array(audioData[start..<(start + windowSize)])
            windows.append((windowSize, window))
            start += stepSize
        }
        
        // Handle last window if needed
        if audioData.count < windowSize || (audioData.count - windowSize) % stepSize > 0 {
            var lastWindow = Array(audioData[start...])
            let lastWindowSize = lastWindow.count
            
            if lastWindow.count < windowSize {
                lastWindow.append(contentsOf: Array(repeating: 0.0, count: windowSize - lastWindow.count))
            }
            
            windows.append((lastWindowSize, lastWindow))
        }
        
        return windows
    }
    
    /// Process raw output data into speaker probabilities
    /// - Parameter outputData: Raw tensor output data
    /// - Returns: Array of speaker probability arrays
    private func processOutputData(_ outputData: Data) -> [[Double]] {
        let floats = outputData.toArray(type: Float.self)
        var frameOutputs: [[Double]] = []
        
        let numCompleteFrames = floats.count / 7
        for frame in 0..<numCompleteFrames {
            let i = frame * 7
            let probs = Array(floats[i..<(i + 7)]).map { exp(Double($0)) }
            
            var speakerProbs = Array(repeating: 0.0, count: numSpeakers)
            speakerProbs[0] = probs[1] + probs[4] + probs[5] // spk1
            speakerProbs[1] = probs[2] + probs[4] + probs[6] // spk2
            speakerProbs[2] = probs[3] + probs[5] + probs[6] // spk3
            
            frameOutputs.append(speakerProbs)
        }
        
        return frameOutputs
    }
    
    /// Reorders and blends overlapping frames
    /// - Parameters:
    ///   - overlapChunk: Previous overlap chunk
    ///   - newFrames: New frames to process
    /// - Returns: Reordered and blended frames
    private func reorderAndBlend(overlapChunk: [[Double]], newFrames: [[Double]]) -> [[Double]] {
        var reorderedFrames = reorder(x: overlapChunk, y: newFrames)
        
        // Blend overlapping sections
        for i in 0..<overlapChunk.count {
            for j in 0..<numSpeakers {
                reorderedFrames[i][j] = (reorderedFrames[i][j] + overlapChunk[i][j]) / 2.0
            }
        }
        
        return reorderedFrames
    }
    
    /// Reorders speaker assignments for consistency
    /// - Parameters:
    ///   - x: Previous frame probabilities
    ///   - y: Current frame probabilities
    /// - Returns: Reordered current frame probabilities
    private func reorder(x: [[Double]], y: [[Double]]) -> [[Double]] {
        let perms = generatePermutations(n: numSpeakers)
        let yTransposed = transpose(y)
        
        var minDiff = Double.infinity
        var bestPerm = y
        
        for perm in perms {
            var permuted = Array(repeating: Array(repeating: 0.0, count: numSpeakers), count: y.count)
            for i in 0..<y.count {
                for j in 0..<numSpeakers {
                    permuted[i][j] = yTransposed[perm[j]][i]
                }
            }
            
            var diff = 0.0
            for i in 0..<x.count {
                for j in 0..<numSpeakers {
                    diff += abs(x[i][j] - permuted[i][j])
                }
            }
            
            if diff < minDiff {
                minDiff = diff
                bestPerm = permuted
            }
        }
        
        return bestPerm
    }
    
    /// Generates all possible permutations
    /// - Parameter n: Number of elements
    /// - Returns: Array of permutations
    private func generatePermutations(n: Int) -> [[Int]] {
        if n == 1 {
            return [[0]]
        }
        
        var result: [[Int]] = []
        for i in 0..<n {
            let subPerms = generatePermutations(n: n - 1)
            for var perm in subPerms {
                perm = [i] + perm.map { $0 >= i ? $0 + 1 : $0 }
                result.append(perm)
            }
        }
        return result
    }
    
    /// Transposes a 2D array
    /// - Parameter matrix: Input 2D array
    /// - Returns: Transposed 2D array
    private func transpose(_ matrix: [[Double]]) -> [[Double]] {
        guard !matrix.isEmpty else { return [] }
        let rows = matrix.count
        let cols = matrix[0].count
        var result = Array(repeating: Array(repeating: 0.0, count: rows), count: cols)
        
        for i in 0..<rows {
            for j in 0..<cols {
                result[j][i] = matrix[i][j]
            }
        }
        
        return result
    }
}