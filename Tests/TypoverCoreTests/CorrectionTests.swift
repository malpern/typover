import Foundation
import Testing

@testable import TypoverCore

struct CorrectionTests {
  @Test("A correction reports when it changes text")
  func detectsChangedText() {
    let correction = Correction(
      original: "teh",
      replacement: "the",
      confidence: 0.99
    )

    #expect(correction.changesText)
  }

  @Test("Confidence is constrained to a probability")
  func clampsConfidence() {
    let overconfident = Correction(
      original: "recieve",
      replacement: "receive",
      confidence: 1.4
    )
    let underconfident = Correction(
      original: "form",
      replacement: "from",
      confidence: -0.2
    )

    #expect(overconfident.confidence == 1)
    #expect(underconfident.confidence == 0)
  }
}
