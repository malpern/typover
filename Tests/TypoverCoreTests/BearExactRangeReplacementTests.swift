import AppKit
import ApplicationServices
import Foundation
import Testing
import TypoverBearAdapter
import TypoverCore

@testable import TypoverAccessibility

@Suite("Bear exact-range replacement")
struct BearExactRangeReplacementTests {
  @Test("A verified current range can be re-anchored after a sibling edit")
  func reanchorsVerifiedCurrentRange() throws {
    let editor = FakeBearEditableTextClient(
      text: "alpha teh the omega",
      selection: AccessibilityTextRange(location: 17, length: 0)
    )
    let outcome = BearCorrectionReanchorTransaction().reanchor(
      BearCorrectionReanchorRequest(
        targetRange: AccessibilityTextRange(location: 10, length: 3),
        expectedText: "the",
        leadingContextLimit: 6,
        trailingContextLimit: 6
      ),
      in: editor
    )

    #expect(outcome.status == .reanchored)
    let anchor = try #require(outcome.correctionAnchor)
    #expect(anchor.correctionRange == AccessibilityTextRange(location: 10, length: 3))
    #expect(anchor.documentLength == editor.text.length)
    #expect(anchor.leadingContextLength == 6)
    #expect(anchor.trailingContextLength == 6)
  }

  @Test("Re-anchoring rejects superseded and out-of-bounds ranges")
  func reanchorRejectsUnsafeRanges() {
    let editor = FakeBearEditableTextClient(
      text: "alpha the omega",
      selection: AccessibilityTextRange(location: 15, length: 0)
    )
    let superseded = BearCorrectionReanchorTransaction().reanchor(
      BearCorrectionReanchorRequest(
        targetRange: AccessibilityTextRange(location: 6, length: 3),
        expectedText: "ten",
        leadingContextLimit: 6,
        trailingContextLimit: 6
      ),
      in: editor
    )
    let outOfBounds = BearCorrectionReanchorTransaction().reanchor(
      BearCorrectionReanchorRequest(
        targetRange: AccessibilityTextRange(location: 99, length: 3),
        expectedText: "the",
        leadingContextLimit: 6,
        trailingContextLimit: 6
      ),
      in: editor
    )

    #expect(superseded.status == .superseded)
    #expect(superseded.correctionAnchor == nil)
    #expect(outOfBounds.status == .targetOutOfBounds)
    #expect(outOfBounds.correctionAnchor == nil)
  }

