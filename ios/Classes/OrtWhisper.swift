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
      let logitsProcessorData = try createORTValue(from: [0], elementType: .int32, shape: [1])
      // The more exact construction here allows avoiding an error of "Repetition penalty must be > 0.0"
      var repetitionPenaltyBytes = [Float]()
      repetitionPenaltyBytes += Array(repeating: 1, count: 1)
      let repetitionPenaltyData = NSMutableData(
        bytes: repetitionPenaltyBytes, length: MemoryLayout<Float32>.size)
      let repetitionPenaltyTensor = try ORTValue(
        tensorData: repetitionPenaltyData, elementType: .float, shape: [1])

      let session = sessionObjects.session
      let outputName = "str"

      // The more exact construction here, and in the caller, avoids an error of "Invalid audio format"
      // It seems otherwise the bytes are not interpreted as Uint8.
      let audioData = convertAudioBytesToFloats(audioBytes: audioBytes)
      let audioTensor = try createORTValue(
        from: audioData, elementType: .float,
        shape: [NSNumber(value: 1), NSNumber(value: audioData.count)])
      let outputs = try session.run(
        withInputs: [
          "audio_pcm": audioTensor,
          "max_length": maxLengthData,
          "min_length": minLengthData,
          "num_beams": numBeamsData,
          "num_return_sequences": numReturnSequencesData,
          "length_penalty": lengthPenaltyData,
          "repetition_penalty": repetitionPenaltyTensor,
          "logits_processor": logitsProcessorData,
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
