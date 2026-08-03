import AppKit
import OSLog
import Observation
import TypoverAccessibility
import TypoverAppleSpell
import TypoverBearAdapter
import TypoverCore
import TypoverOverlay

enum BearAutomaticCorrectionStatus: Equatable {
  case disabled
  case waitingForBear
  case observing
  case pausedForSelection
  case bearVersionUnavailable
  case unsupportedBearVersion(installed: String)
  case unsupportedMacOSVersion(installed: String)
  case accessibilityPermissionRequired
  case editorUnavailable
  case inputMonitoringUnavailable
  case pausedAfterIndeterminateWrite
}

protocol BearCorrectionApplying: Sendable {
  func apply(
    original: String,
    replacement: String,
    at targetRange: AccessibilityTextRange
  ) -> BearCorrectionApplication
}

extension BearCorrectionAdapter: BearCorrectionApplying {}

#if DEBUG
  enum BearAutomaticCorrectionDebugFaults {
    static let environmentKey = "TYPOVER_DEBUG_BEAR_FAULT"
    static let unreconciledPostWriteValue = "post-write-unreconciled"

    static func correctionApplicator(
      base: any BearCorrectionApplying,
      environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> any BearCorrectionApplying {
      guard environment[environmentKey] == unreconciledPostWriteValue else {
        return base
      }
      return DebugUnreconciledPostWriteApplicator(base: base)
    }
  }

  private final class DebugUnreconciledPostWriteApplicator:
    BearCorrectionApplying, @unchecked Sendable
  {
    private let base: any BearCorrectionApplying
    private let lock = NSLock()
    private var isArmed = true
    private let logger = Logger(
      subsystem: "com.malpern.typover",
      category: "BearAutomaticCorrection"
    )

    init(base: any BearCorrectionApplying) {
      self.base = base
    }

    func apply(
      original: String,
      replacement: String,
      at targetRange: AccessibilityTextRange
    ) -> BearCorrectionApplication {
      let application = base.apply(
        original: original,
        replacement: replacement,
        at: targetRange
      )
      guard application.report.writeOccurred,
        lock.withLock({
          guard isArmed else { return false }
          isArmed = false
          return true
        })
      else {
        return application
      }
      logger.fault(
        "Debug fault injected an unreconciled post-write result"
      )
      return BearCorrectionApplication(
        report: BearExactRangeReplacementReport(
          status: .verificationFailed,
          writeOccurred: true,
          targetRange: application.report.targetRange,
          replacementRange: application.report.replacementRange,
          selectionBefore: application.report.selectionBefore,
          selectionAfter: application.report.selectionAfter,
          surroundingContextVerified: false,
          caretRestored: application.report.caretRestored
        ),
        correction: application.correction,
        correctionRecord: nil,
        correctionAnchor: nil
      )
    }
  }
#endif

@MainActor
protocol BearAnnotationTracking: AnyObject {
  func handleInvalidation(_ event: BearAccessibilityInvalidationEvent)

  func recordVerifiedEdit(_ edit: BearAnnotationVerifiedEdit)

  func trackWithResolution(
    _ application: BearCorrectionApplication,
    alternatives: [String],
    userRecency: Date?,
    onFirstVisible: (@MainActor @Sendable () -> Void)?,
    onInteractionLatency: (
      @MainActor @Sendable (Duration) -> Void
    )?,
    onResolution: (
      @MainActor @Sendable (BearAnnotationResolution) -> Void
    )?,
    onFinished: (@MainActor @Sendable () -> Void)?
  )

  func stop()
}

extension BearAnnotationOverlayController: BearAnnotationTracking {
  func trackWithResolution(
    _ application: BearCorrectionApplication,
    alternatives: [String],
    userRecency _: Date?,
    onFirstVisible: (@MainActor @Sendable () -> Void)?,
    onInteractionLatency: (
      @MainActor @Sendable (Duration) -> Void
    )?,
    onResolution: (
      @MainActor @Sendable (BearAnnotationResolution) -> Void
    )?,
    onFinished: (@MainActor @Sendable () -> Void)?
  ) {
    trackWithResolution(
      application,
      alternatives: alternatives,
      onFirstVisible: onFirstVisible,
      onInteractionLatency: onInteractionLatency,
      onResolution: onResolution,
      onFinished: onFinished
    )
  }

  func handleInvalidation(_ event: BearAccessibilityInvalidationEvent) {
    handleSharedInvalidation(event)
  }

  func recordVerifiedEdit(_ edit: BearAnnotationVerifiedEdit) {
    Task { @MainActor [weak self] in
      await self?.applyVerifiedEdit(edit)
    }
  }
}
extension BearAnnotationOverlayCollectionController: BearAnnotationTracking {}

@MainActor
protocol BearTypingInputMonitoring: AnyObject {
  @discardableResult
  func start(
    handler: @escaping @MainActor @Sendable (BearTypingInputObservation) -> Void
  ) -> Bool
  func stop()
}

@MainActor
final class AppKitBearTypingInputMonitor: BearTypingInputMonitoring {
  private var eventMonitor: Any?

  func start(
    handler: @escaping @MainActor @Sendable (BearTypingInputObservation) -> Void
  ) -> Bool {
    stop()
    eventMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: .keyDown
    ) { event in
      let modifiers = event.modifierFlags.intersection(
        .deviceIndependentFlagsMask
      )
      let intent = BearTypingInput.intent(
        characters: event.characters,
        charactersIgnoringModifiers: event.charactersIgnoringModifiers,
        modifiers: modifiers
      )
      // Capture time in the event callback, before the MainActor hop. Under
      // load, actor scheduling delay must not make a fresh physical key look
      // stale or distort correction latency diagnostics.
      let observation = BearTypingInputObservation(
        intent: intent,
        observedAt: ContinuousClock().now
      )
      Task { @MainActor in
        handler(observation)
      }
    }
    return eventMonitor != nil
  }

  func stop() {
    if let eventMonitor {
      NSEvent.removeMonitor(eventMonitor)
      self.eventMonitor = nil
    }
  }
}