  @Test("Only the requested range changes and the caret is restored")
  func appliesExactRange() {
    let editor = FakeBearEditableTextClient(
      text: "alpha teh omega",
      selection: AccessibilityTextRange(location: 10, length: 0)
    )

    let outcome = BearExactRangeTransaction().applyOutcome(
      request(
        location: 6,
        original: "teh",
        replacement: "the"
      ),
      to: editor
    )
    let report = outcome.report

    #expect(report.status == .applied)
    #expect(report.isVerifiedApplication)
    #expect(editor.text as String == "alpha the omega")
    #expect(
      editor.selection
        == AccessibilityTextRange(location: 10, length: 0)
    )
    #expect(editor.replacementWriteCount == 1)
    #expect(outcome.correctionAnchor != nil)
  }

  @Test("A longer replacement shifts the caret by only its length delta")
  func adjustsCaretForLengthDelta() {
    let editor = FakeBearEditableTextClient(
      text: "alpha adress omega",
      selection: AccessibilityTextRange(location: 13, length: 0)
    )

    let report = BearExactRangeTransaction().apply(
      request(
        location: 6,
        original: "adress",
        replacement: "address"
      ),
      to: editor
    )

    #expect(report.status == .applied)
    #expect(editor.text as String == "alpha address omega")
    #expect(
      report.selectionAfter
        == AccessibilityTextRange(location: 14, length: 0)
    )
  }

  @Test("A stale target makes no edit")
  func rejectsStaleTarget() {
    let editor = FakeBearEditableTextClient(
      text: "alpha ten omega",
      selection: AccessibilityTextRange(location: 10, length: 0)
    )

    let report = BearExactRangeTransaction().apply(
      request(
        location: 6,
        original: "teh",
        replacement: "the"
      ),
      to: editor
    )

    #expect(report.status == .preconditionFailed)
    #expect(!report.writeOccurred)
    #expect(editor.text as String == "alpha ten omega")
    #expect(editor.replacementWriteCount == 0)
  }

  @Test("Repeating an applied transaction is idempotent")
  func alreadyAppliedDoesNotWrite() {
    let editor = FakeBearEditableTextClient(
      text: "alpha the omega",
      selection: AccessibilityTextRange(location: 10, length: 0)
    )

    let report = BearExactRangeTransaction().apply(
      request(
        location: 6,
        original: "teh",
        replacement: "the"
      ),
      to: editor
    )

    #expect(report.status == .alreadyApplied)
    #expect(!report.writeOccurred)
    #expect(editor.replacementWriteCount == 0)
  }

  @Test("A shorter replacement is not mistaken for already applied")
  func shorterReplacementStillApplies() {
    let editor = FakeBearEditableTextClient(
      text: "alpha cats omega",
      selection: AccessibilityTextRange(location: 11, length: 0)
    )

    let report = BearExactRangeTransaction().apply(
      request(
        location: 6,
        original: "cats",
        replacement: "cat"
      ),
      to: editor
    )

    #expect(report.status == .applied)
    #expect(editor.text as String == "alpha cat omega")
    #expect(
      report.selectionAfter
        == AccessibilityTextRange(location: 10, length: 0)
    )
  }

  @Test("Unexpected surrounding changes fail post-write verification")
  func detectsUnexpectedSurroundingChange() {
    let editor = FakeBearEditableTextClient(
      text: "alpha teh omega",
      selection: AccessibilityTextRange(location: 10, length: 0),
      appendedTextAfterReplacement: "!"
    )

    let report = BearExactRangeTransaction().apply(
      request(
        location: 6,
        original: "teh",
        replacement: "the"
      ),
      to: editor
    )

    #expect(report.status == .verificationFailed)
    #expect(report.writeOccurred)
    #expect(!report.surroundingContextVerified)
  }

  @Test("A selection-write failure prevents replacement")
  func selectionFailureDoesNotWrite() {
    let editor = FakeBearEditableTextClient(
      text: "alpha teh omega",
      selection: AccessibilityTextRange(location: 10, length: 0),
      selectionErrors: [.cannotComplete]
    )

    let report = BearExactRangeTransaction().apply(
      request(
        location: 6,
        original: "teh",
        replacement: "the"
      ),
      to: editor
    )

    #expect(report.status == .selectionWriteFailed)
    #expect(!report.writeOccurred)
    #expect(editor.text as String == "alpha teh omega")
    #expect(editor.replacementWriteCount == 0)
  }

  @Test("A replacement-write failure restores the original caret")
  func replacementFailureRestoresCaret() {
    let originalSelection = AccessibilityTextRange(location: 10, length: 0)
    let editor = FakeBearEditableTextClient(
      text: "alpha teh omega",
      selection: originalSelection,
      replacementError: .cannotComplete
    )

    let report = BearExactRangeTransaction().apply(
      request(
        location: 6,
        original: "teh",
        replacement: "the"
      ),
      to: editor
    )

    #expect(report.status == .replacementWriteFailed)
    #expect(!report.writeOccurred)
    #expect(editor.text as String == "alpha teh omega")
    #expect(editor.selection == originalSelection)
  }

  @Test("A caret-restore failure is reported after the write")
  func caretRestoreFailureIsNotRecordedAsSuccess() {
    let editor = FakeBearEditableTextClient(
      text: "alpha teh omega",
      selection: AccessibilityTextRange(location: 10, length: 0),
      selectionErrors: [.success, .cannotComplete]
    )

    let report = BearExactRangeTransaction().apply(
      request(
        location: 6,
        original: "teh",
        replacement: "the"
      ),
      to: editor
    )

    #expect(report.status == .selectionRestoreFailed)
    #expect(report.writeOccurred)
    #expect(!report.caretRestored)
    #expect(editor.text as String == "alpha the omega")
  }

  @Test("An out-of-bounds target makes no edit")
  func rejectsOutOfBoundsTarget() {
    let editor = FakeBearEditableTextClient(
      text: "alpha teh omega",
      selection: AccessibilityTextRange(location: 10, length: 0)
    )

    let report = BearExactRangeTransaction().apply(
      request(
        location: 100,
        original: "teh",
        replacement: "the"
      ),
      to: editor
    )

    #expect(report.status == .targetOutOfBounds)
    #expect(!report.writeOccurred)
    #expect(editor.replacementWriteCount == 0)
  }

  @Test("Replacement reports contain no source or replacement text")
  func reportEncodingIsContentFree() throws {
    let report = BearExactRangeReplacementReport(
      status: .applied,
      writeOccurred: true,
      targetRange: AccessibilityTextRange(location: 6, length: 3),
      replacementRange: AccessibilityTextRange(location: 6, length: 3),
      selectionBefore: AccessibilityTextRange(location: 10, length: 0),
      selectionAfter: AccessibilityTextRange(location: 10, length: 0),
      surroundingContextVerified: true,
      caretRestored: true
    )

    let data = try JSONEncoder().encode(report)
    let json = try #require(String(data: data, encoding: .utf8))

    #expect(!json.contains("teh"))
    #expect(!json.contains("the"))
    #expect(!json.contains("original"))
    #expect(!json.contains("replacementText"))
  }

  @Test("A correction record is created only after verified or reconciled application")
  func adapterGatesCorrectionRecord() {
    let verifiedReport = BearExactRangeReplacementReport(
      status: .applied,
      writeOccurred: true,
      targetRange: AccessibilityTextRange(location: 6, length: 3),
      replacementRange: AccessibilityTextRange(location: 6, length: 3),
      selectionBefore: AccessibilityTextRange(location: 10, length: 0),
      selectionAfter: AccessibilityTextRange(location: 10, length: 0),
      surroundingContextVerified: true,
      caretRestored: true
    )
    let anchor = BearCorrectionAnchor(
      correctionRange: AccessibilityTextRange(location: 6, length: 3),
      documentLength: 15,
      leadingContext: "alpha ",
      trailingContext: " omega"
    )
    let failedReport = BearExactRangeReplacementReport(
      status: .verificationFailed,
      writeOccurred: true,
      targetRange: AccessibilityTextRange(location: 6, length: 3)
    )

    let verified = BearCorrectionAdapter(
      replacer: StubBearReplacer(
        report: verifiedReport,
        correctionAnchor: anchor
      )
    ).apply(
      original: "teh",
      replacement: "the",
      at: AccessibilityTextRange(location: 6, length: 3)
    )
    let failed = BearCorrectionAdapter(
      replacer: StubBearReplacer(report: failedReport)
    ).apply(
      original: "teh",
      replacement: "the",
      at: AccessibilityTextRange(location: 6, length: 3)
    )

    #expect(verified.correctionRecord?.correction.original == "teh")
    #expect(verified.correctionRecord?.correction.replacement == "the")
    #expect(failed.correction.original == "teh")
    #expect(failed.correction.replacement == "the")
    #expect(failed.correctionRecord == nil)
  }

  @Test("A post-write verification failure cannot be promoted by re-anchoring")
  func adapterRejectsPostWriteFailureReanchor() throws {
    let replacementRange = AccessibilityTextRange(location: 6, length: 3)
    let report = BearExactRangeReplacementReport(
      status: .verificationFailed,
      writeOccurred: true,
      targetRange: replacementRange,
      replacementRange: replacementRange,
      selectionBefore: AccessibilityTextRange(location: 10, length: 0),
      selectionAfter: AccessibilityTextRange(location: 10, length: 0),
      caretRestored: true
    )
    let anchor = BearCorrectionAnchor(
      correctionRange: replacementRange,
      documentLength: 15,
      leadingContext: "alpha ",
      trailingContext: " omega"
    )
    let adapter = BearCorrectionAdapter(
      replacer: StubBearReplacer(report: report),
      reanchorer: StubBearReanchorer(
        outcome: BearCorrectionReanchorOutcome(
          status: .reanchored,
          correctionAnchor: anchor
        )
      )
    )

    let application = adapter.apply(
      original: "teh",
      replacement: "the",
      at: replacementRange
    )

    #expect(!application.report.isVerifiedApplication)
    #expect(!application.isReversibleApplication)
    #expect(application.correctionAnchor == nil)
    #expect(application.correctionRecord == nil)
  }

  @Test("A verified synthetic edit is adopted without another write")
  func adapterAdoptsSyntheticCorrection() {
    let originalRange = AccessibilityTextRange(location: 6, length: 3)
    let replacementRange = AccessibilityTextRange(location: 6, length: 3)
    let anchor = BearCorrectionAnchor(
      correctionRange: replacementRange,
      documentLength: 10,
      leadingContext: "alpha ",
      trailingContext: " "
    )
    let adapter = BearCorrectionAdapter(
      replacer: StubBearReplacer(
        report: BearExactRangeReplacementReport(
          status: .replacementWriteFailed,
          targetRange: originalRange
        )
      ),
      reanchorer: StubBearReanchorer(
        outcome: BearCorrectionReanchorOutcome(
          status: .reanchored,
          correctionAnchor: anchor
        )
      )
    )

    let application = adapter.adoptSyntheticCorrection(
      BearSyntheticCorrectionAdoptionRequest(
        original: "teh",
        replacement: "the",
        originalRange: originalRange,
        replacementRange: replacementRange,
        selectionAfter: AccessibilityTextRange(location: 10, length: 0)
      )
    )

    #expect(application.report.status == .applied)
    #expect(application.report.isVerifiedApplication)
    #expect(application.report.selectionBefore == nil)
    #expect(application.isReversibleApplication)
    #expect(application.correctionAnchor == anchor)
    #expect(application.correctionRecord?.disposition == .applied)
  }

  @Test("An unverified synthetic write remains visible to the circuit breaker")
  func adapterRejectsUnverifiedSyntheticCorrection() {
    let adapter = BearCorrectionAdapter(
      reanchorer: StubBearReanchorer(
        outcome: BearCorrectionReanchorOutcome(status: .superseded)
      )
    )
    let application = adapter.adoptSyntheticCorrection(
      BearSyntheticCorrectionAdoptionRequest(
        original: "teh",
        replacement: "the",
        originalRange: AccessibilityTextRange(location: 0, length: 3),
        replacementRange: AccessibilityTextRange(location: 0, length: 3),
        selectionAfter: AccessibilityTextRange(location: 4, length: 0)
      )
    )

    #expect(application.report.status == .verificationFailed)
    #expect(application.report.writeOccurred)
    #expect(!application.report.isVerifiedApplication)
    #expect(!application.isReversibleApplication)
    #expect(application.correctionRecord == nil)
    #expect(application.correctionAnchor == nil)
  }

  @Test("Malformed synthetic adoption evidence is rejected")
  func adapterRejectsMalformedSyntheticEvidence() {
    let adapter = BearCorrectionAdapter()
    let application = adapter.adoptSyntheticCorrection(
      BearSyntheticCorrectionAdoptionRequest(
        original: "teh",
        replacement: "the",
        originalRange: AccessibilityTextRange(location: 0, length: 2),
        replacementRange: AccessibilityTextRange(location: 1, length: 3),
        selectionAfter: AccessibilityTextRange(location: 4, length: 1)
      )
    )

    #expect(application.report.status == .invalidRequest)
    #expect(application.report.writeOccurred)
    #expect(!application.isReversibleApplication)
  }

  @Test(
    "Live Bear transaction replaces the completed synthetic typo",
    .enabled(
      if: ProcessInfo.processInfo.environment[
        "TYPOVER_RUN_LIVE_BEAR_REPLACEMENT"
      ] == "1"
    )
  )
  func liveBearExactRangeReplacement() throws {
    let probe = BearAccessibilityProbe().run()
    let selection = try #require(probe.selectedRange)
    #expect(probe.status == .ready)
    let targetRange: AccessibilityTextRange
    if selection.length == 3 {
      targetRange = selection
    } else {
      #expect(selection.length == 0)
      #expect(selection.location >= 4)
      targetRange = AccessibilityTextRange(
        location: selection.location - 4,
        length: 3
      )
    }
    let adapter = BearCorrectionAdapter()
    let application = adapter.apply(
      original: "teh",
      replacement: "the",
      at: targetRange
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let encoded = try encoder.encode(application.report)
    let json = try #require(String(data: encoded, encoding: .utf8))
    print(json)

    #expect(application.report.isVerifiedApplication)
    #expect(application.correctionRecord != nil)

    let repeated = adapter.apply(
      original: "teh",
      replacement: "the",
      at: targetRange
    )
    #expect(repeated.report.status == .alreadyApplied)
    #expect(!repeated.report.writeOccurred)
    #expect(repeated.correctionRecord == nil)
  }

  @Test(
    "Live Bear native Undo reverses the Accessibility transaction",
    .enabled(
      if: ProcessInfo.processInfo.environment[
        "TYPOVER_RUN_LIVE_BEAR_UNDO"
      ] == "1"
    )
  )
  func liveBearUndo() throws {
    #expect(try performBearUndoMenuAction())
  }

  private func request(
    location: Int,
    original: String,
    replacement: String
  ) -> BearExactRangeReplacementRequest {
    BearExactRangeReplacementRequest(
      targetRange: AccessibilityTextRange(
        location: location,
        length: original.utf16.count
      ),
      expectedOriginal: original,
      replacement: replacement
    )
  }
}

