import Flutter
import onnxruntime_objc
import os

class OrtWhisper {
  var modelPath: String
  lazy var sessionObjects: OrtSessionObjects = {
    OrtSessionObjects(modelPath: modelPath, includeOrtExtensions: true)!
  }()

  init(modelPath: String) {
    self.modelPath = modelPath
  }

  func getTranscription(
    audioBytes: [UInt8],
    completion: @escaping (_ result: String?, _ error: String?) -> Void
  ) {

    do {
      let maxLengthData = try createORTValue(from: [200], elementType: .int32, shape: [1])
      let minLengthData = try createORTValue(from: [0], elementType: .int32, shape: [1])
      let numBeamsData = try createORTValue(from: [2], elementType: .int32, shape: [1])
      let numReturnSequencesData = try createORTValue(from: [1], elementType: .int32, shape: [1])
      let lengthPenaltyData = try createORTValue(from: [1.0], elementType: .float, shape: [1])

      // The more exact construction here allows avoiding an error of "Repetition penalty must be > 0.0"
      var repetitionPenaltyBytes = [Float]()
      repetitionPenaltyBytes += Array(repeating: 1, count: 1)
      let repetitionPenaltyData = NSMutableData(
        bytes: repetitionPenaltyBytes, length: MemoryLayout<Float32>.size)
      let repetitionPenaltyTensor = try ORTValue(
        tensorData: repetitionPenaltyData, elementType: .float, shape: [1])

      let session = sessionObjects.session
      let outputName = "str"

      let startDate = Date()
      // The more exact construction here, and in the caller, avoids an error of "Invalid audio format"
      // It seems otherwise the bytes are not interpreted as Uint8.
      let audioStreamData = Data(bytes: audioBytes, count: audioBytes.count)
      let audioStreamTensor = try ORTValue(
        tensorData: NSMutableData(data: audioStreamData), elementType: .uInt8,
        shape: [1, NSNumber(value: audioBytes.count)])
      let outputs = try session.run(
        withInputs: [
          "audio_stream": audioStreamTensor,
          "max_length": maxLengthData,
          "min_length": minLengthData,
          "num_beams": numBeamsData,
          "num_return_sequences": numReturnSequencesData,
          "length_penalty": lengthPenaltyData,
          "repetition_penalty": repetitionPenaltyTensor,
        ],
        outputNames: [outputName],
        runOptions: nil)

      guard let rawOutputValue = outputs[outputName] else {
        os_log("Failed to get output")
        completion(
          nil,
          "Failed to get output")
        return
      }
      // Assuming model outputs a string tensor
      let outputString = try rawOutputValue.tensorStringData()
      let interval = Date().timeIntervalSince(startDate) * 1000
      os_log("Model inference took \(interval) ms")
      completion(outputString.first, nil)
    } catch {

      completion(nil, error.localizedDescription)
    }

  }
}

extension Data {
  init<T>(fromArray array: [T]) {
    self = array.withUnsafeBytes {
      Data(
        buffer: UnsafeBufferPointer(
          start: $0.baseAddress?.assumingMemoryBound(to: T.self), count: array.count))
    }
  }
}

func createORTValue<T>(from array: [T], elementType: ORTTensorElementDataType, shape: [NSNumber])
  throws -> ORTValue
{
  let data = Data(fromArray: array)
  let mutableData = NSMutableData(data: data)  // Safely create NSMutableData from Data
  return try ORTValue(tensorData: mutableData, elementType: elementType, shape: shape)
}
