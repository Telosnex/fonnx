import Flutter
import onnxruntime_objc
import os

class MiniLmL6V2 {
  var modelPath: String
  lazy var sessionObjects: OrtSessionObjects = { OrtSessionObjects(modelPath: modelPath)! }()

  init(modelPath: String) {
    self.modelPath = modelPath
  }

  func getEmbedding(
    tokens: [Int64], completion: @escaping (_ result: FlutterStandardTypedData?, _ error: Error?) -> Void
  ) {
    do {
      let interval: TimeInterval
      let shape = [
        NSNumber(value: 1), NSNumber(value: tokens.count),
      ]
      var attentionMaskBytes = [Int64]()
      var tokenTypeIdsBytes = [Int64]()
      attentionMaskBytes += Array(repeating: 1, count: tokens.count)
      tokenTypeIdsBytes += Array(repeating: 0, count: tokens.count)

      // Convert to data
      let inputBytesData = NSMutableData(
        bytes: tokens, length: tokens.count * MemoryLayout<Int64>.size)
      let attentionMaskData = NSMutableData(
        bytes: attentionMaskBytes, length: attentionMaskBytes.count * MemoryLayout<Int64>.size)
      let tokenTypeIdsData = NSMutableData(
        bytes: tokenTypeIdsBytes, length: tokenTypeIdsBytes.count * MemoryLayout<Int64>.size)
      // Create tensors
      let inputTensor = try ORTValue(tensorData: inputBytesData, elementType: .int64, shape: shape)
      let attentionTensor = try ORTValue(
        tensorData: attentionMaskData, elementType: .int64, shape: shape)
      let tokenTensor = try ORTValue(
        tensorData: tokenTypeIdsData, elementType: .int64, shape: shape)

      let startDate = Date()
      let session = sessionObjects.session
      let outputName = "embeddings"
      let outputs = try session.run(
        withInputs: [
          "input_ids": inputTensor, "token_type_ids": tokenTensor,
          "attention_mask": attentionTensor,
        ],
        outputNames: [outputName],
        runOptions: nil)

      guard let rawOutputValue = outputs[outputName] else {
        completion(nil, FonnxError("Failed to get output"))
        return
      }
      let rawOutputData = try rawOutputValue.tensorData() as Data
      // Model output is 32-bit floats (known from model inspection, see Netron)
      // See here for info on Swift type choice:
      // https://docs.flutter.dev/platform-integration/platform-channels?tab=type-mappings-swift-tab
      let outputArr = FlutterStandardTypedData(float32: rawOutputData);
      let embeddingDone = Date()
      interval = embeddingDone.timeIntervalSince(startDate) * 1000
      os_log("took \(interval) ms for embedding")
      completion(outputArr, nil)
    } catch {
      completion(nil, error)
    }
  }
}
