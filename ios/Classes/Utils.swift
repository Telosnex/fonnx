struct FonnxError: Error {
  let message: String

  init(_ message: String) {
    self.message = message
  }
}

extension Array {
  // Create a new array from the bytes of the given unsafe data.
  init?(unsafeData: Data) {
    guard unsafeData.count % MemoryLayout<Element>.stride == 0 else { return nil }
    #if swift(>=5.0)
      self = unsafeData.withUnsafeBytes { .init($0.bindMemory(to: Element.self)) }
    #else
      self = unsafeData.withUnsafeBytes {
        .init(
          UnsafeBufferPointer<Element>(
            start: $0,
            count: unsafeData.count / MemoryLayout<Element>.stride
          ))
      }
    #endif  // swift(>=5.0)
  }
}
