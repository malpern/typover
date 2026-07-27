import AppKit
import Foundation
import Testing
import TypoverAccessibility
import TypoverBearAdapter
import TypoverCore
import TypoverOverlay

@testable import TypoverApp

@MainActor
@Suite("Bear automatic correction", .serialized)
struct BearAutomaticCorrectionCoordinatorTests {
  @Test("Only word-completion characters arm automatic correction")
  func recognizesBoundaryInput() {
    #expect(BearTypingInput.isCompletionBoundary(" "))
    #expect(BearTypingInput.isCompletionBoundary("\n"))
    #expect(BearTypingInput.isCompletionBoundary("."))
    #expect(!BearTypingInput.isCompletionBoundary("x"))
    #expect(!BearTypingInput.isCompletionBoundary(""))
    #expect(
      BearTypingInput.intent(characters: " ", modifiers: [])
        == .completionBoundary
    )
    #expect(
      BearTypingInput.intent(
        characters: "?",
        charactersIgnoringModifiers: "/",
        modifiers: [.shift]
      ) == .completionBoundary
    )
    #expect(
      BearTypingInput.intent(
        characters: "Ω",
        charactersIgnoringModifiers: "z",
        modifiers: [.command]
      ) == .undoOrRedo
    )
    #expect(
      BearTypingInput.intent(
        characters: "Z",
        modifiers: [.command, .shift]
      ) == .undoOrRedo
    )
    #expect(
      BearTypingInput.intent(characters: " ", modifiers: [.option])
        == .other
    )
  }

  @Test("A verified typed boundary corrects the completed word")
  func correctsTypedBoundary() async throws {
    let fixture = try Fixture()
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)
    fixture.monitor.emit(.selectionChanged)
    #expect(
      await waitUntil {
        !fixture.applicator.requests.isEmpty
      }
    )

    let request = try #require(fixture.applicator.requests.first)
    #expect(request.original == "teh")
    #expect(request.replacement == "the")
    #expect(request.range == AccessibilityTextRange(location: 0, length: 3))
    #expect(fixture.tracker.applications.count == 1)
    #expect(fixture.store.statistics().correctionsApplied == 1)
  }

  @Test("Only the validated Bear and macOS versions are supported")
  func validatesSupportedEnvironment() {
    let policy = BearSupportPolicy.current
    #expect(
      policy.evaluate(
        bearVersion: "2.8.1",
        operatingSystemVersion: OperatingSystemVersion(
          majorVersion: 27,
          minorVersion: 0,
          patchVersion: 1
        )
      ) == .supported
    )
    #expect(
      policy.evaluate(
        bearVersion: "2.8.2",
        operatingSystemVersion: OperatingSystemVersion(
          majorVersion: 27,
          minorVersion: 0,
          patchVersion: 0
        )
      ) == .unsupportedBearVersion(installed: "2.8.2")
    )
    #expect(
      policy.evaluate(
        bearVersion: "2.8.1",
        operatingSystemVersion: OperatingSystemVersion(
          majorVersion: 27,
          minorVersion: 1,
          patchVersion: 0
        )
      ) == .unsupportedMacOSVersion(installed: "27.1.0")
    )
  }

  @Test("Unsupported environments never attach mutation observers")
  func blocksUnsupportedEnvironment() throws {
    let fixture = try Fixture(
      environmentSupport: .unsupportedBearVersion(installed: "2.8.2")
    )
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))

    fixture.coordinator.setEnabled(true)

    #expect(
      fixture.coordinator.status
        == .unsupportedBearVersion(installed: "2.8.2")
    )
    #expect(fixture.monitor.startCount == 0)
    #expect(fixture.inputMonitor.startCount == 0)
  }

  @Test("Consecutive typed words create consecutive annotations")
  func correctsConsecutiveWords() async throws {
    let fixture = try Fixture()
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.tracker.applications.count == 1
      }
    )

    fixture.reader.result = .ready(snapshot(text: "teh teh", caret: 7))
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.reader.readCount >= 4
      }
    )
    fixture.reader.result = .ready(snapshot(text: "teh teh ", caret: 8))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)

    #expect(
      await waitUntil {
        fixture.tracker.applications.count == 2
      }
    )
    #expect(fixture.applicator.requests.map(\.range) == [
      AccessibilityTextRange(location: 0, length: 3),
      AccessibilityTextRange(location: 4, length: 3),
    ])
  }

  @Test("A pasted or coalesced insertion is ignored")
  func ignoresBulkInsertion() async throws {
    let fixture = try Fixture()
    fixture.reader.result = .ready(snapshot(text: "", caret: 0))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.reader.readCount >= 2
      }
    )

    #expect(fixture.applicator.requests.isEmpty)
    #expect(fixture.tracker.applications.isEmpty)
  }

  @Test("A boundary inserted without a matching keystroke is ignored")
  func ignoresNonKeyboardBoundary() async throws {
    let fixture = try Fixture()
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.reader.readCount >= 2
      }
    )

    #expect(fixture.applicator.requests.isEmpty)
  }

  @Test("Undo or Redo clears an armed completion boundary")
  func undoRedoDisarmsBoundary() async throws {
    let fixture = try Fixture()
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.inputMonitor.emitUndoOrRedo()
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.reader.readCount >= 2
      }
    )

    #expect(fixture.applicator.requests.isEmpty)
    #expect(fixture.tracker.applications.isEmpty)
  }

  @Test("A composition commit that changes text is ignored")
  func ignoresCompositionCommit() async throws {
    let fixture = try Fixture()
    fixture.reader.result = .ready(snapshot(text: "te", caret: 2))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.reader.readCount >= 2
      }
    )

    #expect(fixture.applicator.requests.isEmpty)
    #expect(fixture.tracker.applications.isEmpty)
  }

  @Test("A selection pauses observation without applying a correction")
  func pausesForSelection() async throws {
    let fixture = try Fixture()
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .selectionActive
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.coordinator.status == .pausedForSelection
      }
    )

    #expect(fixture.coordinator.status == .pausedForSelection)
    #expect(fixture.applicator.requests.isEmpty)
  }

  @Test("A learned Change Back suppresses the next matching typo")
  func learnsChangeBack() async throws {
    let fixture = try Fixture()
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        !fixture.tracker.applications.isEmpty
      }
    )
    fixture.tracker.resolve(.changedBack)

    #expect(
      fixture.store.preference(for: "teh", language: "en_US")
        == .suppressed
    )
    #expect(fixture.engine.responses == [.reverted])
  }

  @Test("Observation retries while Bear's focused editor is attaching")
  func retriesObserverAttachment() async throws {
    let fixture = try Fixture()
    fixture.monitor.startResults = [false, true]
    fixture.reader.result = .focusedEditorUnavailable

    fixture.coordinator.setEnabled(true)
    fixture.reader.result = .ready(snapshot(text: "", caret: 0))

    #expect(
      await waitUntil {
        fixture.monitor.startCount == 2
          && fixture.inputMonitor.startCount == 1
      }
    )
    #expect(fixture.coordinator.status == .observing)
  }

  @Test("Typing transition requires unchanged bounded context")
  func rejectsChangedContext() {
    let previous = snapshot(
      text: "before teh",
      caret: 10,
      trailing: " after"
    )
    let current = snapshot(
      text: "beforz teh ",
      caret: 11,
      documentLength: 17,
      trailing: " after"
    )

    #expect(
      BearTypingTransition.completedWord(
        from: previous,
        to: current
      ) == nil
    )
  }

  private func snapshot(
    text: String,
    caret: Int,
    documentLength: Int? = nil,
    trailing: String = ""
  ) -> BearTypingContextSnapshot {
    BearTypingContextSnapshot(
      leadingRange: AccessibilityTextRange(
        location: 0,
        length: text.utf16.count
      ),
      leadingText: text,
      trailingText: trailing,
      caretLocation: caret,
      documentLength: documentLength ?? caret + trailing.utf16.count
    )
  }

  private func waitUntil(
    timeout: Duration = .seconds(10),
    condition: () -> Bool
  ) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
      if condition() {
        return true
      }
      try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
  }
}

