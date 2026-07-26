import AppKit
import Foundation
import Testing
import TypoverCore

@testable import TypoverApp

@MainActor
@Suite(.serialized)
struct EditorStressTests {
  @Test("Rapid typing applies many consecutive corrections to exact ranges")
  func rapidConsecutiveCorrections() {
    let fixture = EditorFixture()
    defer { fixture.removeLearningStore() }

    for _ in 0..<10 {
      fixture.type("teh recieve speling ")
    }

    let expectedUnit = "the receive spelling "
    #expect(fixture.editor.string == String(repeating: expectedUnit, count: 10))
    #expect(fixture.appliedSnapshots.count == 30)
    #expect(
      fixture.appliedSnapshots.allSatisfy {
        $0.annotatedRanges.count == 1
      }
    )
    #expect(fixture.editor.correctionDiagnostics.isEmpty)
    #expect(fixture.editor.correctionTransactionSamples.count == 30)
    #expect(
      fixture.editor.correctionTransactionSamples.allSatisfy {
        $0.elapsed >= .zero
      }
    )
  }

  @Test("A proposal is rejected when its source text changes during lookup")
  func rejectsStaleProposal() {
    let fixture = EditorFixture()
    defer { fixture.removeLearningStore() }
    weak let editor = fixture.editor
    fixture.engine.beforeProposal = { word in
      guard word == "teh", let editor else {
        return
      }
      editor.textStorage?.replaceCharacters(
        in: NSRange(location: 0, length: 3),
        with: "ten"
      )
    }

    fixture.type("teh ")

    #expect(fixture.editor.string == "ten ")
    #expect(fixture.appliedSnapshots.isEmpty)
    #expect(
      fixture.editor.correctionSnapshots.first?.disposition == .invalidated
    )
    let diagnostic = fixture.editor.correctionDiagnostics.last
    #expect(diagnostic?.kind == .staleText)
    #expect(diagnostic?.rangeLocation == 0)
    #expect(diagnostic?.rangeLength == 3)
    #expect(diagnostic?.documentUTF16Length == 4)
  }

  @Test("Corrections remain aligned before and after moving the caret")
  func correctionsBeforeAndAfterCaret() {
    let fixture = EditorFixture(initialText: "Anchor\n")
    defer { fixture.removeLearningStore() }

    fixture.moveCaret(to: fixture.editor.string.utf16.count)
    fixture.type("teh ")
    fixture.moveCaret(to: 0)
    fixture.type("wrod ")
    fixture.moveCaret(to: fixture.editor.string.utf16.count)
    fixture.type("recieve ")

    #expect(fixture.editor.string == "word Anchor\nthe receive ")
    #expect(fixture.appliedSnapshots.count == 3)
    #expect(
      fixture.appliedSnapshots
        .flatMap(\.annotatedRanges)
        .map(\.location)
        .sorted() == [0, 12, 16]
    )
  }

  @Test("Edits before and after a correction preserve its annotation")
  func editsAroundAnnotation() throws {
    let fixture = EditorFixture()
    defer { fixture.removeLearningStore() }
    fixture.type("teh ")
    let id = try #require(fixture.appliedSnapshots.first?.correction.id)

    fixture.moveCaret(to: 0)
    fixture.type("A ")
    fixture.moveCaret(to: fixture.editor.string.utf16.count)
    fixture.type("tail")

    let snapshot = try #require(
      fixture.editor.correctionSnapshots.first(where: {
        $0.correction.id == id
      })
    )
    #expect(fixture.editor.string == "A the tail")
    #expect(snapshot.disposition == .applied)
    #expect(snapshot.annotatedRanges == [NSRange(location: 2, length: 3)])
    #expect(fixture.editor.correctionDiagnostics.isEmpty)
  }

  @Test("An edit inside a correction explicitly invalidates its annotation")
  func editInsideAnnotation() throws {
    let fixture = EditorFixture()
    defer { fixture.removeLearningStore() }
    fixture.type("teh ")
    let range = try #require(
      fixture.appliedSnapshots.first?.annotatedRanges.first
    )

    fixture.editor.insertText(
      "x",
      replacementRange: NSRange(location: range.location + 1, length: 1)
    )

    #expect(fixture.editor.string == "txe ")
    #expect(
      fixture.editor.correctionSnapshots.first?.disposition == .invalidated
    )
    #expect(fixture.editor.correctionSnapshots.first?.annotatedRanges.isEmpty == true)
    #expect(
      fixture.editor.correctionDiagnostics.last?.kind
        == .annotationInvalidated
    )
  }

  @Test("Selection replacement corrects only the newly typed word")
  func selectionReplacement() {
    let fixture = EditorFixture(initialText: "keep replace tail")
    defer { fixture.removeLearningStore() }
    fixture.editor.setSelectedRange(NSRange(location: 5, length: 8))

    fixture.type("teh ")

    #expect(fixture.editor.string == "keep the tail")
    #expect(fixture.appliedSnapshots.count == 1)
    #expect(
      fixture.appliedSnapshots.first?.annotatedRanges
        == [NSRange(location: 5, length: 3)]
    )
  }

  @Test("Pasted text is inserted without being auto-corrected")
  func pasteDoesNotCorrectExistingText() {
    let fixture = EditorFixture(initialText: "before after")
    defer { fixture.removeLearningStore() }
    fixture.editor.setSelectedRange(NSRange(location: 7, length: 5))

    fixture.editor.insertPastedTextForTesting("teh ")

    #expect(fixture.editor.string == "before teh ")
    #expect(fixture.editor.correctionSnapshots.isEmpty)
    #expect(fixture.editor.correctionDiagnostics.last?.kind == .pasteSkipped)
  }

  @Test("Marked-text composition does not create a correction")
  func markedTextDoesNotCorrect() {
    let fixture = EditorFixture()
    defer { fixture.removeLearningStore() }

    fixture.editor.setMarkedText(
      "teh ",
      selectedRange: NSRange(location: 4, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0)
    )

    #expect(fixture.editor.string == "teh ")
    #expect(fixture.editor.correctionSnapshots.isEmpty)
  }

  @Test("Punctuation and paragraph boundaries trigger exact-word correction")
  func punctuationAndParagraphBoundaries() {
    let fixture = EditorFixture()
    defer { fixture.removeLearningStore() }

    fixture.type("teh. wrod,\nrecieve\n")

    #expect(fixture.editor.string == "the. word,\nreceive\n")
    #expect(fixture.appliedSnapshots.count == 3)
    #expect(fixture.editor.correctionDiagnostics.isEmpty)
  }

  @Test("An earlier-page correction leaves a large document unchanged elsewhere")
  func earlierPageInLargeDocument() {
    let paragraphs = (0..<600)
      .map { "Paragraph \($0) remains exactly as written." }
    let document = paragraphs.joined(separator: "\n")
    let insertionMarker = "Paragraph 120"
    let insertionLocation = (document as NSString).range(
      of: insertionMarker
    ).location
    let fixture = EditorFixture(initialText: document)
    defer { fixture.removeLearningStore() }
    fixture.moveCaret(to: insertionLocation)

    fixture.type("teh ")

    let expected = (document as NSString).replacingCharacters(
      in: NSRange(location: insertionLocation, length: 0),
      with: "the "
    )
    #expect(fixture.editor.string == expected)
    #expect(fixture.appliedSnapshots.count == 1)
    #expect(
      fixture.appliedSnapshots.first?.annotatedRanges
        == [NSRange(location: insertionLocation, length: 3)]
    )
  }

  @Test("Wrapping and viewport movement preserve correction annotations")
  func wrappingAndViewportMovement() throws {
    let fixture = EditorFixture()
    defer { fixture.removeLearningStore() }
    fixture.editor.frame = NSRect(x: 0, y: 0, width: 180, height: 2000)
    fixture.type(String(repeating: "ordinary ", count: 80))
    fixture.type("teh ")
    let correction = try #require(fixture.appliedSnapshots.first)
    let range = try #require(correction.annotatedRanges.first)

    fixture.editor.scrollRangeToVisible(range)
    fixture.editor.layoutSubtreeIfNeeded()

    let refreshed = try #require(
      fixture.editor.correctionSnapshots.first(where: {
        $0.correction.id == correction.correction.id
      })
    )
    #expect(refreshed.disposition == .applied)
    #expect(refreshed.annotatedRanges == [range])
  }

  @Test("Undo and redo the automatic correction")
  func undoRedoAutomaticCorrection() {
    let fixture = EditorFixture(initialText: "teh ")
    defer { fixture.removeLearningStore() }
    fixture.editor.undoManager?.removeAllActions()
    fixture.editor.applyPendingCorrectionForTesting()

    fixture.editor.undoManager?.undo()
    #expect(fixture.editor.string == "teh ")
    #expect(fixture.editor.correctionSnapshots.first?.disposition == .restored)

    fixture.editor.undoManager?.redo()
    #expect(fixture.editor.string == "the ")
    #expect(fixture.editor.correctionSnapshots.first?.disposition == .applied)
  }

  @Test("Undo and redo Change Back")
  func undoRedoChangeBack() throws {
    let fixture = EditorFixture()
    defer { fixture.removeLearningStore() }
    fixture.type("teh ")
    let id = try #require(fixture.appliedSnapshots.first?.correction.id)
    fixture.editor.undoManager?.removeAllActions()

    #expect(fixture.editor.changeBack(correctionID: id))
    #expect(fixture.editor.string == "teh ")

    fixture.editor.undoManager?.undo()
    #expect(fixture.editor.string == "the ")
    #expect(fixture.editor.correctionSnapshots.first?.disposition == .applied)

    fixture.editor.undoManager?.redo()
    #expect(fixture.editor.string == "teh ")
    #expect(fixture.editor.correctionSnapshots.first?.disposition == .restored)
  }

  @Test("A learned suppression explains why a typo stays unchanged")
  func learnedSuppressionIsReported() throws {
    let fixture = EditorFixture()
    defer { fixture.removeLearningStore() }
    var reportedOriginal: String?
    fixture.editor.onLearnedSuppression = { original in
      reportedOriginal = original
    }
    fixture.type("teh ")
    let id = try #require(fixture.appliedSnapshots.first?.correction.id)
    #expect(fixture.editor.changeBack(correctionID: id))

    fixture.moveCaret(to: fixture.editor.string.utf16.count)
    fixture.type("teh ")

    #expect(fixture.editor.string == "teh teh ")
    #expect(reportedOriginal == "teh")
  }

  @Test("Undo and redo an alternative correction")
  func undoRedoAlternative() throws {
    let fixture = EditorFixture()
    defer { fixture.removeLearningStore() }
    fixture.type("teh ")
    let id = try #require(fixture.appliedSnapshots.first?.correction.id)
    fixture.editor.undoManager?.removeAllActions()

    #expect(
      fixture.editor.useAlternative(
        correctionID: id,
        replacement: "ten"
      )
    )
    #expect(fixture.editor.string == "ten ")

    fixture.editor.undoManager?.undo()
    #expect(fixture.editor.string == "the ")

    fixture.editor.undoManager?.redo()
    #expect(fixture.editor.string == "ten ")
    #expect(
      fixture.editor.correctionSnapshots.first?.correction.replacement == "ten"
    )
  }

  @Test("Removing a shared learned choice changes the next correction")
  func removedSharedChoiceTakesEffectImmediately() throws {
    let fixture = EditorFixture()
    defer { fixture.removeLearningStore() }
    fixture.type("teh ")
    let id = try #require(fixture.appliedSnapshots.first?.correction.id)
    #expect(
      fixture.editor.useAlternative(
        correctionID: id,
        replacement: "ten"
      )
    )
    let rule = try #require(fixture.learningStore.rememberedRules.first)

    fixture.learningStore.removeRule(rule.id)
    fixture.moveCaret(to: fixture.editor.string.utf16.count)
    fixture.type("teh ")

    #expect(fixture.editor.string == "ten the ")
  }

  @Test("The correction menu uses concise native-style choices")
  func correctionMenuHasConciseChoices() throws {
    let fixture = EditorFixture()
    defer { fixture.removeLearningStore() }
    fixture.type("teh ")
    let id = try #require(fixture.appliedSnapshots.first?.correction.id)
    let menu = try #require(fixture.editor.correctionMenu(for: id))
    let titles = menu.items
      .filter { !$0.isSeparatorItem }
      .map(\.title)

    #expect(titles.contains("Revert to “teh”"))
    #expect(titles.contains("ten"))
    #expect(titles.contains("Apple Spelling"))
    #expect(!titles.contains(where: { $0.hasPrefix("Change to ") }))
    #expect(!titles.contains("Keep Correction"))
  }

  @Test(
    "Contextual correction can finish while typing continues after the sentence"
  )
  func contextualCorrectionWhileTypingContinues() async throws {
    let contextualEngine = ImmediateContextualEngine(
      candidate: ContextualCorrectionCandidate(
        original: "Their",
        replacement: "They're"
      )
    )
    let fixture = EditorFixture(
      contextualCorrectionEngine: contextualEngine
    )
    defer { fixture.removeLearningStore() }

    fixture.type("Their going home.")
    fixture.type(" Next")
    await fixture.editor.waitForContextualCorrectionForTesting()

    #expect(fixture.editor.string == "They're going home. Next")
    let snapshot = try #require(fixture.appliedSnapshots.first)
    #expect(
      snapshot.annotatedRanges == [
        NSRange(location: 0, length: "They're".utf16.count)
      ]
    )
    let menu = try #require(
      fixture.editor.correctionMenu(for: snapshot.correction.id)
    )
    #expect(
      menu.items.map(\.title).contains(
        "Apple Intelligence"
      )
    )
  }

  @Test("A contextual proposal is discarded when its sentence changes")
  func contextualCorrectionRejectsStaleSentence() async {
    let contextualEngine = SuspendedContextualEngine(
      candidate: ContextualCorrectionCandidate(
        original: "Their",
        replacement: "They're"
      )
    )
    let fixture = EditorFixture(
      contextualCorrectionEngine: contextualEngine
    )
    defer { fixture.removeLearningStore() }

    fixture.type("Their going home.")
    await contextualEngine.waitUntilRequested()
    fixture.editor.insertText(
      "x",
      replacementRange: NSRange(location: 1, length: 0)
    )
    await contextualEngine.resume()
    await fixture.editor.waitForContextualCorrectionForTesting()

    #expect(fixture.editor.string == "Txheir going home.")
    #expect(fixture.appliedSnapshots.isEmpty)
    #expect(
      fixture.editor.correctionDiagnostics.last?.kind
        == .contextualStaleSentence
    )
  }

  @Test(
    "Changing back a contextual correction records the outcome without a global rule"
  )
  func contextualChangeBackDoesNotCreateGlobalPreference() async throws {
    let contextualEngine = ImmediateContextualEngine(
      candidate: ContextualCorrectionCandidate(
        original: "it's",
        replacement: "its"
      )
    )
    let fixture = EditorFixture(
      contextualCorrectionEngine: contextualEngine
    )
    defer { fixture.removeLearningStore() }

    fixture.type("The dog wagged it's tail.")
    await fixture.editor.waitForContextualCorrectionForTesting()
    let id = try #require(fixture.appliedSnapshots.first?.correction.id)

    #expect(fixture.editor.changeBack(correctionID: id))
    #expect(fixture.editor.string == "The dog wagged it's tail.")
    #expect(fixture.learningStore.rememberedRules.isEmpty)
    #expect(fixture.learningStore.statistics().correctionsApplied == 1)
    #expect(fixture.learningStore.statistics().reverted == 1)
  }

  @Test("Undo and redo treat a contextual correction as one transaction")
  func undoRedoContextualCorrection() async {
    let contextualEngine = ImmediateContextualEngine(
      candidate: ContextualCorrectionCandidate(
        original: "Their",
        replacement: "They're"
      )
    )
    let fixture = EditorFixture(
      contextualCorrectionEngine: contextualEngine
    )
    defer { fixture.removeLearningStore() }

    fixture.type("Their going home")
    fixture.editor.undoManager?.removeAllActions()
    fixture.type(".")
    await fixture.editor.waitForContextualCorrectionForTesting()
    #expect(fixture.editor.string == "They're going home.")

    fixture.editor.undoManager?.undo()
    #expect(fixture.editor.string == "Their going home.")
    #expect(fixture.editor.correctionSnapshots.first?.disposition == .restored)

    fixture.editor.undoManager?.redo()
    #expect(fixture.editor.string == "They're going home.")
    #expect(fixture.editor.correctionSnapshots.first?.disposition == .applied)
  }

  @Test("Contextual correction works at an earlier position in a long document")
  func contextualCorrectionAtEarlierCursorPosition() async throws {
    let contextualEngine = ImmediateContextualEngine(
      candidate: ContextualCorrectionCandidate(
        original: "Their",
        replacement: "They're"
      )
    )
    let prefix = String(
      repeating: "Earlier material stays unchanged. ",
      count: 40
    )
    let target = "Their going home"
    let suffix = " Later material also stays unchanged."
    let fixture = EditorFixture(
      initialText: prefix + target + suffix,
      contextualCorrectionEngine: contextualEngine
    )
    defer { fixture.removeLearningStore() }
    fixture.moveCaret(to: prefix.utf16.count + target.utf16.count)

    fixture.type(".")
    await fixture.editor.waitForContextualCorrectionForTesting()

    #expect(
      fixture.editor.string
        == prefix + "They're going home." + suffix
    )
    let correction = try #require(fixture.appliedSnapshots.first)
    #expect(
      correction.annotatedRanges == [
        NSRange(location: prefix.utf16.count, length: "They're".utf16.count)
      ]
    )
  }

  @Test("Comprehensive contextual edits undo and redo as one transaction")
  func comprehensiveEditsAreOneUndoTransaction() async {
    let contextualEngine = ImmediateContextualResultEngine(
      result: ContextualCorrectionResult(
        candidates: [
          ContextualCorrectionCandidate(
            original: "Their",
            replacement: "They're",
            kind: .comprehensiveEdit
          ),
          ContextualCorrectionCandidate(
            original: "its",
            replacement: "it's",
            kind: .comprehensiveEdit
          ),
        ]
      )
    )
    let behaviorSettings = makeBehaviorSettings(
      scope: .comprehensive
    )
    let fixture = EditorFixture(
      contextualCorrectionEngine: contextualEngine,
      behaviorSettings: behaviorSettings
    )
    defer { fixture.removeLearningStore() }

    fixture.type("Their going because its late")
    fixture.editor.undoManager?.removeAllActions()
    fixture.type(".")
    await fixture.editor.waitForContextualCorrectionForTesting()

    #expect(fixture.editor.string == "They're going because it's late.")
    #expect(fixture.appliedSnapshots.count == 2)

    fixture.editor.undoManager?.undo()
    #expect(fixture.editor.string == "Their going because its late.")

    fixture.editor.undoManager?.redo()
    #expect(fixture.editor.string == "They're going because it's late.")
  }

  @Test("An allowed sentence rewrite stays visible and reversible")
  func sentenceRewriteIsVisibleAndReversible() async throws {
    let original = "Due to the fact that we need food, we go to the store now."
    let replacement = "We need food, so we are going to the store now."
    let contextualEngine = ImmediateContextualResultEngine(
      result: ContextualCorrectionResult(
        candidates: [
          ContextualCorrectionCandidate(
            original: original,
            replacement: replacement,
            kind: .sentenceRewrite
          )
        ]
      )
    )
    let behaviorSettings = makeBehaviorSettings(
      scope: .comprehensive,
      allowsSentenceRewrites: true
    )
    let fixture = EditorFixture(
      contextualCorrectionEngine: contextualEngine,
      behaviorSettings: behaviorSettings
    )
    defer { fixture.removeLearningStore() }

    fixture.type("Due to the fact that we need food, we go to the store now")
    fixture.editor.undoManager?.removeAllActions()
    fixture.type(".")
    await fixture.editor.waitForContextualCorrectionForTesting()

    #expect(fixture.editor.string == replacement)
    let snapshot = try #require(fixture.appliedSnapshots.first)
    #expect(
      snapshot.annotatedRanges == [
        NSRange(location: 0, length: replacement.utf16.count)
      ]
    )
    let menu = try #require(
      fixture.editor.correctionMenu(for: snapshot.correction.id)
    )
    #expect(
      menu.items.map(\.title).contains(
        "Apple Rewrite"
      )
    )
    let request = try #require(await contextualEngine.lastRequest)
    #expect(request.scope == .comprehensive)
    #expect(request.allowsSentenceRewrite)

    fixture.editor.undoManager?.undo()
    #expect(fixture.editor.string == original)

    fixture.editor.undoManager?.redo()
    #expect(fixture.editor.string == replacement)

    #expect(
      fixture.editor.changeBack(
        correctionID: snapshot.correction.id
      )
    )
    #expect(fixture.editor.string == original)
  }

  @Test("Pasted sentences never start contextual correction")
  func pastedSentenceDoesNotStartContextualCorrection() async {
    let contextualEngine = CountingContextualEngine()
    let fixture = EditorFixture(
      contextualCorrectionEngine: contextualEngine
    )
    defer { fixture.removeLearningStore() }

    fixture.editor.insertPastedTextForTesting("Their going home.")
    await fixture.editor.waitForContextualCorrectionForTesting()

    #expect(await contextualEngine.requestCount == 0)
    #expect(fixture.editor.string == "Their going home.")
    #expect(fixture.appliedSnapshots.isEmpty)
  }

}

