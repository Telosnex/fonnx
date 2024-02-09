import onnxruntime_objc
import os

class OrtSessionObjects: NSObject {
  public private(set) var session: ORTSession
  private var env: ORTEnv

  // MARK: - Initialization of ModelHandler
    init?(modelPath: String, includeOrtExtensions: Bool) {
    do {
      // Start the ORT inference environment and specify the options for session
      env = try ORTEnv(loggingLevel: ORTLoggingLevel.error)
      let options = try ORTSessionOptions()
        if includeOrtExtensions {
            let ortCustomOpsFnPtr = OrtExt.getRegisterCustomOpsFunctionPointer()
            try options.registerCustomOps(functionPointer: ortCustomOpsFnPtr)
        }
      // Using CoreMLExecutionProvider did not improve performance of MiniLmL6V2 in Q3 2023.
      // It did not improve performance of Whisper Base on 8 Feb 2024.
      // Disabling it for consistency, but, leaving it in code because it may be useful in the future.
      // try options.appendCoreMLExecutionProvider(with: ORTCoreMLExecutionProviderOptions())
      try options.setLogSeverityLevel(ORTLoggingLevel.error)
      // Create the ORTSession
      session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: options)
      os_log("Created ORTSession.")
    } catch {
      os_log("Failed to create ORTSession.")
      return nil
    }

    super.init()
  }
}