@Suite("Bear correction selection stabilization")
struct BearCorrectionSelectionStabilizationTests {
  @Test("Bear's delayed transient caret is repaired")
  func repairsTransientCaret() {
    let editor = FakeBearEditableTextClient(
      text: "alpha the omega",
      selection: AccessibilityTextRange(location: 9, length: 0)
    )

    let status = BearCorrectionSelectionStabilizationTransaction().stabilize(
      request(desiredLocation: 13),
      in: editor
    )

    #expect(status == .stabilized)
    #expect(
      editor.selection == AccessibilityTextRange(location: 13, length: 0)
    )
  }

  @Test("A newer user selection always wins")
  func preservesNewerUserSelection() {
    let editor = FakeBearEditableTextClient(
      text: "alpha the omega",
      selection: AccessibilityTextRange(location: 11, length: 0)
    )

    let status = BearCorrectionSelectionStabilizationTransaction().stabilize(
      request(desiredLocation: 13),
      in: editor
    )

    #expect(status == .userMovedSelection)
    #expect(
      editor.selection == AccessibilityTextRange(location: 11, length: 0)
    )
  }

  @Test("The previous replacement end is a recognized Bear transient")
  func repairsPreviousReplacementEnd() {
    let editor = FakeBearEditableTextClient(
      text: "alpha tech omega",
      selection: AccessibilityTextRange(location: 9, length: 0)
    )
    let request = BearCorrectionSelectionStabilizationRequest(
      anchor: BearCorrectionAnchor(
        correctionRange: AccessibilityTextRange(location: 6, length: 4),
        documentLength: "alpha tech omega".utf16.count,
        leadingContext: "alpha ",
        trailingContext: " omega"
      ),
      expectedText: "tech",
      desiredSelection: AccessibilityTextRange(location: 14, length: 0),
      additionalTransientSelections: [
        AccessibilityTextRange(location: 9, length: 0)
      ]
    )

    let status = BearCorrectionSelectionStabilizationTransaction().stabilize(
      request,
      in: editor
    )

    #expect(status == .stabilized)
    #expect(
      editor.selection == AccessibilityTextRange(location: 14, length: 0)
    )
  }

  private func request(
    desiredLocation: Int
  ) -> BearCorrectionSelectionStabilizationRequest {
    BearCorrectionSelectionStabilizationRequest(
      anchor: BearCorrectionAnchor(
        correctionRange: AccessibilityTextRange(location: 6, length: 3),
        documentLength: "alpha the omega".utf16.count,
        leadingContext: "alpha ",
        trailingContext: " omega"
      ),
      expectedText: "the",
      desiredSelection: AccessibilityTextRange(
        location: desiredLocation,
        length: 0
      )
    )
  }
}

