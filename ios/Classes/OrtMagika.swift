import Flutter
import Foundation
import onnxruntime_objc
import os.log

/// OrtVad is a class responsible for performing voice activity detection (VAD) using ONNX Runtime.
class OrtMagika {
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
  ///   - fileBytes: The input data as an array of floats. 1536 ranging from 0 to 255 (bytes)
  ///     and 256 (representing padding).
  /// - Returns: A list of Float32 values representing the probability of each class.
  func doInference(fileBytes: [Float]) -> FlutterStandardTypedData? {
    do {
      let session = model.session
      let bytesTensor = try createORTValue(
        from: fileBytes, elementType: .float,
        shape: [NSNumber(value: 1), NSNumber(value: fileBytes.count)])
      let inputs = [
        "bytes": bytesTensor
      ]
      let outputName = "target_label"
      let outputNames = Set([outputName])

      let outputs = try session.run(withInputs: inputs, outputNames: outputNames, runOptions: nil)
      guard let rawOutputValue = outputs[outputName] else {
        os_log("Output value not found")
        return nil
      }
      let rawOutputData = try rawOutputValue.tensorData() as Data
      // Model output is 32-bit floats (known from model inspection, see Netron)
      // See here for info on Swift type choice:
      // https://docs.flutter.dev/platform-integration/platform-channels?tab=type-mappings-swift-tab
      os_log("Output data: %{public}s", rawOutputData.description)
      let outputFloats = FlutterStandardTypedData(float32: rawOutputData)
      return outputFloats
    } catch {
      os_log("Error in doInference: %{public}s", error.localizedDescription)
      for symbol in Thread.callStackSymbols {
        os_log("Stack trace: %{public}s", symbol)
      }
      return nil
    }
  }
}
