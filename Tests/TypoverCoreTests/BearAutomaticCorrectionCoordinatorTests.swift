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
        == .completionBoundary(" ")
    )
    #expect(
      BearTypingInput.intent(
        characters: "?",
        charactersIgnoringModifiers: "/",
        modifiers: [.shift]
      ) == .completionBoundary("?")
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
    #expect(fixture.coordinator.diagnostics.snapshot.boundaryInputs == 1)
    #expect(fixture.coordinator.diagnostics.snapshot.valueChanges == 1)
    #expect(fixture.coordinator.diagnostics.snapshot.correctionsApplied == 1)
    #expect(
      fixture.coordinator.diagnostics.snapshot
        .correctionToAnnotationSampleCount == 1
    )

    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.reader.readCount >= 4
      }
    )
    #expect(fixture.coordinator.diagnostics.snapshot.valueChanges == 1)
    #expect(fixture.coordinator.diagnostics.snapshot.safeSkips == 0)
    #expect(fixture.coordinator.diagnostics.snapshot.lastOutcome == .applied)
  }

  @Test("Punctuation and newline keys authorize only their exact transition")
  func correctsPunctuationBoundaries() async throws {
    for boundary in [".", "?", "\n"] {
      let fixture = try Fixture()
      fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
      fixture.coordinator.setEnabled(true)

      fixture.reader.result = .ready(
        snapshot(text: "teh\(boundary)", caret: 4)
      )
      fixture.inputMonitor.emitBoundary(boundary)
      fixture.monitor.emit(.valueChanged)

      #expect(
        await waitUntil {
          fixture.applicator.requests.count == 1
        }
      )
      #expect(
        fixture.applicator.requests.first?.range
          == AccessibilityTextRange(location: 0, length: 3)
      )
    }
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
    #expect(fixture.coordinator.diagnostics.snapshot.refusals == 1)
  }

  @Test("Disabling stops observation and re-enabling starts fresh")
  func disablesAndReenablesObservation() throws {
    let fixture = try Fixture()
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)
    let monitorStopsAfterEnable = fixture.monitor.stopCount
    let inputStopsAfterEnable = fixture.inputMonitor.stopCount

    fixture.coordinator.setEnabled(false)

    #expect(fixture.coordinator.status == .disabled)
    #expect(fixture.monitor.stopCount == monitorStopsAfterEnable + 1)
    #expect(fixture.inputMonitor.stopCount == inputStopsAfterEnable + 1)
    #expect(fixture.tracker.stopCount == 1)

    fixture.coordinator.setEnabled(true)

    #expect(fixture.coordinator.status == .observing)
    #expect(fixture.monitor.startCount == 2)
    #expect(fixture.inputMonitor.startCount == 2)
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

  @Test("The next ordinary key does not erase a pending boundary")
  func preservesBoundaryWhileRapidTypingContinues() async throws {
    let fixture = try Fixture()
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.inputMonitor.emitOther()
    fixture.monitor.emit(.valueChanged)

    #expect(
      await waitUntil {
        fixture.applicator.requests.count == 1
      }
    )
    #expect(
      fixture.applicator.requests.first?.range
        == AccessibilityTextRange(location: 0, length: 3)
    )
  }

  @Test("A coalesced next character still fails closed")
  func refusesBoundaryCoalescedWithRapidTyping() async throws {
    let fixture = try Fixture()
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .ready(snapshot(text: "teh t", caret: 5))
    fixture.inputMonitor.emitBoundary()
    fixture.inputMonitor.emitOther()
    fixture.monitor.emit(.valueChanged)

    #expect(
      await waitUntil {
        fixture.coordinator.diagnostics.snapshot.safeSkips == 1
      }
    )
    #expect(fixture.applicator.requests.isEmpty)
    #expect(
      fixture.coordinator.diagnostics.snapshot.lastOutcome == .contextChanged
    )
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
    #expect(fixture.coordinator.diagnostics.snapshot.safeSkips == 1)
    #expect(
      fixture.coordinator.diagnostics.snapshot.lastOutcome == .contextChanged
    )
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
    #expect(fixture.coordinator.diagnostics.snapshot.safeSkips == 1)
    #expect(
      fixture.coordinator.diagnostics.snapshot.lastOutcome
        == .unarmedValueChange
    )
  }

  @Test("A stale completion key cannot authorize a later value change")
  func ignoresStaleBoundaryInput() async throws {
    let fixture = try Fixture(maximumBoundaryPairingDelay: .zero)
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
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
    #expect(fixture.coordinator.diagnostics.snapshot.safeSkips == 1)
    #expect(
      fixture.coordinator.diagnostics.snapshot.lastOutcome
        == .staleBoundaryInput
    )
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

  @Test("Collapsing a selection establishes a fresh typing baseline")
  func resumesAfterSelection() async throws {
    let fixture = try Fixture()
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .selectionActive
    fixture.monitor.emit(.selectionChanged)
    #expect(
      await waitUntil {
        fixture.coordinator.status == .pausedForSelection
      }
    )

    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.monitor.emit(.selectionChanged)
    #expect(
      await waitUntil {
        fixture.coordinator.status == .observing
      }
    )

    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.applicator.requests.count == 1
      }
    )
  }

  @Test("Changing focused editors disarms an in-flight boundary")
  func focusChangeDisarmsBoundary() async throws {
    let fixture = try Fixture()
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.focusedElementChanged)
    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    #expect(
      await waitUntil {
        fixture.monitor.startCount == 2
      }
    )

    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.reader.readCount >= 3
      }
    )

    #expect(fixture.applicator.requests.isEmpty)
    #expect(
      fixture.coordinator.diagnostics.snapshot.lastOutcome
        == .unarmedValueChange
    )
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
    #expect(
      fixture.coordinator.diagnostics.snapshot.interactionLatencySampleCount
        == 1
    )
    #expect(
      fixture.coordinator.diagnostics.snapshot
        .medianInteractionLatencyMilliseconds == 42
    )
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

  @Test("Input monitoring failure is explicit and recovers on activation")
  func recoversInputMonitoring() async throws {
    let fixture = try Fixture()
    fixture.inputMonitor.startResults = [false, true]
    fixture.reader.result = .ready(snapshot(text: "", caret: 0))

    fixture.coordinator.setEnabled(true)

    #expect(fixture.coordinator.status == .inputMonitoringUnavailable)
    #expect(fixture.monitor.startCount == 1)
    #expect(fixture.inputMonitor.startCount == 1)
    #expect(fixture.coordinator.diagnostics.snapshot.refusals == 1)
    #expect(
      fixture.coordinator.diagnostics.snapshot.lastOutcome
        == .inputMonitoringUnavailable
    )

    fixture.workspaceNotificationCenter.post(
      name: NSWorkspace.didActivateApplicationNotification,
      object: nil
    )

    #expect(
      await waitUntil {
        fixture.inputMonitor.startCount == 2
          && fixture.coordinator.status == .observing
      }
    )
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
        to: current,
        expectedBoundary: " "
      ) == nil
    )
  }

  @Test("The inserted boundary must match the observed key")
  func rejectsMismatchedBoundary() {
    let previous = snapshot(text: "teh", caret: 3)
    let current = snapshot(text: "teh.", caret: 4)

    #expect(
      BearTypingTransition.completedWord(
        from: previous,
        to: current,
        expectedBoundary: " "
      ) == nil
    )
    #expect(
      BearTypingTransition.completedWord(
        from: previous,
        to: current,
        expectedBoundary: "."
      ) != nil
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
  let workspaceNotificationCenter = NotificationCenter()
  private let directory: URL

  init(
    environmentSupport: BearEnvironmentSupport = .supported,
    maximumBoundaryPairingDelay: Duration = .seconds(10)
  ) throws {
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
      maximumBoundaryPairingDelay: maximumBoundaryPairingDelay,
      observationRestartDelay: .milliseconds(1),
      workspaceNotificationCenter: workspaceNotificationCenter
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
  private(set) var stopCount = 0
  var startResults: [Bool] = []

  func start(
    handler: @escaping @MainActor @Sendable (BearTypingInputIntent) -> Void
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
    stopCount += 1
    handler = nil
  }

  func emitBoundary(_ character: String = " ") {
    handler?(.completionBoundary(character))
  }

  func emitUndoOrRedo() {
    handler?(.undoOrRedo)
  }

  func emitOther() {
    handler?(.other)
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
  private(set) var stopCount = 0
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
    stopCount += 1
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
  private(set) var stopCount = 0
  private var onResolution:
    (
      @MainActor @Sendable (BearAnnotationResolution) -> Void
    )?
  private var onInteractionLatency:
    (@MainActor @Sendable (Duration) -> Void)?

  func trackWithResolution(
    _ application: BearCorrectionApplication,
    alternatives _: [String],
    onInteractionLatency: (
      @MainActor @Sendable (Duration) -> Void
    )?,
    onResolution: (
      @MainActor @Sendable (BearAnnotationResolution) -> Void
    )?,
    onFinished _: (@MainActor @Sendable () -> Void)?
  ) {
    applications.append(application)
    self.onInteractionLatency = onInteractionLatency
    self.onResolution = onResolution
  }

  func stop() {
    stopCount += 1
    applications = []
    onInteractionLatency = nil
    onResolution = nil
  }

  func resolve(
    _ resolution: BearAnnotationResolution,
    interactionLatency: Duration = .milliseconds(42)
  ) {
    onInteractionLatency?(interactionLatency)
    onResolution?(resolution)
  }
}