@Suite("Bear independent Change Back")
struct BearCorrectionRestorationTests {
  @Test("Change Back restores only the corrected range")
  func restoresCorrection() throws {
    let fixture = try makeAppliedFixture()

    let report = restore(fixture)

    #expect(report.status == .restored)
    #expect(report.writeOccurred)
    #expect(fixture.editor.text as String == fixture.originalDocument)
    #expect(fixture.editor.replacementWriteCount == 2)
  }

  @Test("Typing before the context re-anchors by document-length delta")
  func reanchorsAfterEditBefore() throws {
    let fixture = try makeAppliedFixture()
    fixture.editor.userReplace(
      AccessibilityTextRange(location: 0, length: 0),
      with: "inserted before "
    )

    let report = restore(fixture)

    #expect(report.status == .restored)
    #expect(
      fixture.editor.text as String
        == "inserted before " + fixture.originalDocument
    )
  }

  @Test("Typing after the context keeps the original anchor valid")
  func reanchorsAfterEditAfter() throws {
    let fixture = try makeAppliedFixture()
    let suffix = " user text written later"
    fixture.editor.userReplace(
      AccessibilityTextRange(
        location: fixture.editor.text.length,
        length: 0
      ),
      with: suffix
    )

    let report = restore(fixture)

    #expect(report.status == .restored)
    #expect(fixture.editor.text as String == fixture.originalDocument + suffix)
  }

  @Test("An externally restored original is recognized without another write")
  func recognizesAlreadyRestored() throws {
    let fixture = try makeAppliedFixture()
    fixture.editor.userReplace(
      fixture.anchor.correctionRange,
      with: "teh"
    )
    let writeCount = fixture.editor.replacementWriteCount

    let report = restore(fixture)

    #expect(report.status == .alreadyRestored)
    #expect(!report.writeOccurred)
    #expect(fixture.editor.replacementWriteCount == writeCount)
  }

  @Test("A manually changed correction is superseded and never overwritten")
  func refusesSupersededCorrection() throws {
    let fixture = try makeAppliedFixture()
    fixture.editor.userReplace(
      fixture.anchor.correctionRange,
      with: "thy"
    )

    let report = restore(fixture)

    #expect(report.status == .superseded)
    #expect(!report.writeOccurred)
    #expect((fixture.editor.text as String).contains(" thy "))
  }

  @Test("Duplicated surrounding context is ambiguous and never edited")
  func refusesAmbiguousAnchor() throws {
    let fixture = try makeAppliedFixture()
    let duplicate =
      String(repeating: "a", count: 60)
      + " the "
      + String(repeating: "z", count: 60)
    fixture.editor.userReplace(
      AccessibilityTextRange(
        location: fixture.editor.text.length,
        length: 0
      ),
      with: duplicate
    )
    let textBefore = fixture.editor.text as String

    let report = restore(fixture)

    #expect(report.status == .invalidated)
    #expect(report.candidateCount > 1)
    #expect(!report.writeOccurred)
    #expect(fixture.editor.text as String == textBefore)
  }

  @Test("One changed context side keeps a unique correction anchored")
  func acceptsOneChangedSide() throws {
    let fixture = try makeAppliedFixture()
    fixture.editor.userReplace(
      AccessibilityTextRange(
        location: fixture.anchor.correctionRange.location - 2,
        length: 1
      ),
      with: "x"
    )

    let report = restore(fixture)

    #expect(report.status == .restored)
    #expect(report.writeOccurred)
    #expect((fixture.editor.text as String).contains("x teh "))
  }

  @Test("Changes on both context sides invalidate without editing")
  func refusesTwoChangedSides() throws {
    let fixture = try makeAppliedFixture()
    fixture.editor.userReplace(
      AccessibilityTextRange(
        location: fixture.anchor.correctionRange.location - 2,
        length: 1
      ),
      with: "x"
    )
    fixture.editor.userReplace(
      AccessibilityTextRange(
        location: fixture.anchor.correctionRange.location
          + fixture.anchor.correctionRange.length + 2,
        length: 1
      ),
      with: "y"
    )
    let textBefore = fixture.editor.text as String

    let report = restore(fixture)

    #expect(report.status == .invalidated)
    #expect(report.candidateCount == 0)
    #expect(!report.writeOccurred)
    #expect(fixture.editor.text as String == textBefore)
  }

  @Test("Typing immediately after a correction preserves Change Back")
  func restoresWhileTypingContinues() throws {
    let fixture = try makeAppliedFixture()
    fixture.editor.userReplace(
      AccessibilityTextRange(
        location: fixture.anchor.correctionRange.location
          + fixture.anchor.correctionRange.length + 1,
        length: 0
      ),
      with: "newly typed "
    )

    let report = restore(fixture)

    #expect(report.status == .restored)
    #expect(
      (fixture.editor.text as String).contains(" teh newly typed ")
    )
  }

  @Test("Rapid continued typing remains outside the restored range")
  func restoresAfterRapidTyping() throws {
    let fixture = try makeAppliedFixture()
    var insertionLocation =
      fixture.anchor.correctionRange.location
      + fixture.anchor.correctionRange.length + 1
    for chunk in ["rapid ", "typing ", "continues "] {
      fixture.editor.userReplace(
        AccessibilityTextRange(location: insertionLocation, length: 0),
        with: chunk
      )
      insertionLocation += chunk.utf16.count
    }

    let report = restore(fixture)

    #expect(report.status == .restored)
    #expect(
      (fixture.editor.text as String).contains(
        " teh rapid typing continues "
      )
    )
  }

  @Test("Stored anchors contain fingerprints rather than surrounding prose")
  func anchorIsContentPrivate() throws {
    let fixture = try makeAppliedFixture()
    let data = try JSONEncoder().encode(fixture.anchor)
    let json = try #require(String(data: data, encoding: .utf8))

    #expect(!json.contains(String(repeating: "a", count: 39)))
    #expect(!json.contains(String(repeating: "z", count: 39)))
    #expect(!json.contains("teh"))
    #expect(!json.contains("the"))
  }

  @Test("An alternative replaces only the anchored correction")
  func appliesAlternative() throws {
    let fixture = try makeAppliedFixture()
    let selectionBefore = fixture.editor.selection

    let outcome = retarget(fixture, replacement: "ten")

    #expect(outcome.report.status == .applied)
    #expect(outcome.report.writeOccurred)
    #expect((fixture.editor.text as String).contains(" ten "))
    #expect(fixture.editor.selection == selectionBefore)
    #expect(outcome.correctionAnchor?.correctionRange.length == 3)
  }

  @Test("An alternative re-anchors after earlier typing")
  func reanchorsAlternative() throws {
    let fixture = try makeAppliedFixture()
    fixture.editor.userReplace(
      AccessibilityTextRange(location: 0, length: 0),
      with: "earlier "
    )

    let outcome = retarget(fixture, replacement: "ten")

    #expect(outcome.report.status == .applied)
    #expect(
      outcome.report.matchedRange?.location
        == fixture.anchor.correctionRange.location + 8
    )
    #expect((fixture.editor.text as String).contains(" ten "))
  }

  @Test("An alternative remains available while typing continues")
  func appliesAlternativeWhileTypingContinues() throws {
    let fixture = try makeAppliedFixture()
    fixture.editor.userReplace(
      AccessibilityTextRange(
        location: fixture.anchor.correctionRange.location
          + fixture.anchor.correctionRange.length + 1,
        length: 0
      ),
      with: "newly typed "
    )

    let outcome = retarget(fixture, replacement: "ten")

    #expect(outcome.report.status == .applied)
    #expect(
      (fixture.editor.text as String).contains(" ten newly typed ")
    )
  }

  @Test("A manually superseded correction rejects an alternative")
  func refusesAlternativeAfterSupersession() throws {
    let fixture = try makeAppliedFixture()
    fixture.editor.userReplace(
      fixture.anchor.correctionRange,
      with: "thy"
    )

    let outcome = retarget(fixture, replacement: "ten")

    #expect(outcome.report.status == .superseded)
    #expect(!outcome.report.writeOccurred)
    #expect((fixture.editor.text as String).contains(" thy "))
  }

  @Test("Repeating an alternative is idempotent and refreshes its anchor")
  func recognizesAppliedAlternative() throws {
    let fixture = try makeAppliedFixture()
    let first = retarget(fixture, replacement: "ten")
    let writeCount = fixture.editor.replacementWriteCount
    let refreshedAnchor = try #require(first.correctionAnchor)

    let repeated = BearCorrectionRetargetTransaction().retarget(
      BearCorrectionRetargetRequest(
        anchor: refreshedAnchor,
        expectedCurrent: "the",
        replacement: "ten"
      ),
      in: fixture.editor
    )

    #expect(repeated.report.status == .alreadyApplied)
    #expect(!repeated.report.writeOccurred)
    #expect(fixture.editor.replacementWriteCount == writeCount)
    #expect(repeated.correctionAnchor != nil)
  }

  @Test("The Bear adapter carries the original into an alternative record")
  func adapterBuildsAlternativeApplication() throws {
    let fixture = try makeAppliedFixture()
    let correction = Correction(original: "teh", replacement: "the")
    let application = BearCorrectionApplication(
      report: BearExactRangeReplacementReport(
        status: .applied,
        writeOccurred: true,
        targetRange: fixture.anchor.correctionRange,
        replacementRange: fixture.anchor.correctionRange,
        surroundingContextVerified: true,
        caretRestored: true
      ),
      correction: correction,
      correctionRecord: CorrectionRecord(correction: correction),
      correctionAnchor: fixture.anchor
    )
    let replacementReport = BearExactRangeReplacementReport(
      status: .applied,
      writeOccurred: true,
      targetRange: fixture.anchor.correctionRange,
      replacementRange: fixture.anchor.correctionRange,
      surroundingContextVerified: true,
      caretRestored: true
    )
    let adapter = BearCorrectionAdapter(
      retargeter: StubBearRetargeter(
        outcome: BearCorrectionRetargetOutcome(
          report: BearCorrectionRetargetReport(
            status: .applied,
            writeOccurred: true,
            matchedRange: fixture.anchor.correctionRange,
            candidateCount: 1,
            replacementReport: replacementReport
          ),
          correctionAnchor: fixture.anchor
        )
      )
    )

    let result = adapter.chooseAlternative("ten", for: application)

    #expect(result.report.status == .applied)
    #expect(result.application?.correction.original == "teh")
    #expect(result.application?.correction.replacement == "ten")
    #expect(result.application?.correctionRecord?.disposition == .applied)
  }

  @Test("The Bear adapter maps restoration outcomes to explicit dispositions")
  func adapterTransitionsDisposition() throws {
    let fixture = try makeAppliedFixture()
    let correction = Correction(original: "teh", replacement: "the")
    let application = BearCorrectionApplication(
      report: BearExactRangeReplacementReport(
        status: .applied,
        writeOccurred: true,
        targetRange: AccessibilityTextRange(location: 61, length: 3),
        replacementRange: fixture.anchor.correctionRange,
        surroundingContextVerified: true,
        caretRestored: true
      ),
      correction: correction,
      correctionRecord: CorrectionRecord(correction: correction),
      correctionAnchor: fixture.anchor
    )

    let restored = BearCorrectionAdapter(
      replacer: StubBearReplacer(report: application.report),
      restorer: StubBearRestorer(status: .restored)
    ).changeBack(application)
    let superseded = BearCorrectionAdapter(
      replacer: StubBearReplacer(report: application.report),
      restorer: StubBearRestorer(status: .superseded)
    ).changeBack(application)
    let invalidated = BearCorrectionAdapter(
      replacer: StubBearReplacer(report: application.report),
      restorer: StubBearRestorer(status: .invalidated)
    ).changeBack(application)

    #expect(restored.correctionRecord.disposition == .restored)
    #expect(superseded.correctionRecord.disposition == .superseded)
    #expect(invalidated.correctionRecord.disposition == .invalidated)
  }

  @Test(
    "Live Bear Change Back restores the synthetic correction",
    .enabled(
      if: ProcessInfo.processInfo.environment[
        "TYPOVER_RUN_LIVE_BEAR_CHANGE_BACK"
      ] == "1"
    )
  )
  func liveBearChangeBack() throws {
    let probe = BearAccessibilityProbe().run()
    let selection = try #require(probe.selectedRange)
    #expect(probe.status == .ready)
    let targetRange: AccessibilityTextRange
    if selection.length == 3 {
      targetRange = selection
    } else {
      #expect(selection.length == 0)
      #expect(selection.location >= 4)
      targetRange = AccessibilityTextRange(
        location: selection.location - 4,
        length: 3
      )
    }
    let adapter = BearCorrectionAdapter()
    let application = adapter.apply(
      original: "teh",
      replacement: "the",
      at: targetRange
    )
    let record = try #require(application.correctionRecord)
    #expect(record.disposition == .applied)

    let restoration = adapter.changeBack(application)
    #expect(restoration.report.status == .restored)
    #expect(restoration.correctionRecord.disposition == .restored)
  }

  private func makeAppliedFixture() throws -> AppliedFixture {
    let originalDocument =
      String(repeating: "a", count: 60)
      + " teh "
      + String(repeating: "z", count: 60)
    let editor = FakeBearEditableTextClient(
      text: originalDocument,
      selection: AccessibilityTextRange(
        location: originalDocument.utf16.count,
        length: 0
      )
    )
    let outcome = BearExactRangeTransaction().applyOutcome(
      BearExactRangeReplacementRequest(
        targetRange: AccessibilityTextRange(location: 61, length: 3),
        expectedOriginal: "teh",
        replacement: "the"
      ),
      to: editor
    )
    let report = outcome.report
    #expect(report.status == .applied)
    return AppliedFixture(
      editor: editor,
      anchor: try #require(outcome.correctionAnchor),
      originalDocument: originalDocument
    )
  }

  private func restore(
    _ fixture: AppliedFixture
  ) -> BearCorrectionRestorationReport {
    BearCorrectionRestorationTransaction().restore(
      BearCorrectionRestorationRequest(
        anchor: fixture.anchor,
        expectedReplacement: "the",
        original: "teh"
      ),
      in: fixture.editor
    )
  }

  private func retarget(
    _ fixture: AppliedFixture,
    replacement: String
  ) -> BearCorrectionRetargetOutcome {
    BearCorrectionRetargetTransaction().retarget(
      BearCorrectionRetargetRequest(
        anchor: fixture.anchor,
        expectedCurrent: "the",
        replacement: replacement
      ),
      in: fixture.editor
    )
  }
}