private enum SystemPhysicalInputActivity {
  static func idleDuration() -> Duration? {
    let seconds = CGEventSource.secondsSinceLastEventType(
      .combinedSessionState,
      eventType: .keyDown
    )
    guard seconds.isFinite, seconds >= 0 else {
      return nil
    }
    return .seconds(seconds)
  }
}

struct BearTypingInputObservation: Equatable, Sendable {
  let intent: BearTypingInputIntent
  let observedAt: ContinuousClock.Instant
}

enum BearTypingInputIntent: Equatable {
  case completionBoundary(String)
  case undoOrRedo
  case other
}

enum BearTypingInput {
  private static let punctuationBoundaries = CharacterSet(
    charactersIn: ".,!?;:…"
  )

  static func isCompletionBoundary(_ text: String) -> Bool {
    guard !text.isEmpty else {
      return false
    }
    return text.unicodeScalars.allSatisfy { scalar in
      CharacterSet.whitespacesAndNewlines.contains(scalar)
        || punctuationBoundaries.contains(scalar)
    }
  }

  static func intent(
    characters: String?,
    charactersIgnoringModifiers: String? = nil,
    modifiers: NSEvent.ModifierFlags
  ) -> BearTypingInputIntent {
    let normalizedCharacters =
      (charactersIgnoringModifiers ?? characters)?.lowercased()
    if modifiers.contains(.command),
      !modifiers.contains(.control),
      !modifiers.contains(.option),
      normalizedCharacters == "z"
    {
      return .undoOrRedo
    }

    let disallowedModifiers: NSEvent.ModifierFlags = [
      .command,
      .control,
      .option,
    ]
    guard
      modifiers.isDisjoint(with: disallowedModifiers),
      characters.map(isCompletionBoundary) == true
    else {
      return .other
    }
    return .completionBoundary(characters ?? "")
  }
}

enum BearAutomaticCorrectionPrivateDiagnostics {
  static let defaultsKey =
    BearPrivateDiagnosticsConfiguration.enabledDefaultsKey
}

struct VerifiedBearTypingCompletion: Equatable {
  let word: CompletedWord
  let targetRange: AccessibilityTextRange
}

enum BearTypingTransition {
  static func completedWord(
    from previous: BearTypingContextSnapshot,
    to current: BearTypingContextSnapshot,
    expectedBoundary: String
  ) -> VerifiedBearTypingCompletion? {
    guard
      expectedBoundary.utf16.count == 1,
      current.documentLength == previous.documentLength + 1,
      current.caretLocation == previous.caretLocation + 1,
      current.leadingRange.location + current.leadingRange.length
        == current.caretLocation,
      current.leadingText.utf16.count == current.leadingRange.length,
      current.leadingRange.length > 0,
      insertedBoundary(in: current) == expectedBoundary,
      boundedLeadingTextMatches(previous: previous, current: current),
      boundedTrailingTextMatches(previous: previous, current: current),
      let word = CompletedWordDetector.immediatelyBeforeCaret(
        in: current.leadingText,
        caretUTF16Offset: current.leadingText.utf16.count
      )
    else {
      return nil
    }

    return VerifiedBearTypingCompletion(
      word: word,
      targetRange: AccessibilityTextRange(
        location: current.leadingRange.location + word.range.location,
        length: word.range.length
      )
    )
  }

  private static func insertedBoundary(
    in snapshot: BearTypingContextSnapshot
  ) -> String? {
    guard snapshot.leadingText.utf16.count > 0 else {
      return nil
    }
    return utf16Substring(
      snapshot.leadingText,
      range: NSRange(
        location: snapshot.leadingText.utf16.count - 1,
        length: 1
      )
    )
  }

  private static func boundedLeadingTextMatches(
    previous: BearTypingContextSnapshot,
    current: BearTypingContextSnapshot
  ) -> Bool {
    let previousEnd = previous.caretLocation
    let currentTextBeforeInsertion = NSRange(
      location: current.leadingRange.location,
      length: current.leadingRange.length - 1
    )
    let overlapStart = max(
      previous.leadingRange.location,
      currentTextBeforeInsertion.location
    )
    let overlapLength = previousEnd - overlapStart
    guard overlapLength >= 0 else {
      return false
    }

    return utf16Substring(
      previous.leadingText,
      range: NSRange(
        location: overlapStart - previous.leadingRange.location,
        length: overlapLength
      )
    )
      == utf16Substring(
        current.leadingText,
        range: NSRange(
          location: overlapStart - current.leadingRange.location,
          length: overlapLength
        )
      )
  }

  private static func boundedTrailingTextMatches(
    previous: BearTypingContextSnapshot,
    current: BearTypingContextSnapshot
  ) -> Bool {
    let overlapLength = min(
      previous.trailingText.utf16.count,
      current.trailingText.utf16.count
    )
    return utf16Substring(
      previous.trailingText,
      range: NSRange(location: 0, length: overlapLength)
    )
      == utf16Substring(
        current.trailingText,
        range: NSRange(location: 0, length: overlapLength)
      )
  }

  private static func utf16Substring(
    _ text: String,
    range: NSRange
  ) -> String {
    (text as NSString).substring(with: range)
  }
}