@MainActor
private final class EditorFixture {
  let editor: TypoverTextView
  let engine: TestCorrectionEngine
  let learningStore: CorrectionLearningStore

  private let learningDirectory: URL
  private let scrollView: NSScrollView

  init(
    initialText: String = "",
    contextualCorrectionEngine: any ContextualCorrectionEngine =
      DisabledContextualCorrectionEngine(),
    behaviorSettings: CorrectionBehaviorSettings? = nil
  ) {
    engine = TestCorrectionEngine()
    editor = TypoverTextView(usingTextLayoutManager: true)
    learningDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    learningStore = CorrectionLearningStore(
      fileURL: learningDirectory.appendingPathComponent("learning.json")
    )
    let testBehaviorSettings =
      behaviorSettings
      ?? makeBehaviorSettings(scope: .careful)

    editor.allowsUndo = true
    editor.isRichText = false
    editor.isAutomaticSpellingCorrectionEnabled = false
    editor.isContinuousSpellCheckingEnabled = false
    editor.isHorizontallyResizable = false
    editor.textContainer?.containerSize = NSSize(
      width: 0,
      height: CGFloat.greatestFiniteMagnitude
    )
    editor.textContainer?.widthTracksTextView = true
    editor.configureForTesting(
      correctionEngine: engine,
      contextualCorrectionEngine: contextualCorrectionEngine,
      behaviorSettings: testBehaviorSettings,
      learningStore: learningStore,
      undoManager: UndoManager()
    )
    editor.string = initialText
    editor.setSelectedRange(
      NSRange(location: initialText.utf16.count, length: 0)
    )

    scrollView = NSScrollView(
      frame: NSRect(x: 0, y: 0, width: 600, height: 500)
    )
    scrollView.documentView = editor
    editor.undoManager?.removeAllActions()
  }

