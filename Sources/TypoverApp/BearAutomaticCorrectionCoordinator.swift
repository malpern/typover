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
  case accessibilityPermissionRequired
  case editorUnavailable
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
    onResolution: (
      @MainActor @Sendable (BearAnnotationResolution) -> Void
    )?,
    onFinished: (@MainActor @Sendable () -> Void)?
  )

  func stop()
}

extension BearAnnotationOverlayController: BearAnnotationTracking {}

@MainActor
protocol BearTypingInputMonitoring: AnyObject {
  func start(
    handler: @escaping @MainActor @Sendable (Bool) -> Void
  )
  func stop()
}

@MainActor
final class AppKitBearTypingInputMonitor: BearTypingInputMonitoring {
  private var eventMonitor: Any?

  func start(
    handler: @escaping @MainActor @Sendable (Bool) -> Void
  ) {
    stop()
    eventMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: .keyDown
    ) { event in
      let modifiers = event.modifierFlags.intersection(
        .deviceIndependentFlagsMask
      )
      let disallowedModifiers: NSEvent.ModifierFlags = [
        .command,
        .control,
        .option,
      ]
      let isUnmodifiedBoundary =
        modifiers.isDisjoint(
          with: disallowedModifiers
        ) && event.characters.map(BearTypingInput.isCompletionBoundary) == true
      Task { @MainActor in
        handler(isUnmodifiedBoundary)
      }
    }
  }

  func stop() {
    if let eventMonitor {
      NSEvent.removeMonitor(eventMonitor)
      self.eventMonitor = nil
    }
  }
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
}

struct VerifiedBearTypingCompletion: Equatable {
  let word: CompletedWord
  let targetRange: AccessibilityTextRange
}

enum BearTypingTransition {
  static func completedWord(
    from previous: BearTypingContextSnapshot,
    to current: BearTypingContextSnapshot
  ) -> VerifiedBearTypingCompletion? {
    guard
      current.documentLength == previous.documentLength + 1,
      current.caretLocation == previous.caretLocation + 1,
      current.leadingRange.location + current.leadingRange.length
        == current.caretLocation,
      current.leadingText.utf16.count == current.leadingRange.length,
      current.leadingRange.length > 0,
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

  private let contextReader: any BearTypingContextReading
  private let invalidationMonitor: any BearAccessibilityInvalidationObserving
  private let correctionEngine: any CorrectionEngine
  private let correctionApplicator: any BearCorrectionApplying
  private let annotationTracker: any BearAnnotationTracking
  private let typingInputMonitor: any BearTypingInputMonitoring
  private let learningStore: CorrectionLearningStore
  private let frontmostBundleIdentifier: @MainActor @Sendable () -> String?
  private let settleDelay: Duration
  private let workspaceNotificationCenter: NotificationCenter
  private let logger = Logger(
    subsystem: "com.malpern.typover",
    category: "BearAutomaticCorrection"
  )

  private var isEnabled = false
  private var lastSnapshot: BearTypingContextSnapshot?
  private var pendingValueChange = false
  private var pendingTypedBoundary = false
  private var settleGeneration = 0
  private var settleTask: Task<Void, Never>?
  private var workspaceObservers: [NSObjectProtocol] = []

  convenience init(
    learningStore: CorrectionLearningStore,
    correctionAdapter: BearCorrectionAdapter = BearCorrectionAdapter()
  ) {
    self.init(
      contextReader: BearTypingContextReader(),
      invalidationMonitor: BearAccessibilityInvalidationMonitor(),
      correctionEngine: AppleSpellCheckerEngine(),
      correctionApplicator: correctionAdapter,
      annotationTracker: BearAnnotationOverlayController(
        adapter: correctionAdapter
      ),
      typingInputMonitor: AppKitBearTypingInputMonitor(),
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
    learningStore: CorrectionLearningStore,
    frontmostBundleIdentifier: @escaping @MainActor @Sendable () -> String? = {
      NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    },
    settleDelay: Duration = .milliseconds(35),
    workspaceNotificationCenter: NotificationCenter =
      NSWorkspace.shared.notificationCenter
  ) {
    self.contextReader = contextReader
    self.invalidationMonitor = invalidationMonitor
    self.correctionEngine = correctionEngine
    self.correctionApplicator = correctionApplicator
    self.annotationTracker = annotationTracker
    self.typingInputMonitor = typingInputMonitor
    self.learningStore = learningStore
    self.frontmostBundleIdentifier = frontmostBundleIdentifier
    self.settleDelay = settleDelay
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
    guard invalidationMonitor.start(handler: handle) else {
      updateStatus(for: contextReader.read())
      return
    }
    typingInputMonitor.start { [weak self] isBoundary in
      self?.pendingTypedBoundary = isBoundary
    }
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
    pendingTypedBoundary = false
  }

  private func handle(_ event: BearAccessibilityInvalidationEvent) {
    guard isEnabled else {
      return
    }
    switch event {
    case .valueChanged:
      pendingValueChange = true
      scheduleSettledRead()
    case .selectionChanged:
      scheduleSettledRead()
    case .focusedElementChanged, .focusedWindowChanged:
      scheduleObservationRestart()
    case .layoutChanged, .windowMoved, .windowResized:
      break
    }
  }

  private func scheduleSettledRead() {
    settleGeneration += 1
    let generation = settleGeneration
    settleTask?.cancel()
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
      self.evaluateSettledChange()
    }
  }

  private func scheduleObservationRestart() {
    stopSettling()
    let delay = settleDelay
    settleTask = Task { [weak self] in
      do {
        try await Task.sleep(for: delay)
      } catch {
        return
      }
      self?.restartObservation()
    }
  }

  private func evaluateSettledChange() {
    let result = contextReader.read()
    guard case .ready(let currentSnapshot) = result else {
      lastSnapshot = nil
      updateStatus(for: result)
      return
    }

    let previousSnapshot = lastSnapshot
    lastSnapshot = currentSnapshot
    status = .observing
    let valueChangeWasTypedBoundary =
      pendingValueChange && pendingTypedBoundary
    pendingValueChange = false
    pendingTypedBoundary = false
    guard valueChangeWasTypedBoundary else {
      return
    }
    guard
      let previousSnapshot,
      let completion = BearTypingTransition.completedWord(
        from: previousSnapshot,
        to: currentSnapshot
      ),
      let engineProposal = correctionEngine.proposal(
        for: completion.word.text
      ),
      let proposal = learningStore.applyingPreference(to: engineProposal),
      proposal.correction.original == completion.word.text
    else {
      return
    }

    let application = correctionApplicator.apply(
      original: proposal.correction.original,
      replacement: proposal.correction.replacement,
      at: completion.targetRange
    )
    guard application.report.isVerifiedApplication else {
      logger.notice(
        "Automatic correction refused: \(application.report.status.rawValue, privacy: .public)"
      )
      rebaseline()
      return
    }

    learningStore.recordApplied(proposal)
    annotationTracker.trackWithResolution(
      application,
      alternatives: proposal.alternatives,
      onResolution: { [weak self] resolution in
        self?.record(resolution, for: proposal)
      },
      onFinished: nil
    )
    logger.notice("Automatic correction applied")
    rebaseline()
  }

  private func rebaseline() {
    let result = contextReader.read()
    if case .ready(let snapshot) = result {
      lastSnapshot = snapshot
    } else {
      lastSnapshot = nil
    }
    updateStatus(for: result)
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
          self?.restartObservation()
        }
      }
    }
  }
}