@MainActor
private final class Fixture {
  let reader = TestTypingContextReader()
  let monitor = TestInvalidationMonitor()
  let engine = TestCorrectionEngine()
  let applicator = TestCorrectionApplicator()
  let tracker = TestAnnotationTracker()
  let inputMonitor = TestTypingInputMonitor()
  let store: CorrectionLearningStore
  let coordinator: BearAutomaticCorrectionCoordinator
  private let directory: URL

  init(environmentSupport: BearEnvironmentSupport = .supported) throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    store = CorrectionLearningStore(
      fileURL: directory.appendingPathComponent("learning.json")
    )
    coordinator = BearAutomaticCorrectionCoordinator(
      contextReader: reader,
      invalidationMonitor: monitor,
      correctionEngine: engine,
      correctionApplicator: applicator,
      annotationTracker: tracker,
      typingInputMonitor: inputMonitor,
      environmentChecker: TestBearEnvironmentChecker(
        result: environmentSupport
      ),
      learningStore: store,
      frontmostBundleIdentifier: {
        BearAccessibilityProbe.bearBundleIdentifier
      },
      settleDelay: .milliseconds(1),
      observationRestartDelay: .milliseconds(1),
      workspaceNotificationCenter: NotificationCenter()
    )
  }

  deinit {
    try? FileManager.default.removeItem(at: directory)
  }
}