  var appliedSnapshots: [TypoverTextView.CorrectionSnapshot] {
    editor.correctionSnapshots.filter { $0.disposition == .applied }
  }

  func moveCaret(to location: Int) {
    editor.setSelectedRange(NSRange(location: location, length: 0))
  }

  func type(_ text: String) {
    for character in text {
      editor.insertText(
        String(character),
        replacementRange: editor.selectedRange()
      )
    }
  }

  func removeLearningStore() {
    try? FileManager.default.removeItem(at: learningDirectory)
  }
}

private actor ImmediateContextualResultEngine: ContextualCorrectionEngine {
  let result: ContextualCorrectionResult?
  private(set) var lastRequest: ContextualCorrectionRequest?

  init(result: ContextualCorrectionResult?) {
    self.result = result
  }

  func availability(
    for _: String?
  ) -> ContextualCorrectionAvailability {
    .available
  }

  func proposal(
    for request: ContextualCorrectionRequest
  ) -> ContextualCorrectionResult? {
    lastRequest = request
    return result
  }
}

private actor ImmediateContextualEngine: ContextualCorrectionEngine {
  let candidate: ContextualCorrectionCandidate?

  init(candidate: ContextualCorrectionCandidate?) {
    self.candidate = candidate
  }

  func availability(
    for _: String?
  ) -> ContextualCorrectionAvailability {
    .available
  }

  func proposal(
    for _: ContextualCorrectionRequest
  ) -> ContextualCorrectionResult? {
    candidate.map {
      ContextualCorrectionResult(candidates: [$0])
    }
  }
}

