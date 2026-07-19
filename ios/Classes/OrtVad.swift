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

  func doInference(audioBytes: [UInt8], previousState: [String: Any] = [:]) -> [String: Any]? {
    do {
      guard !audioBytes.isEmpty && audioBytes.count.isMultiple(of: 2) else {
        throw VadError.invalidPcmLength
      }

      let audio = convertAudioBytesToFloats(audioBytes: audioBytes)
      var state = restore(previousState["state"], count: 256)
      var context = restore(previousState["context"], count: 64)
      var probabilities = [Float]()

      for offset in stride(from: 0, to: audio.count, by: 512) {
        let count = min(512, audio.count - offset)
        var chunk = [Float](repeating: 0, count: 512)
        chunk.replaceSubrange(0..<count, with: audio[offset..<(offset + count)])
        let input = context + chunk

        let inputTensor = try createORTValue(
          from: input,
          elementType: .float,
          shape: [1, NSNumber(value: input.count)]
        )
        let stateData = NSMutableData(
          bytes: state,
          length: state.count * MemoryLayout<Float>.size
        )
        let stateTensor = try ORTValue(
          tensorData: stateData,
          elementType: .float,
          shape: [2, 1, 128]
        )
        let sampleRateTensor = try createORTValue(
          from: [Int64(16000)],
          elementType: .int64,
          shape: [1]
        )

        let outputs = try model.session.run(
          withInputs: [
            "input": inputTensor,
            "state": stateTensor,
            "sr": sampleRateTensor,
          ],
          outputNames: Set(["output", "stateN"]),
          runOptions: nil
        )
        guard
          let outputData = try outputs["output"]?.tensorData() as Data?,
          let stateData = try outputs["stateN"]?.tensorData() as Data?
        else {
          throw VadError.missingOutput
        }
        probabilities.append(outputData.toArray(type: Float.self)[0])
        state = stateData.toArray(type: Float.self)
        guard state.count == 256 else { throw VadError.invalidState }
        context = Array(chunk.suffix(64))
      }

      return [
        "output": float32Data(probabilities),
        "state": float32Data(state),
        "context": float32Data(context),
      ]
    } catch {
      os_log("Silero VAD v6 inference failed: %{public}s", error.localizedDescription)
      return nil
    }
  }

  private func restore(_ value: Any?, count: Int) -> [Float] {
    if let typed = value as? FlutterStandardTypedData {
      let floats = Data(typed.data).toArray(type: Float.self)
      if floats.count == count { return floats }
    }
    if let numbers = value as? [NSNumber], numbers.count == count {
      return numbers.map { $0.floatValue }
    }
    return [Float](repeating: 0, count: count)
  }

  private func float32Data(_ values: [Float]) -> FlutterStandardTypedData {
    let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
    return FlutterStandardTypedData(float32: data)
  }

  private enum VadError: Error {
    case invalidPcmLength
    case missingOutput
    case invalidState
  }
}

extension Data {
  func toArray<T>(type: T.Type) -> [T] {
    return withUnsafeBytes { bytes in
      Array(bytes.bindMemory(to: T.self))
    }
  }
}