enum BearDeferredTypingTransition {
  /// A deferred correction remains authorized only while the writer extends
  /// the same caret position. Text before the original caret and the bounded
  /// trailing context must remain unchanged; document growth must equal caret
  /// movement. This permits ordinary continued typing but rejects navigation,
  /// replacement, deletion, and adjacent edits before an AX write begins.
  static func preservesAppendOnlyContext(
    from authorized: BearTypingContextSnapshot,
    to current: BearTypingContextSnapshot
  ) -> Bool {
    let documentGrowth = current.documentLength - authorized.documentLength
    let caretMovement = current.caretLocation - authorized.caretLocation
    guard
      documentGrowth >= 0,
      caretMovement == documentGrowth,
      authorized.leadingText.utf16.count == authorized.leadingRange.length,
      current.leadingText.utf16.count == current.leadingRange.length,
      authorized.trailingText == current.trailingText
    else {
      return false
    }

    let overlapStart = max(
      authorized.leadingRange.location,
      current.leadingRange.location
    )
    let overlapEnd = authorized.caretLocation
    let overlapLength = overlapEnd - overlapStart
    guard overlapLength > 0 else {
      return false
    }

    return utf16Substring(
      authorized.leadingText,
      range: NSRange(
        location: overlapStart - authorized.leadingRange.location,
        length: overlapLength
      )
    )
      == utf16Substring(
        current.leadingText,
        range: NSRange(
          location: overlapStart - current.leadingRange.location,
          length: overlapLength
        )
      )
  }

  private static func utf16Substring(
    _ text: String,
    range: NSRange
  ) -> String {
    (text as NSString).substring(with: range)
  }
}

@MainActor
@Observable
final class BearAutomaticCorrectionCoordinator {
  private struct DeferredCorrection {
    let proposal: CorrectionProposal
    let targetRange: AccessibilityTextRange
    let boundaryObservedAt: ContinuousClock.Instant?
    let authorizedContext: BearTypingContextSnapshot
  }

  private(set) var status: BearAutomaticCorrectionStatus = .disabled
  let diagnostics: BearAutomaticCorrectionDiagnostics

  private let contextReader: any BearTypingContextReading
  private let invalidationMonitor: any BearAccessibilityInvalidationObserving
  private let correctionEngine: any CorrectionEngine
  private let correctionApplicator: any BearCorrectionApplying
  private let annotationTracker: any BearAnnotationTracking
  private let typingInputMonitor: any BearTypingInputMonitoring
  private let environmentChecker: any BearEnvironmentChecking
  private let learningStore: CorrectionLearningStore
  private let frontmostBundleIdentifier: @MainActor @Sendable () -> String?
  private let settleDelay: Duration
  private let maximumBoundaryPairingDelay: Duration
  private let deferredCorrectionIdleDelay: Duration
  private let physicalInputIdleDuration: @MainActor @Sendable () -> Duration?
  private let observationRestartDelay: Duration
  private let workspaceNotificationCenter: NotificationCenter
  private let privateDiagnosticsEnabled: @MainActor @Sendable () -> Bool
  private let clock = ContinuousClock()
  private let logger = Logger(
    subsystem: "com.malpern.typover",
    category: "BearAutomaticCorrection"
  )

  private var isEnabled = false
  private var lastSnapshot: BearTypingContextSnapshot?
  private var pendingValueChange = false
  private var pendingInputIntent: BearTypingInputIntent = .other
  private var pendingBoundaryObservedAt: ContinuousClock.Instant?
  private var scheduledBoundaryObservedAt: ContinuousClock.Instant?
  private var typingInputGeneration = 0
  private var deferredCorrections: [DeferredCorrection] = []
  private var deferredScanStartLocation: Int?
  private var deferredCorrectionTask: Task<Void, Never>?
  private var suppressesNextRedundantAutomaticValueChange = false
  private var settleGeneration = 0
  private var settleTask: Task<Void, Never>?
  private var workspaceObservers: [NSObjectProtocol] = []
  private var observationRetryCount = 0
  private var isMutationCircuitOpen = false
  private let maximumObservationRetryCount = 4

  convenience init(
    learningStore: CorrectionLearningStore,
    correctionAdapter: BearCorrectionAdapter = BearCorrectionAdapter()
  ) {
    #if DEBUG
      let correctionApplicator =
        BearAutomaticCorrectionDebugFaults.correctionApplicator(
          base: correctionAdapter
        )
    #else
      let correctionApplicator: any BearCorrectionApplying = correctionAdapter
    #endif
    self.init(
      contextReader: BearTypingContextReader(),
      invalidationMonitor: BearAccessibilityInvalidationMonitor(),
      correctionEngine: AppleSpellCheckerEngine(),
      correctionApplicator: correctionApplicator,
      annotationTracker: BearAnnotationOverlayCollectionController(
        adapter: correctionAdapter
      ),
      typingInputMonitor: AppKitBearTypingInputMonitor(),
      environmentChecker: SystemBearEnvironmentChecker(),
      learningStore: learningStore
    )
  }