private struct TestBearEnvironmentChecker: BearEnvironmentChecking {
  let result: BearEnvironmentSupport

  func support() -> BearEnvironmentSupport {
    result
  }
}

@MainActor
private final class TestTypingInputMonitor: BearTypingInputMonitoring {
  private var handler:
    (@MainActor @Sendable (BearTypingInputIntent) -> Void)?
  private(set) var startCount = 0

  func start(
    handler: @escaping @MainActor @Sendable (BearTypingInputIntent) -> Void
  ) -> Bool {
    startCount += 1
    self.handler = handler
    return true
  }

  func stop() {
    handler = nil
  }

  func emitBoundary() {
    handler?(.completionBoundary)
  }

  func emitUndoOrRedo() {
    handler?(.undoOrRedo)
  }
}

@MainActor
private final class TestTypingContextReader: BearTypingContextReading {
  var result: BearTypingContextReadResult = .focusedEditorUnavailable
  private(set) var readCount = 0

  func read() -> BearTypingContextReadResult {
    readCount += 1
    return result
  }
}

@MainActor
private final class TestInvalidationMonitor:
  BearAccessibilityInvalidationObserving
{
  var startResults: [Bool] = []
  private(set) var startCount = 0
  private var handler:
    (
      @MainActor @Sendable (
        BearAccessibilityInvalidationEvent
      ) -> Void
    )?

  func start(
    handler:
      @escaping @MainActor @Sendable (
        BearAccessibilityInvalidationEvent
      ) -> Void
  ) -> Bool {
    startCount += 1
    if !startResults.isEmpty, !startResults.removeFirst() {
      self.handler = nil
      return false
    }
    self.handler = handler
    return true
  }

  func stop() {
    handler = nil
  }

  func emit(_ event: BearAccessibilityInvalidationEvent) {
    handler?(event)
  }
}

@MainActor
private final class TestCorrectionEngine: CorrectionEngine {
  var responses: [CorrectionUserResponse] = []

  func proposal(for word: String) -> CorrectionProposal? {
    guard word == "teh" else {
      return nil
    }
    return CorrectionProposal(
      correction: Correction(original: "teh", replacement: "the"),
      alternatives: ["ten"],
      source: .appleSpelling,
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

private final class TestCorrectionApplicator:
  BearCorrectionApplying, @unchecked Sendable
{
  struct Request: Equatable {
    let original: String
    let replacement: String
    let range: AccessibilityTextRange
  }

  private let lock = NSLock()
  private var storedRequests: [Request] = []

  var requests: [Request] {
    lock.withLock { storedRequests }
  }

  func apply(
    original: String,
    replacement: String,
    at targetRange: AccessibilityTextRange
  ) -> BearCorrectionApplication {
    lock.withLock {
      storedRequests.append(
        Request(
          original: original,
          replacement: replacement,
          range: targetRange
        )
      )
    }
    let replacementRange = AccessibilityTextRange(
      location: targetRange.location,
      length: replacement.utf16.count
    )
    let correction = Correction(
      original: original,
      replacement: replacement
    )
    return BearCorrectionApplication(
      report: BearExactRangeReplacementReport(
        status: .applied,
        writeOccurred: true,
        targetRange: targetRange,
        replacementRange: replacementRange,
        selectionBefore: AccessibilityTextRange(
          location: targetRange.location + targetRange.length + 1,
          length: 0
        ),
        selectionAfter: AccessibilityTextRange(
          location: targetRange.location + replacement.utf16.count + 1,
          length: 0
        ),
        surroundingContextVerified: true,
        caretRestored: true
      ),
      correction: correction,
      correctionRecord: CorrectionRecord(correction: correction),
      correctionAnchor: BearCorrectionAnchor(
        correctionRange: replacementRange,
        documentLength: replacement.utf16.count + 1,
        leadingContext: "",
        trailingContext: " "
      )
    )
  }
}

@MainActor
private final class TestAnnotationTracker: BearAnnotationTracking {
  var applications: [BearCorrectionApplication] = []
  private var onResolution:
    (
      @MainActor @Sendable (BearAnnotationResolution) -> Void
    )?

  func trackWithResolution(
    _ application: BearCorrectionApplication,
    alternatives _: [String],
    onResolution: (
      @MainActor @Sendable (BearAnnotationResolution) -> Void
    )?,
    onFinished _: (@MainActor @Sendable () -> Void)?
  ) {
    applications.append(application)
    self.onResolution = onResolution
  }

  func stop() {
    applications = []
    onResolution = nil
  }

  func resolve(_ resolution: BearAnnotationResolution) {
    onResolution?(resolution)
  }
}
