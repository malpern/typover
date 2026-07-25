public protocol CorrectionEngine: Sendable {
  func correction(for word: String) -> Correction?
}

public struct DemoCorrectionEngine: CorrectionEngine {
  public init() {}

  public func correction(for word: String) -> Correction? {
    guard word == "teh" else {
      return nil
    }

    return Correction(
      original: word,
      replacement: "the",
      confidence: 0.99
    )
  }
}