  init(
    contextReader: any BearTypingContextReading,
    invalidationMonitor: any BearAccessibilityInvalidationObserving,
    correctionEngine: any CorrectionEngine,
    correctionApplicator: any BearCorrectionApplying,
    annotationTracker: any BearAnnotationTracking,
    typingInputMonitor: any BearTypingInputMonitoring,
    environmentChecker: any BearEnvironmentChecking,
    learningStore: CorrectionLearningStore,
    diagnostics: BearAutomaticCorrectionDiagnostics =
      BearAutomaticCorrectionDiagnostics(),
    frontmostBundleIdentifier: @escaping @MainActor @Sendable () -> String? = {
      NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    },
    settleDelay: Duration = .milliseconds(35),
    maximumBoundaryPairingDelay: Duration = .milliseconds(750),
    deferredCorrectionIdleDelay: Duration = .milliseconds(220),
    physicalInputIdleDuration: @escaping @MainActor @Sendable () -> Duration? = {
      SystemPhysicalInputActivity.idleDuration()
    },
    observationRestartDelay: Duration = .milliseconds(250),
    privateDiagnosticsEnabled: @escaping @MainActor @Sendable () -> Bool = {
      UserDefaults.standard.bool(
        forKey: BearAutomaticCorrectionPrivateDiagnostics.defaultsKey
      )
    },
    workspaceNotificationCenter: NotificationCenter =
      NSWorkspace.shared.notificationCenter
  ) {
    self.contextReader = contextReader
    self.invalidationMonitor = invalidationMonitor
    self.correctionEngine = correctionEngine
    self.correctionApplicator = correctionApplicator
    self.annotationTracker = annotationTracker
    self.typingInputMonitor = typingInputMonitor
    self.environmentChecker = environmentChecker
    self.learningStore = learningStore
    self.diagnostics = diagnostics
    self.frontmostBundleIdentifier = frontmostBundleIdentifier
    self.settleDelay = settleDelay
    self.maximumBoundaryPairingDelay = maximumBoundaryPairingDelay
    self.deferredCorrectionIdleDelay = deferredCorrectionIdleDelay
    self.physicalInputIdleDuration = physicalInputIdleDuration
    self.observationRestartDelay = observationRestartDelay
    self.privateDiagnosticsEnabled = privateDiagnosticsEnabled
    self.workspaceNotificationCenter = workspaceNotificationCenter
    installWorkspaceObservers()
  }

  isolated deinit {
    settleTask?.cancel()
    deferredCorrectionTask?.cancel()
    invalidationMonitor.stop()
    typingInputMonitor.stop()
    for observer in workspaceObservers {
      workspaceNotificationCenter.removeObserver(observer)
    }
  }

  func setEnabled(_ enabled: Bool) {
    guard enabled != isEnabled else {
      return
    }
    isEnabled = enabled
    if !enabled {
      isMutationCircuitOpen = false
    }
    if enabled {
      restartObservation()
    } else {
      stopObservation()
      status = .disabled
    }
  }

  private func restartObservation() {
    stopSettling()
    invalidationMonitor.stop()
    typingInputMonitor.stop()
    lastSnapshot = nil
    guard isEnabled else {
      status = .disabled
      return
    }
    guard !isMutationCircuitOpen else {
      status = .pausedAfterIndeterminateWrite
      return
    }
    guard
      frontmostBundleIdentifier()
        == BearAccessibilityProbe.bearBundleIdentifier
    else {
      status = .waitingForBear
      return
    }
    guard validateSupportedEnvironment() else {
      return
    }
    guard invalidationMonitor.start(handler: handle) else {
      diagnostics.recordRefusal(.capabilityUnavailable)
      updateStatus(for: contextReader.read())
      logger.notice("Bear observer attachment deferred")
      scheduleObservationRetry()
      return
    }
    guard
      typingInputMonitor.start(handler: { [weak self] observation in
        guard let self else {
          return
        }
        let intent = observation.intent
        let observedAt = observation.observedAt
        self.typingInputGeneration += 1
        self.scheduleDeferredCorrectionsIfNeeded()
        self.tracePrivate("input intent=\(intent.traceLabel)")
        switch intent {
        case .completionBoundary:
          self.pendingInputIntent = intent
          self.diagnostics.recordBoundaryInput()
          self.pendingBoundaryObservedAt = observedAt
          if self.pendingValueChange {
            // Bear can publish AXValueChanged before AppKit delivers the same
            // physical key to the global monitor. That ordering is safe, but
            // it cannot produce a non-negative host-side arrival sample.
            self.logger.notice(
              "Bear value change preceded completion-boundary callback"
            )
          }
          // AX writes are deliberately idle-first. Bear's editor transaction is
          // not atomic across select, replace, and caret restoration, so writing
          // while the next physical key may arrive risks joining or displacing
          // user input. Record the bounded scan start now and mutate only after
          // the typing stream has been quiet.
          self.markDeferredScanStart()
          self.scheduleDeferredCorrectionsIfNeeded()
          self.logger.debug("Completion boundary key observed")
          if self.pendingValueChange {
            // Bear occasionally publishes the matching AX value change just
            // before the global key monitor callback reaches the main actor.
            self.scheduleSettledRead()
          }
        case .undoOrRedo:
          self.pendingInputIntent = intent
          self.pendingBoundaryObservedAt = nil
          self.clearDeferredCorrections()
          self.logger.debug("Undo or Redo input observed; correction disarmed")
        case .other:
          // Bear can deliver the value-change notification for a completed word
          // after the writer has already pressed the first key of the next word.
          // Keep the boundary armed; exact transition verification still rejects
          // a coalesced or otherwise changed context.
          break
        }
      })
    else {
      invalidationMonitor.stop()
      status = .inputMonitoringUnavailable
      diagnostics.recordRefusal(.inputMonitoringUnavailable)
      logger.error("Typing input monitor unavailable")
      return
    }
    observationRetryCount = 0
    logger.notice("Bear automatic observation ready")
    // Establish the baseline before accepting physical input. This is the one
    // intentional synchronous read at session attachment; all recurring hot-
    // path reads and every mutation use the serialized off-main AX lane.
    let baseline = contextReader.read()
    if case .ready(let snapshot) = baseline {
      lastSnapshot = snapshot
    } else {
      lastSnapshot = nil
    }
    updateStatus(for: baseline)
  }

