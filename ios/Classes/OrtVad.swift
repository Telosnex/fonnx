import Flutter
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

      var h: [Float]?
      var c: [Float]?

      if let hData = previousState["hn"] as? FlutterStandardTypedData {
        let myData = Data(hData.data)
        h = myData.toArray(type: Float.self)
      } else {
        os_log(
          "Previous LSTM state 'hn' is null or not FlutterStandardTypedData, initializing it to zero arrays."
        )
        h = Array(repeating: 0, count: 2 * batchSize * 64)
      }

      if let cData = previousState["cn"] as? FlutterStandardTypedData {
        let myData = Data(cData.data)
        c = myData.toArray(type: Float.self)
      } else {
        os_log(
          "Previous LSTM state 'cn' is null or not FlutterStandardTypedData, initializing it to zero arrays."
        )
        c = Array(repeating: 0, count: 2 * batchSize * 64)
      }

      let inputTensor = try createORTValue(
        from: audioData, elementType: .float,
        shape: [NSNumber(value: 1), NSNumber(value: audioData.count)])
      let sampleRateTensor = try createORTValue(
        from: [sampleRate], elementType: .int64, shape: [NSNumber(value: 1)])
      let hData = NSMutableData(bytes: h, length: h!.count * MemoryLayout<Float>.size)
      let cData = NSMutableData(bytes: c, length: c!.count * MemoryLayout<Float>.size)
      let hTensor = try ORTValue(
        tensorData: hData, elementType: .float,
        shape: [NSNumber(value: 2), NSNumber(value: 1), NSNumber(value: 64)])
      let cTensor = try ORTValue(
        tensorData: cData, elementType: .float,
        shape: [NSNumber(value: 2), NSNumber(value: 1), NSNumber(value: 64)])
      let inputs = [
        "input": inputTensor,
        "sr": sampleRateTensor,
        "h": hTensor,
        "c": cTensor,
      ]
      let outputNames = Set(["output", "hn", "cn"])

      let startTime = Date()
      let outputs = try session.run(withInputs: inputs, outputNames: outputNames, runOptions: nil)
      let endTime = Date()

      var processedMap = [String: Any]()

      if let outputTensor = outputs["output"],
        let outputData = try? outputTensor.tensorData() as Data
      {
        let outputArray = FlutterStandardTypedData(float32: outputData)
        processedMap["output"] = outputArray
      }

      if let hnTensor = outputs["hn"], let hnData = try? hnTensor.tensorData() as Data {
        let hnArray = FlutterStandardTypedData(float32: hnData)
        processedMap["hn"] = hnArray
      }

      if let cnTensor = outputs["cn"], let cnData = try? cnTensor.tensorData() as Data {
        let cnArray = FlutterStandardTypedData(float32: cnData)
        processedMap["cn"] = cnArray
      }

      return processedMap
    } catch {
      os_log("Error in doInference: %{public}s", error.localizedDescription)
      for symbol in Thread.callStackSymbols {
        os_log("Stack trace: %{public}s", symbol)
      }
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
  var audioData = [Float](repeating: 0.0, count: audioBytes.count / 2)
  for i in 0..<audioData.count {
    var valInt = Int(audioBytes[i * 2]) | Int(audioBytes[i * 2 + 1]) << 8
    if valInt > 0x7FFF {
      valInt -= 0x10000
    }
    audioData[i] = Float(valInt) / 32767.0
  }
  return audioData
}

extension Data {
  /// Converts Data to an array of a given type. 
  /// - Parameter type: The type of the array elements.
  /// - Returns: An array of the given type.
  /// via https://stackoverflow.com/questions/24196820/nsdata-from-byte-array-in-swift
  func toArray<T>(type: T.Type) -> [T] {
    let value = self.withUnsafeBytes {
      $0.baseAddress?.assumingMemoryBound(to: T.self)
    }
    return [T](UnsafeBufferPointer(start: value, count: self.count / MemoryLayout<T>.stride))
  }
}