private struct AppliedFixture {
  let editor: FakeBearEditableTextClient
  let anchor: BearCorrectionAnchor
  let originalDocument: String
}

private func performBearUndoMenuAction() throws -> Bool {
  let application = try #require(
    NSRunningApplication.runningApplications(
      withBundleIdentifier: BearAccessibilityProbe.bearBundleIdentifier
    ).first
  )
  application.activate(options: [.activateAllWindows])
  let applicationElement = AXUIElementCreateApplication(
    application.processIdentifier
  )
  let menuBar = try #require(
    testElementAttribute(
      applicationElement,
      kAXMenuBarAttribute as CFString
    )
  )
  let editMenu = try #require(
    testDescendants(of: menuBar).first { element in
      testStringAttribute(element, kAXRoleAttribute as CFString)
        == (kAXMenuBarItemRole as String)
        && testStringAttribute(element, kAXTitleAttribute as CFString)
          == "Edit"
    }
  )
  guard
    AXUIElementPerformAction(
      editMenu,
      kAXPressAction as CFString
    ) == .success
  else {
    return false
  }

  CFRunLoopRunInMode(.defaultMode, 0.1, false)
  let undoItem = try #require(
    testDescendants(of: editMenu).first { element in
      testStringAttribute(element, kAXRoleAttribute as CFString)
        == (kAXMenuItemRole as String)
        && testStringAttribute(element, kAXTitleAttribute as CFString)?
          .hasPrefix("Undo") == true
    }
  )
  return AXUIElementPerformAction(
    undoItem,
    kAXPressAction as CFString
  ) == .success
}