  private func stopObservation() {
    stopSettling()
    invalidationMonitor.stop()
    typingInputMonitor.stop()
    annotationTracker.stop()
    lastSnapshot = nil
  }

  private func stopSettling() {
    settleGeneration += 1
    settleTask?.cancel()
    settleTask = nil
    pendingValueChange = false
    pendingInputIntent = .other
    pendingBoundaryObservedAt = nil
    scheduledBoundaryObservedAt = nil
    typingInputGeneration += 1
    clearDeferredCorrections()
    suppressesNextRedundantAutomaticValueChange = false
  }

  private func handle(_ event: BearAccessibilityInvalidationEvent) {
    guard isEnabled else {
      return
    }
    annotationTracker.handleInvalidation(event)
    switch event {
    case .valueChanged:
      logger.debug("Bear value change observed")
      tracePrivate("accessibility event=valueChanged")
      if !pendingValueChange, let boundaryObservedAt = pendingBoundaryObservedAt {
        let arrivalElapsed = boundaryObservedAt.duration(to: clock.now)
        logger.notice(
          "Bear completion boundary reached AX value change arrivalMs=\(Optional(arrivalElapsed).traceMilliseconds, privacy: .public)"
        )
      }
      pendingValueChange = true
      scheduleSettledRead()
    case .selectionChanged:
      tracePrivate("accessibility event=selectionChanged")
      scheduleSettledRead()
    case .focusedElementChanged, .focusedWindowChanged:
      tracePrivate("accessibility event=focusChanged")
      scheduleObservationRestart()
    case .layoutChanged, .windowMoved, .windowResized:
      break
    }
  }

  private func scheduleSettledRead() {
    let boundaryObservedAt =
      pendingValueChange
      ? pendingBoundaryObservedAt
      : nil
    if scheduledBoundaryObservedAt != nil {
      // Once a typed boundary is paired with a Bear value change, keep its
      // original deadline. Later selection/value notifications are commonly
      // produced by the next word and must not debounce the correction away.
      return
    }
    settleGeneration += 1
    let generation = settleGeneration
    settleTask?.cancel()
    scheduledBoundaryObservedAt = boundaryObservedAt
    let delay = settleDelay
    settleTask = Task { [weak self] in
      do {
        try await Task.sleep(for: delay)
      } catch {
        return
      }
      guard let self, generation == self.settleGeneration else {
        return
      }
      self.scheduledBoundaryObservedAt = nil
      await self.evaluateSettledChange()
    }
  }

  private func scheduleObservationRestart() {
    stopSettling()
    let delay = observationRestartDelay
    settleTask = Task { [weak self] in
      do {
        try await Task.sleep(for: delay)
      } catch {
        return
      }
      self?.restartObservation()
    }
  }

  private func scheduleObservationRetry() {
    guard
      isEnabled,
      frontmostBundleIdentifier()
        == BearAccessibilityProbe.bearBundleIdentifier,
      observationRetryCount < maximumObservationRetryCount
    else {
      return
    }
    observationRetryCount += 1
    scheduleObservationRestart()
  }