private actor CountingContextualEngine: ContextualCorrectionEngine {
  private(set) var requestCount = 0

  func availability(
    for _: String?
  ) -> ContextualCorrectionAvailability {
    .available
  }

  func proposal(
    for _: ContextualCorrectionRequest
  ) -> ContextualCorrectionResult? {
    requestCount += 1
    return nil
  }
}

private actor SuspendedContextualEngine: ContextualCorrectionEngine {
  private let candidate: ContextualCorrectionCandidate?
  private var requestWasReceived = false
  private var requestWaiters: [CheckedContinuation<Void, Never>] = []
  private var responseContinuation:
    CheckedContinuation<
      ContextualCorrectionResult?, Never
    >?

  init(candidate: ContextualCorrectionCandidate?) {
    self.candidate = candidate
  }

  func availability(
    for _: String?
  ) -> ContextualCorrectionAvailability {
    .available
  }

  func proposal(
    for _: ContextualCorrectionRequest
  ) async -> ContextualCorrectionResult? {
    requestWasReceived = true
    for waiter in requestWaiters {
      waiter.resume()
    }
    requestWaiters.removeAll()

    return await withCheckedContinuation { continuation in
      responseContinuation = continuation
    }
  }

  func waitUntilRequested() async {
    guard !requestWasReceived else {
      return
    }
    await withCheckedContinuation { continuation in
      requestWaiters.append(continuation)
    }
  }

  func resume() {
    responseContinuation?.resume(
      returning: candidate.map {
        ContextualCorrectionResult(candidates: [$0])
      }
    )
    responseContinuation = nil
  }
}