private func testDescendants(of root: AXUIElement) -> [AXUIElement] {
  var result: [AXUIElement] = []
  var queue = [root]
  var visited = Set<ObjectIdentifier>()
  while !queue.isEmpty, visited.count < 200 {
    let element = queue.removeFirst()
    guard visited.insert(ObjectIdentifier(element)).inserted else {
      continue
    }
    result.append(element)
    queue.append(
      contentsOf: testElementArrayAttribute(
        element,
        kAXChildrenAttribute as CFString
      )
    )
  }
  return result
}

private func testElementAttribute(
  _ element: AXUIElement,
  _ name: CFString
) -> AXUIElement? {
  var value: CFTypeRef?
  guard
    AXUIElementCopyAttributeValue(element, name, &value) == .success,
    let value,
    CFGetTypeID(value) == AXUIElementGetTypeID()
  else {
    return nil
  }
  return unsafeDowncast(value, to: AXUIElement.self)
}

private func testElementArrayAttribute(
  _ element: AXUIElement,
  _ name: CFString
) -> [AXUIElement] {
  var value: CFTypeRef?
  guard
    AXUIElementCopyAttributeValue(element, name, &value) == .success,
    let value,
    CFGetTypeID(value) == CFArrayGetTypeID()
  else {
    return []
  }
  let values = unsafeDowncast(value, to: CFArray.self)
  return (0..<CFArrayGetCount(values)).compactMap { index in
    guard let pointer = CFArrayGetValueAtIndex(values, index) else {
      return nil
    }
    let child = unsafeBitCast(pointer, to: CFTypeRef.self)
    guard CFGetTypeID(child) == AXUIElementGetTypeID() else {
      return nil
    }
    return unsafeDowncast(child, to: AXUIElement.self)
  }
}

