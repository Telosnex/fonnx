import Flutter
import UIKit
import os

public class FonnxPlugin: NSObject, FlutterPlugin {
  private var cachedMiniLmModelPath: String?
  private var cachedMiniLm: OrtMiniLm?
  private var cachedWhisperModelPath: String?
  private var cachedWhisper: OrtWhisper?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "fonnx", binaryMessenger: registrar.messenger())
    let instance = FonnxPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "miniLm":
      doMiniLm(call, result: result)
    case "whisper":
      doWhisper(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func doMiniLm(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let path = (call.arguments as! [Any])[0] as! String
    let tokens = (call.arguments as! [Any])[1] as! [Int64]

    if cachedMiniLmModelPath != path {
      cachedMiniLm = try? OrtMiniLm(modelPath: path)
      cachedMiniLmModelPath = path
    }

    guard let model = cachedMiniLm else {
      result(FlutterError(code: "MiniLm", message: "Could not instantiate model", details: nil))
      return
    }

    do {
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
    } catch {
      result(FlutterError(code: "MiniLm", message: "Failed to get embedding", details: error))
    }
  }

  public func doWhisper(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let path = (call.arguments as! [Any])[0] as! String
    let audioData = (call.arguments as! [Any])[1] as! FlutterStandardTypedData

    if cachedWhisperModelPath != path {
      cachedWhisper = try? OrtWhisper(modelPath: path)
      cachedMiniLmModelPath = path
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

    do {
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
    } catch {
      result(FlutterError(code: "Whisper", message: "Failed to get transcription", details: error))
    }
  }
}
