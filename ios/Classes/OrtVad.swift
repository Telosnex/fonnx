import Foundation
import onnxruntime_objc
import os.log

/// OrtVad is a class responsible for performing voice activity detection (VAD) using ONNX Runtime.
class OrtVad {
  /// The path to the ONNX model file.
  private let modelPath: String

  /// Lazy instantiation of OrtSessionObjects used to manage the ONNX session.
  private lazy var model: OrtSessionObjects = {
    OrtSessionObjects(modelPath: modelPath, includeOrtExtensions: false)!
  }()

  /// Initializes the OrtVad instance with a provided model path.
  /// - Parameter modelPath: The path to the ONNX model file.
  init(modelPath: String) {
    self.modelPath = modelPath
  }

  /// Performs inference using the ONNX model.
  /// - Parameters:
  ///   - audioBytes: The raw audio data.
  ///   - previousState: The state from previous inference, if any.
  /// - Returns: A dictionary representing the output of the model and the new state.
  func doInference(audioBytes: [UInt8], previousState: [String: Any] = [:]) -> [String: Any]? {
    do {
      let session = model.session
      let audioData = convertAudioBytesToFloats(audioBytes: audioBytes)
      let sampleRate: Int64 = 16000
      let batchSize = 1
      var h = transformToFloatArray3D(previousState["hn"])
      var c = transformToFloatArray3D(previousState["cn"])

      if h == nil || c == nil {
        os_log("Previous LSTM state is null, initializing them to zero arrays.")
        h = Array(
          repeating: Array(repeating: [Float](repeating: 0.0, count: 64), count: batchSize),
          count: 2)
        c = h
      }

      let inputData = try createORTValue(
        from: audioData, elementType: .float,
        shape: [NSNumber(value: 1), NSNumber(value: audioData.count)])
      let sampleRateData = try createORTValue(
        from: [sampleRate], elementType: .int64, shape: [NSNumber(value: 1)])
      let hData = try createORTValue(
        from: h!, elementType: .float,
        shape: [NSNumber(value: 2), NSNumber(value: batchSize), NSNumber(value: 64)])
      let cData = try createORTValue(
        from: c!, elementType: .float,
        shape: [NSNumber(value: 2), NSNumber(value: batchSize), NSNumber(value: 64)])
      let inputs = [
        "input": inputData,
        "sr": sampleRateData,
        "h": hData,
        "c": cData,
      ]
      let outputNames = Set(["output", "hn", "cn"])

      let startTime = Date()
      let outputs = try session.run(withInputs: inputs, outputNames: outputNames, runOptions: nil)
      let endTime = Date()
      os_log("Inference time: %{public}.3f ms", (endTime.timeIntervalSince(startTime) * 1000))

      var processedMap = [String: Any]()

      if let outputTensor = outputs["output"],
        let outputData = try? outputTensor.tensorData() as Data
      {
        let outputArray: [Float] = outputData.toFloatArray()
        processedMap["output"] = outputArray
      }

      if let hnTensor = outputs["hn"], let hnData = try? hnTensor.tensorData() as Data {
        let hnArray: [[[Float]]] = hnData.to3DArray(depth: 2, height: 1, width: 64)!
        processedMap["hn"] = hnArray.map { $0.map { $0 } }
      }

      if let cnTensor = outputs["cn"], let cnData = try? cnTensor.tensorData() as Data {
        let cnArray: [[[Float]]] = cnData.to3DArray(depth: 2, height: 1, width: 64)!
        processedMap["cn"] = cnArray.map { $0.map { $0 } }
      }

      return processedMap
    } catch {
      os_log("Error in doInference: %{public}s", error.localizedDescription)
      return nil
    }
  }
}

extension Int64 {
  /// Converts Int64 to Data.
  var asData: Data {
    var value = self
    return Data(bytes: &value, count: MemoryLayout<Self>.size)
  }
}

extension Array where Element == [[Float]] {
  /// Converts a 3D Float array to Data, assuming the innermost array represents a contiguous block of Floats.
  var asData: Data {
    let flattened = self.flatMap { $0.flatMap { $0 } }
    return Data(buffer: UnsafeBufferPointer(start: flattened, count: flattened.count))
  }
}

/// Converts a byte array representation of 16-bit PCM audio to an array of Float32s.
/// - Parameter audioBytes: The raw audio byte data. Assumes the byte order is little-endian.
/// - Returns: An array of Float32 values representing the audio data.
func convertAudioBytesToFloats(audioBytes: [UInt8]) -> [Float] {
  // Ensure the audio bytes have an even number of elements
  guard audioBytes.count % 2 == 0 else { return [] }

  return stride(from: 0, to: audioBytes.count, by: 2).compactMap { index in
    // Combine two bytes into one 16-bit short value, assuming little-endian byte order
    let value = Int16(audioBytes[index]) | (Int16(audioBytes[index + 1]) << 8)
    // Normalize the 16-bit short value to a floating-point value in [-1.0, 1.0]
    // Int16.max is used for normalization as it represents the maximum positive value a 16-bit signed integer can hold.
    return Float(value) / Float(Int16.max)
  }
}

func transformToFloatArray3D(_ list: Any) -> [[[Float]]]? {
  // Check if the outermost layer is an array and safely cast it.
  guard let outerArray = list as? [[Any]] else { return nil }

  // Transform the outer array into a 3D Float array, if possible.
  let transformed = outerArray.compactMap { midLayer in
    // For each mid-layer, attempt to cast it to an array of Any,
    // then transform each element into a Float array, if possible.
    midLayer.compactMap { innerLayer in
      // Attempt to cast the innermost layer to either directly an array of Float
      // or an array of NSNumber, then convert to Float.
      if let floatArray = innerLayer as? [Float] {
        // Directly return if already Float array.
        return floatArray
      } else if let numberArray = innerLayer as? [NSNumber] {
        // Convert NSNumber array to Float array.
        return numberArray.map { $0.floatValue }
      } else {
        // If the innermost layer isn't correctly structured, return nil for this layer.
        return nil
      }
    }
  }

  // Check the transformed structure to ensure we have a non-empty 3D array.
  return transformed.isEmpty ? nil : transformed
}
extension Double {
  /// Converts the time interval in seconds to a string representing milliseconds.
  var millisecondsString: String {
    String(format: "%.3f", self * 1000)
  }
}
extension Data {
  /// Correctly converts Data to an array of the specified type.
  /// The existing method works well for fixed-width integers.

  /// Converts Data to a Float array - useful for neural network outputs.
  func toFloatArray() -> [Float] {
    return withUnsafeBytes {
      Array($0.bindMemory(to: Float.self))
    }
  }

  /// Assuming specific dimensions for the 3D Float array, for demonstration purposes.
  /// This method will convert Data into a 3D Float array given expected row and column counts
  /// where `depth * height * width == count / MemoryLayout<Float>.size`.
  func to3DArray(depth: Int, height: Int, width: Int) -> [[[Float]]]? {
    let expectedCount = depth * height * width
    let floatCount = count / MemoryLayout<Float>.size

    guard floatCount == expectedCount else { return nil }

    return withUnsafeBytes { ptr -> [[[Float]]]? in
      let floats = ptr.bindMemory(to: Float.self).baseAddress!

      var threeDArray = [[[Float]]](
        repeating: [[Float]](repeating: [Float](repeating: 0, count: width), count: height),
        count: depth)
      for d in 0..<depth {
        for h in 0..<height {
          for w in 0..<width {
            let index = d * height * width + h * width + w
            threeDArray[d][h][w] = floats[index]
          }
        }
      }
      return threeDArray
    }
  }
}
