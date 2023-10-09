import Flutter
import UIKit
import os

public class FonnxPlugin: NSObject, FlutterPlugin {
  private var cachedMiniLmL6V2Path: String?
  private var cachedMiniLmL6V2: MiniLmL6V2?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "fonnx", binaryMessenger: registrar.messenger())
    let instance = FonnxPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "miniLmL6V2":
      doMiniLmL6V2(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func doMiniLmL6V2(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let path = (call.arguments as! [Any])[0] as! String
    let tokens = (call.arguments as! [Any])[1] as! [[Int64]]

    if cachedMiniLmL6V2Path != path {
      cachedMiniLmL6V2 = try? MiniLmL6V2(modelPath: path)
      cachedMiniLmL6V2Path = path
    }

    guard let model = cachedMiniLmL6V2 else {
      result(FlutterError(code: "MiniLmL6V2", message: "Could not instantiate model", details: nil))
      return
    }
    
    do {
     model.getEmbedding(
        tokens: tokens[0],
        completion: { (answer, error) in
          if let error = error {
            result(
              FlutterError(code: "MiniLmL6V2", message: "Failed to get embedding", details: error)
            )
          } else {
            result(answer)
          }
        })
    } catch {
      result(FlutterError(code: "MiniLmL6V2", message: "Failed to get embedding", details: error))
    }
  }
}
