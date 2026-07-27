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
}

protocol BearCorrectionApplying: Sendable {
  func apply(
    original: String,
    replacement: String,
    at targetRange: AccessibilityTextRange
  ) -> BearCorrectionApplication
}

extension BearCorrectionAdapter: BearCorrectionApplying {}

@MainActor
protocol BearAnnotationTracking: AnyObject {
  func trackWithResolution(
    _ application: BearCorrectionApplication,
    alternatives: [String],
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

extension BearAnnotationOverlayController: BearAnnotationTracking {}
extension BearAnnotationOverlayCollectionController: BearAnnotationTracking {}

@MainActor
protocol BearTypingInputMonitoring: AnyObject {
  @discardableResult
  func start(
    handler: @escaping @MainActor @Sendable (BearTypingInputIntent) -> Void
  ) -> Bool
  func stop()
}

@MainActor
final class AppKitBearTypingInputMonitor: BearTypingInputMonitoring {
  private var eventMonitor: Any?

  func start(
    handler: @escaping @MainActor @Sendable (BearTypingInputIntent) -> Void
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
      Task { @MainActor in
        handler(intent)
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
  static let defaultsKey = "bear-private-diagnostics-enabled"
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

@MainActor
@Observable
final class BearAutomaticCorrectionCoordinator {
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
  private var suppressesNextRedundantAutomaticValueChange = false
  private var settleGeneration = 0
  private var settleTask: Task<Void, Never>?
  private var workspaceObservers: [NSObjectProtocol] = []
  private var observationRetryCount = 0
  private let maximumObservationRetryCount = 4

  convenience init(
    learningStore: CorrectionLearningStore,
    correctionAdapter: BearCorrectionAdapter = BearCorrectionAdapter()
  ) {
    self.init(
      contextReader: BearTypingContextReader(),
      invalidationMonitor: BearAccessibilityInvalidationMonitor(),
      correctionEngine: AppleSpellCheckerEngine(),
      correctionApplicator: correctionAdapter,
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
    self.observationRestartDelay = observationRestartDelay
    self.privateDiagnosticsEnabled = privateDiagnosticsEnabled
    self.workspaceNotificationCenter = workspaceNotificationCenter
    installWorkspaceObservers()
  }

  isolated deinit {
    settleTask?.cancel()
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
    guard typingInputMonitor.start(handler: { [weak self] intent in
      guard let self else {
        return
      }
      self.tracePrivate("input intent=\(intent.traceLabel)")
      switch intent {
      case .completionBoundary:
        self.pendingInputIntent = intent
        self.diagnostics.recordBoundaryInput()
        self.pendingBoundaryObservedAt = self.clock.now
        self.logger.debug("Completion boundary key observed")
        if self.pendingValueChange {
          // Bear occasionally publishes the matching AX value change just
          // before the global key monitor callback reaches the main actor.
          self.scheduleSettledRead()
        }
      case .undoOrRedo:
        self.pendingInputIntent = intent
        self.pendingBoundaryObservedAt = nil
        self.logger.debug("Undo or Redo input observed; correction disarmed")
      case .other:
        // Bear can deliver the value-change notification for a completed word
        // after the writer has already pressed the first key of the next word.
        // Keep the boundary armed; exact transition verification still rejects
        // a coalesced or otherwise changed context.
        break
      }
    }) else {
      invalidationMonitor.stop()
      status = .inputMonitoringUnavailable
      diagnostics.recordRefusal(.inputMonitoringUnavailable)
      logger.error("Typing input monitor unavailable")
      return
    }
    observationRetryCount = 0
    logger.notice("Bear automatic observation ready")
    rebaseline()
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
    suppressesNextRedundantAutomaticValueChange = false
  }

  private func handle(_ event: BearAccessibilityInvalidationEvent) {
    guard isEnabled else {
      return
    }
    switch event {
    case .valueChanged:
      logger.debug("Bear value change observed")
      tracePrivate("accessibility event=valueChanged")
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
    let boundaryObservedAt = pendingValueChange
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
      self.evaluateSettledChange()
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

  private func evaluateSettledChange() {
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

    let result = contextReader.read()
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

    let application = correctionApplicator.apply(
      original: proposal.correction.original,
      replacement: proposal.correction.replacement,
      at: completion.targetRange
    )
    guard application.report.isVerifiedApplication else {
      tracePrivate(
        "outcome=replacementRefused status=\(application.report.status.rawValue)"
      )
      diagnostics.recordRefusal(.replacementRefused)
      logger.notice(
        "Automatic correction refused: \(application.report.status.rawValue, privacy: .public)"
      )
      rebaseline()
      return
    }
    suppressesNextRedundantAutomaticValueChange = true

    learningStore.recordApplied(proposal)
    annotationTracker.trackWithResolution(
      application,
      alternatives: proposal.alternatives,
      onInteractionLatency: { [weak self] elapsed in
        self?.diagnostics.recordInteractionLatency(elapsed)
      },
      onResolution: { [weak self] resolution in
        self?.record(resolution, for: proposal)
      },
      onFinished: nil
    )
    diagnostics.recordApplied(
      elapsed: boundaryPairingElapsed
    )
    tracePrivate(
      "outcome=applied original=\(proposal.correction.original.debugDescription) replacement=\(proposal.correction.replacement.debugDescription) range=\(completion.targetRange.location):\(completion.targetRange.length)"
    )
    logger.notice("Automatic correction applied")
    rebaseline()
  }

  private func rebaseline() {
    let result = contextReader.read()
    if case .ready(let snapshot) = result {
      lastSnapshot = snapshot
      tracePrivate("baseline snapshot={\(snapshot.traceDescription)}")
    } else {
      lastSnapshot = nil
      tracePrivate("baseline result=\(result.traceLabel)")
    }
    updateStatus(for: result)
  }

  private func tracePrivate(_ message: String) {
    guard privateDiagnosticsEnabled() else {
      return
    }
    logger.notice("PRIVATE_DIAGNOSTIC \(message, privacy: .public)")
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

private extension BearTypingInputIntent {
  var traceLabel: String {
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

private extension BearTypingContextReadResult {
  var traceLabel: String {
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

private extension BearTypingContextSnapshot {
  var traceDescription: String {
    "caret=\(caretLocation) documentLength=\(documentLength) leadingRange=\(leadingRange.location):\(leadingRange.length) leading=\(leadingText.debugDescription) trailing=\(trailingText.debugDescription)"
  }
}

private extension Optional where Wrapped == BearTypingContextSnapshot {
  var traceDescription: String {
    switch self {
    case .some(let snapshot):
      snapshot.traceDescription
    case .none:
      "none"
    }
  }
}

private extension Optional where Wrapped == Duration {
  var traceMilliseconds: String {
    guard let duration = self else {
      return "none"
    }
    let components = duration.components
    let milliseconds =
      Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
    return milliseconds.formatted(
      .number.precision(.fractionLength(3))
    )
  }
}
