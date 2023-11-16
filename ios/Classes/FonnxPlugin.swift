import Flutter
import UIKit
import os

public class FonnxPlugin: NSObject, FlutterPlugin {
  private var cachedMiniLmModelPath: String?
  private var cachedMiniLm: OrtMiniLm?

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
}