  private func evaluateSettledChange() async {
    let valueChangeWasObserved = pendingValueChange
    let boundaryObservedAt = pendingBoundaryObservedAt
    let pendingBoundaryCharacter: String?
    if case .completionBoundary(let character) = pendingInputIntent {
      pendingBoundaryCharacter = character
    } else {
      pendingBoundaryCharacter = nil
    }
    let boundaryPairingElapsed = boundaryObservedAt.map {
      $0.duration(to: clock.now)
    }
    let valueChangeWasTypedBoundary =
      pendingValueChange
      && pendingBoundaryCharacter != nil
      && boundaryPairingElapsed.map {
        $0 <= maximumBoundaryPairingDelay
      } == true
    let valueChangeHadStaleBoundary =
      pendingValueChange
      && pendingBoundaryCharacter != nil
      && boundaryObservedAt != nil
      && !valueChangeWasTypedBoundary
    let mayBeRedundantAutomaticValueChange =
      suppressesNextRedundantAutomaticValueChange
    pendingValueChange = false
    pendingInputIntent = .other
    pendingBoundaryObservedAt = nil
    suppressesNextRedundantAutomaticValueChange = false

    let result = await readContext()
    guard case .ready(let currentSnapshot) = result else {
      tracePrivate(
        "evaluation result=\(result.traceLabel) valueChange=\(valueChangeWasObserved) boundary=\(pendingBoundaryCharacter.debugDescription)"
      )
      if valueChangeWasObserved {
        diagnostics.recordValueChange()
      }
      if valueChangeWasTypedBoundary {
        diagnostics.recordRefusal(.contextUnavailable)
      }
      lastSnapshot = nil
      updateStatus(for: result)
      return
    }

    let previousSnapshot = lastSnapshot
    lastSnapshot = currentSnapshot
    status = .observing
    tracePrivate(
      "evaluation valueChange=\(valueChangeWasObserved) boundary=\(pendingBoundaryCharacter.debugDescription) ageMs=\(boundaryPairingElapsed.traceMilliseconds) previous={\(previousSnapshot.traceDescription)} current={\(currentSnapshot.traceDescription)}"
    )
    if mayBeRedundantAutomaticValueChange,
      currentSnapshot == previousSnapshot
    {
      tracePrivate("outcome=redundantAutomaticValueChange")
      logger.debug("Ignoring Typover's redundant Bear value change")
      return
    }
    if valueChangeWasObserved {
      diagnostics.recordValueChange()
    }
    if valueChangeHadStaleBoundary {
      tracePrivate("outcome=staleBoundaryInput")
      diagnostics.recordSafeSkip(.staleBoundaryInput)
      return
    }
    guard valueChangeWasTypedBoundary else {
      if valueChangeWasObserved {
        tracePrivate("outcome=unarmedValueChange")
        diagnostics.recordSafeSkip(.unarmedValueChange)
      }
      return
    }
    guard let previousSnapshot else {
      tracePrivate("outcome=baselineUnavailable")
      diagnostics.recordSafeSkip(.baselineUnavailable)
      return
    }
    guard
      let completion = BearTypingTransition.completedWord(
        from: previousSnapshot,
        to: currentSnapshot,
        expectedBoundary: pendingBoundaryCharacter ?? ""
      )
    else {
      if deferredScanStartLocation != nil {
        tracePrivate("outcome=rapidTypingCoalesced")
        logger.debug("Coalesced rapid input deferred to bounded idle scan")
        scheduleDeferredCorrectionsIfNeeded()
        return
      }
      tracePrivate("outcome=contextChanged")
      diagnostics.recordSafeSkip(.contextChanged)
      return
    }
    guard
      let engineProposal = correctionEngine.proposal(
        for: completion.word.text
      )
    else {
      tracePrivate("outcome=noSuggestion word=\(completion.word.text.debugDescription)")
      diagnostics.recordSafeSkip(.noSuggestion)
      return
    }
    guard
      let proposal = learningStore.applyingPreference(to: engineProposal)
    else {
      tracePrivate("outcome=learnedSuppression")
      diagnostics.recordSafeSkip(.learnedSuppression)
      return
    }
    guard proposal.correction.original == completion.word.text else {
      tracePrivate("outcome=proposalMismatch")
      diagnostics.recordRefusal(.proposalMismatch)
      return
    }

    deferredScanStartLocation = min(
      deferredScanStartLocation ?? completion.targetRange.location,
      completion.targetRange.location
    )
    deferredCorrections.append(
      DeferredCorrection(
        proposal: proposal,
        targetRange: completion.targetRange,
        boundaryObservedAt: boundaryObservedAt,
        authorizedContext: currentSnapshot
      )
    )
    diagnostics.recordDeferred()
    tracePrivate(
      "outcome=idleDeferred range=\(completion.targetRange.location):\(completion.targetRange.length)"
    )
    logger.debug("Correction deferred until typing is idle")
    scheduleDeferredCorrectionsIfNeeded()
  }

  private func scheduleDeferredCorrectionsIfNeeded() {
    guard
      !deferredCorrections.isEmpty || deferredScanStartLocation != nil
    else {
      deferredCorrectionTask?.cancel()
      deferredCorrectionTask = nil
      return
    }
    deferredCorrectionTask?.cancel()
    let generation = typingInputGeneration
    let delay = deferredCorrectionIdleDelay
    deferredCorrectionTask = Task { [weak self] in
      do {
        try await Task.sleep(for: delay)
      } catch {
        return
      }
      guard let self, generation == self.typingInputGeneration else {
        return
      }
      await self.applyDeferredCorrections()
    }
  }

  private func applyDeferredCorrections() async {
    deferredCorrectionTask = nil
    guard
      frontmostBundleIdentifier()
        == BearAccessibilityProbe.bearBundleIdentifier
    else {
      clearDeferredCorrections()
      return
    }
    if let physicalIdle = physicalInputIdleDuration(),
      physicalIdle < deferredCorrectionIdleDelay
    {
      tracePrivate(
        "outcome=physicalInputStillActive idleMs=\(Self.milliseconds(physicalIdle))"
      )
      scheduleDeferredCorrectionsIfNeeded()
      return
    }

    let scanGeneration = typingInputGeneration
    await appendDeferredCorrectionsFromRapidScan()
    await Task.yield()
    guard scanGeneration == typingInputGeneration else {
      scheduleDeferredCorrectionsIfNeeded()
      return
    }
    let validationGeneration = typingInputGeneration
    guard case .ready(let currentContext) = await readContext() else {
      tracePrivate("outcome=deferredContextUnavailable")
      diagnostics.recordSafeSkip(.contextChanged)
      clearDeferredCorrections()
      await rebaseline()
      return
    }
    guard
      validationGeneration == typingInputGeneration,
      deferredCorrections.allSatisfy({
        BearDeferredTypingTransition.preservesAppendOnlyContext(
          from: $0.authorizedContext,
          to: currentContext
        )
      })
    else {
      tracePrivate("outcome=deferredContextChanged")
      diagnostics.recordSafeSkip(.contextChanged)
      clearDeferredCorrections()
      await rebaseline()
      return
    }
    let pending = deferredCorrections.sorted {
      $0.targetRange.location > $1.targetRange.location
    }
    deferredCorrections.removeAll(keepingCapacity: true)
    let applicationGeneration = typingInputGeneration
    for (index, correction) in pending.enumerated() {
      let applicator = correctionApplicator
      let original = correction.proposal.correction.original
      let replacement = correction.proposal.correction.replacement
      let targetRange = correction.targetRange
      let application = await BearAccessibilityOperationLane.shared.run {
        applicator.apply(
          original: original,
          replacement: replacement,
          at: targetRange
        )
      }
      guard application.isReversibleApplication else {
        tracePrivate(
          "outcome=deferredReplacementRefused status=\(application.report.status.rawValue) range=\(correction.targetRange.location):\(correction.targetRange.length)"
        )
        if application.report.writeOccurred {
          diagnostics.recordRefusal(.postWriteReconciliationFailed)
          openMutationCircuit(
            status: application.report.status,
            range: correction.targetRange
          )
          return
        }
        diagnostics.recordRefusal(.replacementRefused)
        continue
      }
      let correctionElapsed = correction.boundaryObservedAt.map {
        $0.duration(to: clock.now)
      }
      recordVerifiedApplication(
        application,
        proposal: correction.proposal,
        boundaryObservedAt: correction.boundaryObservedAt
      )
      if !application.report.isVerifiedApplication {
        diagnostics.recordPostWriteReconciled()
        logger.error(
          "Automatic correction recovered reversibility after post-write status: \(application.report.status.rawValue, privacy: .public)"
        )
      }
      tracePrivate(
        "outcome=deferredApplied original=\(correction.proposal.correction.original.debugDescription) replacement=\(correction.proposal.correction.replacement.debugDescription) range=\(correction.targetRange.location):\(correction.targetRange.length)"
      )
      // Keep the canonical marker shared with immediate applications so the
      // physical HID harness counts both execution paths consistently.
      logger.notice(
        "Automatic correction applied latencyMs=\(correctionElapsed.traceMilliseconds, privacy: .public)"
      )
      await Task.yield()
      guard applicationGeneration == typingInputGeneration else {
        let remainingIndex = pending.index(after: index)
        if remainingIndex < pending.endIndex {
          deferredCorrections.append(
            contentsOf: pending[remainingIndex...]
          )
        }
        scheduleDeferredCorrectionsIfNeeded()
        await rebaseline()
        return
      }
    }
    suppressesNextRedundantAutomaticValueChange = true
    await rebaseline()
  }

