import Flutter
import onnxruntime_objc
import os

// This class handles the MinishLab embedding model
class OrtMinishLab {
  var modelPath: String
  lazy var sessionObjects: OrtSessionObjects = { 
    guard let session = OrtSessionObjects(modelPath: modelPath, includeOrtExtensions: true) else {
      fatalError("Failed to create OrtSessionObjects for MinishLab")
    }
    return session
  }()

  init(modelPath: String) {
    self.modelPath = modelPath
    os_log("OrtMinishLab initialized with model path: %@", modelPath)
  }

  func getEmbedding(
    tokens: [Int64], 
    completion: @escaping (_ result: FlutterStandardTypedData?, _ error: Error?) -> Void
  ) {
    do {
      let startDate = Date()
      
      // MinishLab model expects a 1D tensor for input_ids
      let inputShape = [NSNumber(value: tokens.count)]
      
      // MinishLab model expects an "offsets" input with a single value 0
      let offsetsValues = [Int64(0)]
      let offsetsShape = [NSNumber(value: offsetsValues.count)]

      // Convert to data
      let inputData = NSMutableData(
        bytes: tokens, length: tokens.count * MemoryLayout<Int64>.size)
      let offsetsData = NSMutableData(
        bytes: offsetsValues, length: offsetsValues.count * MemoryLayout<Int64>.size)
      
      // Create tensors
      let inputTensor = try ORTValue(tensorData: inputData, elementType: .int64, shape: inputShape)
      let offsetsTensor = try ORTValue(tensorData: offsetsData, elementType: .int64, shape: offsetsShape)

      os_log("MinishLab: Created input tensors")
      
      // Get the session and run inference
      let session = sessionObjects.session
      let outputName = "embeddings"
      
      // Log the input names to help debug
      os_log("MinishLab: Running inference with inputs: input_ids, offsets")
      
      let outputs = try session.run(
        withInputs: [
          "input_ids": inputTensor,
          "offsets": offsetsTensor
        ],
        outputNames: [outputName],
        runOptions: nil)

      guard let rawOutputValue = outputs[outputName] else {
        os_log("MinishLab: Failed to get output")
        completion(nil, FonnxError("Failed to get output"))
        return
      }
      
      let rawOutputData = try rawOutputValue.tensorData() as Data
      let outputArr = FlutterStandardTypedData(float32: rawOutputData)
      
      let embeddingDone = Date()
      let interval = embeddingDone.timeIntervalSince(startDate) * 1000
      os_log("MinishLab: took %f ms for embedding", interval)
      
      completion(outputArr, nil)
    } catch {
      os_log("MinishLab error: %@", error.localizedDescription)
      completion(nil, error)
    }
  }
}