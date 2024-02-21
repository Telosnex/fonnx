import Flutter
import UIKit
import os

public class FonnxPlugin: NSObject, FlutterPlugin {
  private var cachedMagikaModelPath: String?
  private var cachedMagika: OrtMagika?
  private var cachedMiniLmModelPath: String?
  private var cachedMiniLm: OrtMiniLm?
  private var cachedWhisperModelPath: String?
  private var cachedWhisper: OrtWhisper?
  private var cachedSileroVadModelPath: String?
  private var cachedSileroVad: OrtVad?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "fonnx", binaryMessenger: registrar.messenger())
    let instance = FonnxPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "magika":
      doMagika(call, result: result)
    case "miniLm":
      doMiniLm(call, result: result)
    case "whisper":
      doWhisper(call, result: result)
    case "sileroVad":
      doSileroVad(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func doMagika(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let path = (call.arguments as! [Any])[0] as! String
    let fileFloats = (call.arguments as! [Any])[1] as! [Float]

    if cachedMagikaModelPath != path {
      cachedMagika = OrtMagika(modelPath: path)
      cachedMagikaModelPath = path
    }

    guard let model = cachedMagika else {
      result(FlutterError(code: "Magika", message: "Could not instantiate model", details: nil))
      return
    }

    let answer = model.doInference(fileBytes: fileFloats)
    result(answer)
  }

  public func doMiniLm(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let path = (call.arguments as! [Any])[0] as! String
    let tokens = (call.arguments as! [Any])[1] as! [Int64]

    if cachedMiniLmModelPath != path {
      cachedMiniLm = OrtMiniLm(modelPath: path)
      cachedMiniLmModelPath = path
    }

    guard let model = cachedMiniLm else {
      result(FlutterError(code: "MiniLm", message: "Could not instantiate model", details: nil))
      return
    }

      model.getEmbedding(
        tokens: tokens,
        completion: { (answer, error) in
          if let error = error {
            result(
              FlutterError(code: "MiniLm", message: "Failed to get embedding", details: error)
            )
          } else {
            result(answer)
          }
        })
  }

  public func doSileroVad(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let path = (call.arguments as! [Any])[0] as! String
    let audioData = (call.arguments as! [Any])[1] as! FlutterStandardTypedData
    let previousState = (call.arguments as! [Any])[2] as! [String: Any]

    if cachedSileroVadModelPath != path {
      cachedSileroVad = OrtVad(modelPath: path)
      cachedSileroVadModelPath = path
    }

    guard let model = cachedSileroVad else {
      result(FlutterError(code: "SileroVad", message: "Could not instantiate model", details: nil))
      return
    }

    // Process the FlutterStandardTypedData to create an NSArray of Ints
    // Simplified and corrected code block for handling audio bytes
    var audioBytes = [UInt8]()
    switch audioData.type {
    case .uInt8:
      audioBytes = [UInt8](audioData.data)
    case .int32:
      audioData.data.withUnsafeBytes { pointer in
        audioBytes = Array(
          UnsafeBufferPointer(
            start: pointer.bindMemory(to: Int32.self).baseAddress,
            count: audioData.data.count / MemoryLayout<Int32>.size)
        ).map(UInt8.init)
      }
    case .int64:
      audioData.data.withUnsafeBytes { pointer in
        audioBytes = Array(
          UnsafeBufferPointer(
            start: pointer.bindMemory(to: Int64.self).baseAddress,
            count: audioData.data.count / MemoryLayout<Int64>.size)
        ).map(UInt8.init)
      }
    case .float32, .float64:
      result(
        FlutterError(
          code: "SileroVad", message: "Unsupported data type for audio bytes", details: nil))
      return
    @unknown default:
      result(FlutterError(code: "SileroVad", message: "Unknown data type", details: nil))
      return
    }

    let answer = model.doInference(audioBytes: audioBytes, previousState: previousState)
    result(answer)
  }

  public func doWhisper(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let path = (call.arguments as! [Any])[0] as! String
    let audioData = (call.arguments as! [Any])[1] as! FlutterStandardTypedData

    if cachedWhisperModelPath != path {
      cachedWhisper = OrtWhisper(modelPath: path)
      cachedWhisperModelPath = path
    }

    guard let model = cachedWhisper else {
      result(FlutterError(code: "Whisper", message: "Could not instantiate model", details: nil))
      return
    }

    // Process the FlutterStandardTypedData to create an NSArray of Ints
    // Simplified and corrected code block for handling audio bytes
    var audioBytes = [UInt8]()
    switch audioData.type {
    case .uInt8:
      audioBytes = [UInt8](audioData.data)
    case .int32:
      audioData.data.withUnsafeBytes { pointer in
        audioBytes = Array(
          UnsafeBufferPointer(
            start: pointer.bindMemory(to: Int32.self).baseAddress,
            count: audioData.data.count / MemoryLayout<Int32>.size)
        ).map(UInt8.init)
      }
    case .int64:
      audioData.data.withUnsafeBytes { pointer in
        audioBytes = Array(
          UnsafeBufferPointer(
            start: pointer.bindMemory(to: Int64.self).baseAddress,
            count: audioData.data.count / MemoryLayout<Int64>.size)
        ).map(UInt8.init)
      }
    case .float32, .float64:
      result(
        FlutterError(
          code: "Whisper", message: "Unsupported data type for audio bytes", details: nil))
      return
    @unknown default:
      result(FlutterError(code: "Whisper", message: "Unknown data type", details: nil))
      return
    }

      model.getTranscription(
        audioBytes: audioBytes,
        completion: { (answer, error) in
          if let error = error {
            result(
              FlutterError(code: "Whisper", message: "Failed to get transcription", details: error)
            )
          } else {
            result(answer)
          }
        })
  }
}