@MainActor
private func makeBehaviorSettings(
  scope: ContextualCorrectionScope,
  allowsSentenceRewrites: Bool = false
) -> CorrectionBehaviorSettings {
  let defaults = UserDefaults(
    suiteName: "EditorStressTests.\(UUID().uuidString)"
  )!
  let settings = CorrectionBehaviorSettings(defaults: defaults)
  settings.contextualScope = scope
  settings.allowsSentenceRewrites = allowsSentenceRewrites
  return settings
}

@MainActor
private final class TestCorrectionEngine: CorrectionEngine {
  var beforeProposal: ((String) -> Void)?
  private(set) var responses: [CorrectionUserResponse] = []

  private let replacements: [String: (replacement: String, alternatives: [String])] = [
    "recieve": ("receive", []),
    "speling": ("spelling", []),
    "teh": ("the", ["ten"]),
    "wrod": ("word", []),
  ]

  func proposal(for word: String) -> CorrectionProposal? {
    beforeProposal?(word)
    guard let candidate = replacements[word] else {
      return nil
    }
    return CorrectionProposal(
      correction: Correction(
        original: word,
        replacement: candidate.replacement
      ),
      alternatives: candidate.alternatives,
      source: .demo,
      language: "en_US",
      lookupDuration: .zero
    )
  }

  func record(
    _ response: CorrectionUserResponse,
    for _: CorrectionProposal
  ) {
    responses.append(response)
  }
}