private func testStringAttribute(
  _ element: AXUIElement,
  _ name: CFString
) -> String? {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, name, &value) == .success else {
    return nil
  }
  return value as? String
}

private final class FakeBearEditableTextClient: BearEditableTextClient {
  let text: NSMutableString
  private(set) var selection: AccessibilityTextRange
  private var selectionErrors: [AXError]
  private let replacementError: AXError
  private let appendedTextAfterReplacement: String?
  private(set) var replacementWriteCount = 0

  init(
    text: String,
    selection: AccessibilityTextRange,
    selectionErrors: [AXError] = [],
    replacementError: AXError = .success,
    appendedTextAfterReplacement: String? = nil
  ) {
    self.text = NSMutableString(string: text)
    self.selection = selection
    self.selectionErrors = selectionErrors
    self.replacementError = replacementError
    self.appendedTextAfterReplacement = appendedTextAfterReplacement
  }

  func selectedRange() -> AccessibilityTextRange? {
    selection
  }

  func characterCount() -> Int? {
    text.length
  }

  func string(in range: AccessibilityTextRange) -> String? {
    let nsRange = NSRange(location: range.location, length: range.length)
    guard
      nsRange.location >= 0,
      nsRange.length >= 0,
      NSMaxRange(nsRange) <= text.length
    else {
      return nil
    }
    return text.substring(with: nsRange)
  }

