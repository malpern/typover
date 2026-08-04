import Foundation
import Testing

@testable import TypoverCore

struct CorrectionTests {
  @Test("A correction reports when it changes text")
  func detectsChangedText() {
    let correction = Correction(
      original: "teh",
      replacement: "the"
    )

    #expect(correction.changesText)
  }

  @Test("The demo engine only corrects its narrow rule")
  @MainActor
  func demoEngineUsesNarrowRule() {
    let engine = DemoCorrectionEngine()

    #expect(engine.proposal(for: "teh")?.correction.replacement == "the")
    #expect(engine.proposal(for: "recieve") == nil)
    #expect(engine.proposal(for: "Teh") == nil)
  }

  @Test("The ledger preserves the original correction as its state changes")
  func ledgerTracksDisposition() {
    let correction = Correction(
      original: "teh",
      replacement: "the"
    )
    var ledger = CorrectionLedger()

    ledger.record(correction)
    #expect(ledger.record(for: correction.id)?.disposition == .applied)

    let didTransition = ledger.transition(correction.id, to: .restored)
    #expect(didTransition)
    #expect(ledger.record(for: correction.id)?.correction == correction)
    #expect(ledger.record(for: correction.id)?.disposition == .restored)
  }

  @Test("A caret after an edited word moves by the replacement delta")
  func movesCaretAfterReplacement() {
    let caret = TextSelectionAdjustment.afterReplacing(
      NSRange(location: 8, length: 3),
      withLength: 7,
      selection: NSRange(location: 15, length: 0)
    )

    #expect(caret == NSRange(location: 19, length: 0))
  }

  @Test("A selection before an edited word stays in place")
  func keepsEarlierSelection() {
    let selection = TextSelectionAdjustment.afterReplacing(
      NSRange(location: 8, length: 3),
      withLength: 7,
      selection: NSRange(location: 1, length: 4)
    )

    #expect(selection == NSRange(location: 1, length: 4))
  }

  @Test("A selection intersecting an edited word collapses after it")
  func collapsesIntersectingSelection() {
    let selection = TextSelectionAdjustment.afterReplacing(
      NSRange(location: 8, length: 3),
      withLength: 7,
      selection: NSRange(location: 9, length: 1)
    )

    #expect(selection == NSRange(location: 15, length: 0))
  }
}