  private func recordVerifiedApplication(
    _ application: BearCorrectionApplication,
    proposal: CorrectionProposal,
    boundaryObservedAt: ContinuousClock.Instant?
  ) {
    suppressesNextRedundantAutomaticValueChange = true
    learningStore.recordApplied(proposal)
    annotationTracker.recordVerifiedEdit(
      BearAnnotationVerifiedEdit(
        replacedRange: application.report.targetRange,
        replacementLength: application.correction.replacement.utf16.count
      )
    )
    annotationTracker.trackWithResolution(
      application,
      alternatives: proposal.alternatives,
      userRecency: proposal.correction.createdAt,
      onFirstVisible: { [weak self] in
        guard let self, let boundaryObservedAt else {
          return
        }
        let elapsed = boundaryObservedAt.duration(to: self.clock.now)
        self.diagnostics.recordVisible(elapsed: elapsed)
        self.logger.notice(
          "Automatic correction visible latencyMs=\(Optional(elapsed).traceMilliseconds, privacy: .public)"
        )
      },
      onInteractionLatency: { [weak self] elapsed in
        self?.diagnostics.recordInteractionLatency(elapsed)
        self?.logger.notice(
          "Overlay interaction verified latencyMs=\(Optional(elapsed).traceMilliseconds, privacy: .public)"
        )
      },
      onResolution: { [weak self] resolution in
        self?.record(resolution, for: proposal)
      },
      onFinished: nil
    )
    diagnostics.recordApplied()
  }

  private func openMutationCircuit(
    status writeStatus: BearExactRangeReplacementStatus,
    range: AccessibilityTextRange
  ) {
    isMutationCircuitOpen = true
    stopSettling()
    invalidationMonitor.stop()
    typingInputMonitor.stop()
    annotationTracker.stop()
    lastSnapshot = nil
    status = .pausedAfterIndeterminateWrite
    tracePrivate(
      "outcome=postWriteReconciliationFailed status=\(writeStatus.rawValue) range=\(range.location):\(range.length)"
    )
    logger.fault(
      "Automatic correction paused after an unreconciled AX write: \(writeStatus.rawValue, privacy: .public)"
    )
  }

  private func clearDeferredCorrections() {
    deferredCorrectionTask?.cancel()
    deferredCorrectionTask = nil
    deferredCorrections.removeAll(keepingCapacity: true)
    deferredScanStartLocation = nil
  }

  private func markDeferredScanStart() {
    guard let snapshot = lastSnapshot else {
      return
    }
    let localCaret = snapshot.caretLocation - snapshot.leadingRange.location
    guard
      localCaret >= 0,
      localCaret <= snapshot.leadingText.utf16.count
    else {
      return
    }

    let leadingText = snapshot.leadingText as NSString
    let textBeforeCaret = leadingText.substring(
      with: NSRange(location: 0, length: localCaret)
    )
    let syntheticBoundaryText = textBeforeCaret + " "
    let activeWord = CompletedWordDetector.immediatelyBeforeCaret(
      in: syntheticBoundaryText,
      caretUTF16Offset: syntheticBoundaryText.utf16.count
    )
    guard let word = activeWord else {
      return
    }

    let absoluteStart = snapshot.leadingRange.location + word.range.location
    deferredScanStartLocation = min(
      deferredScanStartLocation ?? absoluteStart,
      absoluteStart
    )
  }