  func setSelectedRange(_ range: AccessibilityTextRange) -> AXError {
    if !selectionErrors.isEmpty {
      let error = selectionErrors.removeFirst()
      guard error == .success else {
        return error
      }
    }
    selection = range
    return .success
  }

  func replaceSelectedText(with replacement: String) -> AXError {
    guard replacementError == .success else {
      return replacementError
    }
    replacementWriteCount += 1
    text.replaceCharacters(
      in: NSRange(location: selection.location, length: selection.length),
      with: replacement
    )
    selection = AccessibilityTextRange(
      location: selection.location + replacement.utf16.count,
      length: 0
    )
    if let appendedTextAfterReplacement {
      text.append(appendedTextAfterReplacement)
    }
    return .success
  }

  func userReplace(
    _ range: AccessibilityTextRange,
    with replacement: String
  ) {
    let delta = replacement.utf16.count - range.length
    text.replaceCharacters(
      in: NSRange(location: range.location, length: range.length),
      with: replacement
    )
    let rangeEnd = range.location + range.length
    if selection.location >= rangeEnd {
      selection = AccessibilityTextRange(
        location: selection.location + delta,
        length: selection.length
      )
    } else if selection.location > range.location {
      selection = AccessibilityTextRange(
        location: range.location + replacement.utf16.count,
        length: 0
      )
    }
  }
}

private struct StubBearReplacer: BearExactRangeReplacing {
  let report: BearExactRangeReplacementReport
  let correctionAnchor: BearCorrectionAnchor?

  init(
    report: BearExactRangeReplacementReport,
    correctionAnchor: BearCorrectionAnchor? = nil
  ) {
    self.report = report
    self.correctionAnchor = correctionAnchor
  }

  func replace(
    _: BearExactRangeReplacementRequest
  ) -> BearExactRangeReplacementOutcome {
    BearExactRangeReplacementOutcome(
      report: report,
      correctionAnchor: correctionAnchor
    )
  }
}

private struct StubBearRestorer: BearCorrectionRestoring {
  let status: BearCorrectionRestorationStatus

  func restore(
    _: BearCorrectionRestorationRequest
  ) -> BearCorrectionRestorationReport {
    BearCorrectionRestorationReport(status: status)
  }
}

private struct StubBearRetargeter: BearCorrectionRetargeting {
  let outcome: BearCorrectionRetargetOutcome

  func retarget(
    _: BearCorrectionRetargetRequest
  ) -> BearCorrectionRetargetOutcome {
    outcome
  }
}

private struct StubBearReanchorer: BearCorrectionReanchoring {
  let outcome: BearCorrectionReanchorOutcome

  func reanchor(
    _: BearCorrectionReanchorRequest
  ) -> BearCorrectionReanchorOutcome {
    outcome
  }
}