  private func appendDeferredCorrectionsFromRapidScan() async {
    guard let requestedStart = deferredScanStartLocation else {
      return
    }
    deferredScanStartLocation = nil
    guard case .ready(let snapshot) = await readContext() else {
      tracePrivate("outcome=rapidScanUnavailable")
      return
    }

    let availableStart = snapshot.leadingRange.location
    let scanStart = max(requestedStart, availableStart)
    let scanEnd = snapshot.caretLocation
    guard scanEnd > scanStart else {
      return
    }
    if scanStart != requestedStart {
      tracePrivate(
        "outcome=rapidScanTruncated requestedStart=\(requestedStart) availableStart=\(availableStart)"
      )
    }

    let localScanRange = NSRange(
      location: scanStart - availableStart,
      length: scanEnd - scanStart
    )
    for word in CompletedWordDetector.completedWords(
      in: snapshot.leadingText,
      utf16Range: localScanRange
    ) {
      let targetRange = AccessibilityTextRange(
        location: availableStart + word.range.location,
        length: word.range.length
      )
      guard
        !deferredCorrections.contains(where: {
          $0.targetRange == targetRange
        }),
        let engineProposal = correctionEngine.proposal(for: word.text),
        let proposal = learningStore.applyingPreference(to: engineProposal),
        proposal.correction.original == word.text
      else {
        continue
      }
      deferredCorrections.append(
        DeferredCorrection(
          proposal: proposal,
          targetRange: targetRange,
          boundaryObservedAt: nil,
          authorizedContext: snapshot
        )
      )
      diagnostics.recordDeferred()
      tracePrivate(
        "outcome=rapidScanDeferred range=\(targetRange.location):\(targetRange.length)"
      )
    }
  }

  private func rebaseline() async {
    let result = await readContext()
    if case .ready(let snapshot) = result {
      lastSnapshot = snapshot
      tracePrivate("baseline snapshot={\(snapshot.traceDescription)}")
    } else {
      lastSnapshot = nil
      tracePrivate("baseline result=\(result.traceLabel)")
    }
    updateStatus(for: result)
  }

  private func readContext() async -> BearTypingContextReadResult {
    let reader = contextReader
    return await BearAccessibilityOperationLane.shared.run {
      reader.read()
    }
  }

  private func tracePrivate(_ message: String) {
    logger.notice(
      "Diagnostic \(BearPrivateDiagnosticsStore.contentFreeEvent(from: message), privacy: .public)"
    )
    guard privateDiagnosticsEnabled() else {
      return
    }
    BearPrivateDiagnosticsStore.shared.record(message)
  }

  private static func milliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
  }

  private func updateStatus(for result: BearTypingContextReadResult) {
    switch result {
    case .ready:
      status = .observing
    case .accessibilityPermissionRequired:
      status = .accessibilityPermissionRequired
    case .bearNotRunning, .bearNotFrontmost:
      status = .waitingForBear
    case .selectionActive:
      status = .pausedForSelection
    case .focusedEditorUnavailable, .contextUnavailable:
      status = .editorUnavailable
    }
  }

  private func validateSupportedEnvironment() -> Bool {
    switch environmentChecker.support() {
    case .supported:
      return true
    case .bearNotRunning:
      status = .waitingForBear
    case .bearVersionUnavailable:
      status = .bearVersionUnavailable
    case .unsupportedBearVersion(let installed):
      status = .unsupportedBearVersion(installed: installed)
    case .unsupportedMacOSVersion(let installed):
      status = .unsupportedMacOSVersion(installed: installed)
    }
    logger.error("Bear automatic correction blocked by support policy")
    diagnostics.recordRefusal(.unsupportedEnvironment)
    return false
  }

  private func record(
    _ resolution: BearAnnotationResolution,
    for proposal: CorrectionProposal
  ) {
    switch resolution {
    case .changedBack:
      learningStore.recordReverted(proposal)
      correctionEngine.record(.reverted, for: proposal)
    case .choseAlternative(let replacement):
      learningStore.recordPreferred(
        replacement,
        for: proposal,
        outcome: .alternativeChosen
      )
      correctionEngine.record(.edited, for: proposal)
    }
  }

  private func installWorkspaceObservers() {
    let names: [Notification.Name] = [
      NSWorkspace.didActivateApplicationNotification,
      NSWorkspace.didHideApplicationNotification,
      NSWorkspace.didTerminateApplicationNotification,
    ]
    workspaceObservers = names.map { name in
      workspaceNotificationCenter.addObserver(
        forName: name,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.observationRetryCount = 0
          self?.scheduleObservationRestart()
        }
      }
    }
  }
}

extension BearTypingInputIntent {
  fileprivate var traceLabel: String {
    switch self {
    case .completionBoundary(let character):
      "completionBoundary(\(character.debugDescription))"
    case .undoOrRedo:
      "undoOrRedo"
    case .other:
      "other"
    }
  }
}

extension BearTypingContextReadResult {
  fileprivate var traceLabel: String {
    switch self {
    case .ready:
      "ready"
    case .accessibilityPermissionRequired:
      "accessibilityPermissionRequired"
    case .bearNotRunning:
      "bearNotRunning"
    case .bearNotFrontmost:
      "bearNotFrontmost"
    case .focusedEditorUnavailable:
      "focusedEditorUnavailable"
    case .selectionActive:
      "selectionActive"
    case .contextUnavailable:
      "contextUnavailable"
    }
  }
}

extension BearTypingContextSnapshot {
  fileprivate var traceDescription: String {
    "caret=\(caretLocation) documentLength=\(documentLength) leadingRange=\(leadingRange.location):\(leadingRange.length) leading=\(leadingText.debugDescription) trailing=\(trailingText.debugDescription)"
  }
}

extension Optional where Wrapped == BearTypingContextSnapshot {
  fileprivate var traceDescription: String {
    switch self {
    case .some(let snapshot):
      snapshot.traceDescription
    case .none:
      "none"
    }
  }
}

extension Optional where Wrapped == Duration {
  fileprivate var traceMilliseconds: String {
    guard let duration = self else {
      return "none"
    }
    let components = duration.components
    let milliseconds =
      Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
    return String(
      format: "%.3f",
      locale: Locale(identifier: "en_US_POSIX"),
      arguments: [milliseconds]
    )
  }
}
