import AppKit
import OSLog
import TypoverAccessibility
import TypoverBearAdapter
import TypoverCore

public protocol BearCorrectionGeometryResolving: Sendable {
  func geometry(
    for application: BearCorrectionApplication
  ) -> BearCorrectionGeometryReport
}

public protocol BearCorrectionServicing:
  BearCorrectionGeometryResolving, Sendable
{
  func changeBack(
    _ application: BearCorrectionApplication
  ) -> BearCorrectionRestoration

  func chooseAlternative(
    _ replacement: String,
    for application: BearCorrectionApplication
  ) -> BearCorrectionAlternativeApplication

  func reanchor(
    _ application: BearCorrectionApplication,
    at targetRange: AccessibilityTextRange
  ) -> BearCorrectionReanchoredApplication

  func stabilizeSelection(
    _ request: BearCorrectionSelectionStabilizationRequest
  ) -> BearCorrectionSelectionStabilizationStatus
}

extension BearCorrectionAdapter: BearCorrectionServicing {}

public enum BearAnnotationResolution: Equatable, Sendable {
  case changedBack
  case choseAlternative(String)
}

@MainActor
public final class BearAnnotationOverlayController {
  public static let fallbackRefreshInterval = Duration.milliseconds(125)
  public static let recentMarkDuration = Duration.milliseconds(
    CorrectionMarkTiming.visibleMilliseconds
  )
  public static let reviewRevealDelay = Duration.milliseconds(100)
  public static let reviewExitDelay = Duration.milliseconds(250)
  public static let hoverMenuDelay = Duration.milliseconds(350)

  private let logger = Logger(
    subsystem: "com.malpern.typover",
    category: "BearAnnotationOverlay"
  )

  private let adapter: any BearCorrectionServicing
  private let presenter: any BearAnnotationPresenting
  private let invalidationMonitor: any BearAccessibilityInvalidationObserving
  private let frontmostBundleIdentifier: @MainActor @Sendable () -> String?
  private let displays: @MainActor @Sendable () -> [BearOverlayDisplay]
  private let fallbackRefreshInterval: Duration
  private let textChangeRefreshDelay: Duration
  private let selectionStabilizationDelays: [Duration]
  private let handlesKeyboardShortcut: Bool
  private let shortcutRegistrar: any BearAnnotationShortcutRegistering
  private let hostApplicationBundleIdentifier: String?
  private let voiceOverEnabled: @MainActor @Sendable () -> Bool
  private let mutationIsAllowed: @MainActor @Sendable () -> Bool
  private let activateBear: @MainActor @Sendable () -> Void
  private let marksAlwaysVisible: @MainActor @Sendable () -> Bool
  private let recentMarkDuration: Duration
  private let reviewRevealDelay: Duration
  private let reviewExitDelay: Duration
  private let hoverMenuDelay: Duration
  private var usesSharedLifecycle = false

  private var application: BearCorrectionApplication?
  private var refreshGeneration = 0
  private var refreshTask: Task<Void, Never>?
  private var textChangeRefreshTask: Task<Void, Never>?
  private var pendingTextChangeMayInvalidateAnchor = false
  private var fallbackTask: Task<Void, Never>?
  private var interactionTask: Task<Void, Never>?
  private var selectionStabilizationTask: Task<Void, Never>?
  private var recentMarkTask: Task<Void, Never>?
  private var reviewRevealTask: Task<Void, Never>?
  private var reviewExitTask: Task<Void, Never>?
  private var hoverMenuTask: Task<Void, Never>?
  private var workspaceObservers: [NSObjectProtocol] = []
  private var shortcutToken: UUID?
  private var alternatives: [String] = []
  private var onFirstVisible: (@MainActor @Sendable () -> Void)?
  private var onInteractionLatency: (@MainActor @Sendable (Duration) -> Void)?
  private var onFinished: (@MainActor @Sendable () -> Void)?
  private var onResolution: (@MainActor @Sendable (BearAnnotationResolution) -> Void)?
  private var onVerifiedEdit: (@MainActor @Sendable (BearAnnotationVerifiedEdit) -> Void)?
  private var lastResolvedRange: AccessibilityTextRange?
  private var cachedFrontmostBundleIdentifier: String?
  private var trackedCorrectionID: String?
  private var reportedVisible = false
  private var accessibilityInteractionIsActive = false
  private var recentMarkIsVisible = true
  private var reviewIsVisible = false
  private var menuIsVisible = false
  private var pointerIsNearReview = false
  private var pointerIsOverMark = false
  private var hoverMenuWasPresented = false

  public convenience init(
    adapter: any BearCorrectionServicing = BearCorrectionAdapter(),
    presenter: any BearAnnotationPresenting =
      AppKitBearAnnotationPresenter(),
    invalidationMonitor: any BearAccessibilityInvalidationObserving =
      BearAccessibilityInvalidationMonitor(),
    frontmostBundleIdentifier: @escaping @MainActor @Sendable () -> String? = {
      NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    },
    displays: @escaping @MainActor @Sendable () -> [BearOverlayDisplay] = {
      BearAnnotationOverlayController.currentDisplays()
    },
    fallbackRefreshInterval: Duration =
      BearAnnotationOverlayController.fallbackRefreshInterval,
    textChangeRefreshDelay: Duration = .zero,
    handlesKeyboardShortcut: Bool = true,
    selectionStabilizationDelays: [Duration] = [
      .milliseconds(40),
      .milliseconds(180),
    ],
    marksAlwaysVisible: @escaping @MainActor @Sendable () -> Bool = {
      false
    },
    mutationIsAllowed: @escaping @MainActor @Sendable () -> Bool = {
      true
    }
  ) {
    self.init(
      adapter: adapter,
      presenter: presenter,
      invalidationMonitor: invalidationMonitor,
      frontmostBundleIdentifier: frontmostBundleIdentifier,
      displays: displays,
      fallbackRefreshInterval: fallbackRefreshInterval,
      textChangeRefreshDelay: textChangeRefreshDelay,
      handlesKeyboardShortcut: handlesKeyboardShortcut,
      selectionStabilizationDelays: selectionStabilizationDelays,
      shortcutRegistrar: BearAnnotationShortcutCenter.shared,
      mutationIsAllowed: mutationIsAllowed,
      marksAlwaysVisible: marksAlwaysVisible
    )
  }

  init(
    adapter: any BearCorrectionServicing,
    presenter: any BearAnnotationPresenting,
    invalidationMonitor: any BearAccessibilityInvalidationObserving,
    frontmostBundleIdentifier: @escaping @MainActor @Sendable () -> String?,
    displays: @escaping @MainActor @Sendable () -> [BearOverlayDisplay],
    fallbackRefreshInterval: Duration,
    textChangeRefreshDelay: Duration,
    handlesKeyboardShortcut: Bool,
    selectionStabilizationDelays: [Duration],
    shortcutRegistrar: any BearAnnotationShortcutRegistering,
    hostApplicationBundleIdentifier: String? = Bundle.main.bundleIdentifier,
    voiceOverEnabled: @escaping @MainActor @Sendable () -> Bool = {
      NSWorkspace.shared.isVoiceOverEnabled
    },
    mutationIsAllowed: @escaping @MainActor @Sendable () -> Bool = {
      true
    },
    activateBear: @escaping @MainActor @Sendable () -> Void = {
      _ = NSRunningApplication.runningApplications(
        withBundleIdentifier: BearAccessibilityProbe.bearBundleIdentifier
      ).first?.activate(options: [.activateAllWindows])
    },
    marksAlwaysVisible: @escaping @MainActor @Sendable () -> Bool = {
      false
    },
    recentMarkDuration: Duration =
      BearAnnotationOverlayController.recentMarkDuration,
    reviewRevealDelay: Duration =
      BearAnnotationOverlayController.reviewRevealDelay,
    reviewExitDelay: Duration =
      BearAnnotationOverlayController.reviewExitDelay,
    hoverMenuDelay: Duration =
      BearAnnotationOverlayController.hoverMenuDelay
  ) {
    self.adapter = adapter
    self.presenter = presenter
    self.invalidationMonitor = invalidationMonitor
    self.frontmostBundleIdentifier = frontmostBundleIdentifier
    self.displays = displays
    self.fallbackRefreshInterval = fallbackRefreshInterval
    self.textChangeRefreshDelay = textChangeRefreshDelay
    self.handlesKeyboardShortcut = handlesKeyboardShortcut
    self.selectionStabilizationDelays = selectionStabilizationDelays
    self.shortcutRegistrar = shortcutRegistrar
    self.hostApplicationBundleIdentifier = hostApplicationBundleIdentifier
    self.voiceOverEnabled = voiceOverEnabled
    self.mutationIsAllowed = mutationIsAllowed
    self.activateBear = activateBear
    self.marksAlwaysVisible = marksAlwaysVisible
    self.recentMarkDuration = recentMarkDuration
    self.reviewRevealDelay = reviewRevealDelay
    self.reviewExitDelay = reviewExitDelay
    self.hoverMenuDelay = hoverMenuDelay
  }

  isolated deinit {
    stop()
  }

  public func track(
    _ application: BearCorrectionApplication,
    alternatives: [String] = [],
    onFinished: (@MainActor @Sendable () -> Void)? = nil
  ) {
    trackWithResolution(
      application,
      alternatives: alternatives,
      onFirstVisible: nil,
      onInteractionLatency: nil,
      onResolution: nil,
      onFinished: onFinished
    )
  }

  public func trackWithResolution(
    _ application: BearCorrectionApplication,
    alternatives: [String] = [],
    onFirstVisible: (@MainActor @Sendable () -> Void)? = nil,
    onInteractionLatency: (
      @MainActor @Sendable (Duration) -> Void
    )? = nil,
    onResolution: (
      @MainActor @Sendable (BearAnnotationResolution) -> Void
    )? = nil,
    onFinished: (@MainActor @Sendable () -> Void)? = nil
  ) {
    trackWithResolutionCoordinatingEdits(
      application,
      alternatives: alternatives,
      onFirstVisible: onFirstVisible,
      onInteractionLatency: onInteractionLatency,
      onResolution: onResolution,
      onVerifiedEdit: nil,
      onFinished: onFinished
    )
  }

  func trackWithResolutionCoordinatingEdits(
    _ application: BearCorrectionApplication,
    alternatives: [String] = [],
    onFirstVisible: (@MainActor @Sendable () -> Void)? = nil,
    onInteractionLatency: (
      @MainActor @Sendable (Duration) -> Void
    )? = nil,
    onResolution: (
      @MainActor @Sendable (BearAnnotationResolution) -> Void
    )? = nil,
    onVerifiedEdit: (
      @MainActor @Sendable (BearAnnotationVerifiedEdit) -> Void
    )? = nil,
    onFinished: (@MainActor @Sendable () -> Void)? = nil
  ) {
    stop()
    self.application = application
    self.alternatives = alternatives
    self.onFirstVisible = onFirstVisible
    self.onInteractionLatency = onInteractionLatency
    self.onResolution = onResolution
    self.onVerifiedEdit = onVerifiedEdit
    self.onFinished = onFinished
    trackedCorrectionID = application.correction.id.uuidString
    lastResolvedRange = application.correctionAnchor?.correctionRange
    cachedFrontmostBundleIdentifier = frontmostBundleIdentifier()
    beginMarkPresentation()
    if !usesSharedLifecycle {
      installWorkspaceObservers()
    }
    if handlesKeyboardShortcut {
      registerKeyboardShortcut()
    }
    if !usesSharedLifecycle {
      restartInvalidationMonitor()
      startFallbackRefresh()
    }
    refresh(hideFirst: true)
    scheduleSelectionStabilization(for: application)
  }

  public func stop() {
    hideAnnotation(reason: "stop")
    application = nil
    refreshGeneration += 1
    refreshTask?.cancel()
    refreshTask = nil
    textChangeRefreshTask?.cancel()
    textChangeRefreshTask = nil
    pendingTextChangeMayInvalidateAnchor = false
    fallbackTask?.cancel()
    fallbackTask = nil
    interactionTask?.cancel()
    interactionTask = nil
    selectionStabilizationTask?.cancel()
    selectionStabilizationTask = nil
    recentMarkTask?.cancel()
    recentMarkTask = nil
    reviewRevealTask?.cancel()
    reviewRevealTask = nil
    reviewExitTask?.cancel()
    reviewExitTask = nil
    hoverMenuTask?.cancel()
    hoverMenuTask = nil
    invalidationMonitor.stop()
    removeWorkspaceObservers()
    unregisterKeyboardShortcut()
    alternatives = []
    onFirstVisible = nil
    onInteractionLatency = nil
    onResolution = nil
    onVerifiedEdit = nil
    onFinished = nil
    lastResolvedRange = nil
    cachedFrontmostBundleIdentifier = nil
    trackedCorrectionID = nil
    accessibilityInteractionIsActive = false
    pointerIsNearReview = false
    pointerIsOverMark = false
    hoverMenuWasPresented = false
    recentMarkIsVisible = true
    reviewIsVisible = false
    menuIsVisible = false
  }

  public func showMenu() {
    guard isBearFrontmost, let correctionID = trackedCorrectionID else {
      return
    }
    logger.notice(
      "Overlay menu opened id=\(correctionID, privacy: .public) range=\(self.lastResolvedRange?.location ?? -1, privacy: .public):\(self.lastResolvedRange?.length ?? 0, privacy: .public)"
    )
    presenter.showMenu()
  }

  func handlePointerMovement(to point: NSPoint) {
    guard application != nil, isBearFrontmost else {
      return
    }
    updateReviewIntent(isNear: presenter.containsReviewPoint(point))
    updateHoverMenuIntent(isOverMark: presenter.containsMarkPoint(point))
  }

  /// Performs the correction's primary reversible action without activating
  /// Typover or routing a follow-up key event through an AppKit menu.
  @discardableResult
  public func changeBack() -> Bool {
    guard
      mutationIsAllowed(),
      isBearFrontmost,
      application != nil,
      interactionTask == nil
    else {
      return false
    }
    perform(.changeBack)
    return true
  }

  private func refresh(
    hideFirst: Bool,
    finishIfInvalidated: Bool = false
  ) {
    guard let application else {
      hideAnnotation(reason: "missingApplication")
      return
    }
    if hideFirst {
      hideAnnotation(reason: "refresh")
    }
    guard isBearFrontmost else {
      hideAnnotation(reason: "notFrontmost")
      return
    }

    refreshGeneration += 1
    let generation = refreshGeneration
    refreshTask?.cancel()
    let adapter = adapter
    refreshTask = Task { [weak self] in
      let report = await BearAccessibilityOperationLane.shared.run {
        adapter.geometry(for: application)
      }
      guard !Task.isCancelled, let self,
        generation == self.refreshGeneration,
        self.isBearFrontmost
      else {
        return
      }
      self.present(
        report,
        finishIfInvalidated: finishIfInvalidated
      )
    }
  }

  private func present(
    _ report: BearCorrectionGeometryReport,
    finishIfInvalidated: Bool
  ) {
    if let resolvedRange = report.resolvedRange {
      lastResolvedRange = resolvedRange
    }
    guard
      let placements = BearAnnotationLayout.visiblePlacements(
        for: report,
        bearIsFrontmost: isBearFrontmost,
        displays: displays()
      )
    else {
      hideAnnotation(reason: report.status.rawValue)
      if report.status.endsTracking
        || (finishIfInvalidated && report.status.isInvalidatedAnchor)
      {
        finishTracking()
      }
      return
    }
    guard let application else {
      hideAnnotation(reason: "missingApplication")
      return
    }
    presenter.show(
      placements: placements,
      interaction: BearAnnotationInteraction(
        items: BearAnnotationMenuModel.items(
          for: application,
          alternatives: alternatives
        ),
        accessibilityLabel: BearAnnotationMenuModel.accessibilityLabel(
          for: application
        ),
        onMenuVisibilityChanged: { [weak self] isVisible in
          self?.setMenuVisible(isVisible)
        }
      ) { [weak self] action in
        self?.perform(action)
      }
    )
    updateMarkPresentation(animated: false)
    reportVisible(range: report.resolvedRange)
  }

  private func handle(
    _ event: BearAccessibilityInvalidationEvent
  ) {
    if event == .valueChanged || event == .selectionChanged {
      scheduleTextChangeRefresh(event)
      return
    }

    cancelTextChangeRefresh()
    let invalidatesGeometry = event != .selectionChanged
    refresh(
      hideFirst: invalidatesGeometry,
      finishIfInvalidated: event == .valueChanged
    )
    if event == .focusedElementChanged || event == .focusedWindowChanged {
      restartInvalidationMonitor()
    }
  }

  /// Transfers observer, workspace, and fallback ownership to a collection.
  /// This must be called before `trackWithResolution`.
  func useSharedLifecycle() {
    usesSharedLifecycle = true
  }

  public func handleSharedInvalidation(
    _ event: BearAccessibilityInvalidationEvent
  ) {
    guard usesSharedLifecycle else {
      return
    }
    handle(event)
  }

  public func refreshFromSharedFallback() {
    guard usesSharedLifecycle, textChangeRefreshTask == nil else {
      return
    }
    refresh(hideFirst: false)
  }

  private func scheduleTextChangeRefresh(
    _ event: BearAccessibilityInvalidationEvent
  ) {
    pendingTextChangeMayInvalidateAnchor =
      pendingTextChangeMayInvalidateAnchor || event == .valueChanged
    if event == .valueChanged {
      hideAnnotation(reason: "valueChanged")
    }
    refreshGeneration += 1
    refreshTask?.cancel()
    refreshTask = nil
    textChangeRefreshTask?.cancel()

    guard textChangeRefreshDelay != .zero else {
      let finishIfInvalidated = pendingTextChangeMayInvalidateAnchor
      pendingTextChangeMayInvalidateAnchor = false
      textChangeRefreshTask = nil
      refresh(
        hideFirst: false,
        finishIfInvalidated: finishIfInvalidated
      )
      return
    }

    let delay = textChangeRefreshDelay
    textChangeRefreshTask = Task { [weak self] in
      do {
        try await Task.sleep(for: delay)
      } catch {
        return
      }
      guard let self else {
        return
      }
      self.textChangeRefreshTask = nil
      let finishIfInvalidated = self.pendingTextChangeMayInvalidateAnchor
      self.pendingTextChangeMayInvalidateAnchor = false
      self.refresh(
        hideFirst: false,
        finishIfInvalidated: finishIfInvalidated
      )
    }
  }

  private func cancelTextChangeRefresh() {
    textChangeRefreshTask?.cancel()
    textChangeRefreshTask = nil
    pendingTextChangeMayInvalidateAnchor = false
  }

  private func restartInvalidationMonitor() {
    guard application != nil, isBearFrontmost else {
      invalidationMonitor.stop()
      return
    }
    invalidationMonitor.start { [weak self] event in
      self?.handle(event)
    }
  }

  private func startFallbackRefresh() {
    let interval = fallbackRefreshInterval
    fallbackTask = Task { [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: interval)
        } catch {
          return
        }
        guard let self,
          self.textChangeRefreshTask == nil,
          !self.accessibilityInteractionIsActive
        else {
          continue
        }
        self.refresh(hideFirst: false)
      }
    }
  }

  private func perform(_ action: BearAnnotationAction) {
    guard let application else {
      return
    }
    guard mutationIsAllowed() else {
      logger.notice(
        "Overlay mutation refused by the current Bear safety policy"
      )
      finishTracking()
      return
    }
    let actionName = switch action {
    case .changeBack: "changeBack"
    case .chooseAlternative: "chooseAlternative"
    }
    logger.notice(
      "Overlay action selected id=\(application.correction.id.uuidString, privacy: .public) action=\(actionName, privacy: .public)"
    )
    selectionStabilizationTask?.cancel()
    selectionStabilizationTask = nil
    hideAnnotation(reason: "interaction")
    refreshGeneration += 1
    refreshTask?.cancel()
    let adapter = adapter
    let interactionStartedAt = ContinuousClock().now
    let shouldRestoreBearActivation = accessibilityInteractionIsActive
    interactionTask?.cancel()
    interactionTask = Task { [weak self] in
      switch action {
      case .changeBack:
        let result = await BearAccessibilityOperationLane.shared.run {
          adapter.changeBack(application)
        }
        guard !Task.isCancelled, let self,
          self.application == application
        else {
          return
        }
        switch result.report.status {
        case .restored, .alreadyRestored:
          self.onInteractionLatency?(
            interactionStartedAt.duration(to: ContinuousClock().now)
          )
          self.onResolution?(.changedBack)
          if result.report.writeOccurred,
            let matchedRange = result.report.matchedRange
          {
            self.onVerifiedEdit?(
              BearAnnotationVerifiedEdit(
                replacedRange: matchedRange,
                replacementLength: application.correction.original.utf16.count
              )
            )
          }
          if result.report.writeOccurred,
            let anchor = application.correctionAnchor,
            let desiredSelection = result.report.selectionAfter
          {
            await self.stabilizeSelection(
              BearCorrectionSelectionStabilizationRequest(
                anchor: anchor,
                expectedText: application.correction.original,
                desiredSelection: desiredSelection,
                additionalTransientSelections: [
                  application.correctionAnchor.map {
                    AccessibilityTextRange(
                      location: $0.correctionRange.location
                        + $0.correctionRange.length,
                      length: 0
                    )
                  },
                  result.report.matchedRange.map {
                    AccessibilityTextRange(
                      location: $0.location + $0.length,
                      length: 0
                    )
                  },
                ].compactMap { $0 }
              )
            )
          }
          self.finishTracking()
        case .superseded, .invalidated:
          self.finishTracking()
        default:
          self.refresh(hideFirst: true)
        }
        self.restoreBearActivationIfNeeded(shouldRestoreBearActivation)

      case .chooseAlternative(let replacement):
        let result = await BearAccessibilityOperationLane.shared.run {
          adapter.chooseAlternative(replacement, for: application)
        }
        guard !Task.isCancelled, let self,
          self.application == application
        else {
          return
        }
        if let updatedApplication = result.application {
          self.onInteractionLatency?(
            interactionStartedAt.duration(to: ContinuousClock().now)
          )
          self.onResolution?(.choseAlternative(replacement))
          if result.report.writeOccurred,
            let matchedRange = result.report.matchedRange
          {
            self.onVerifiedEdit?(
              BearAnnotationVerifiedEdit(
                replacedRange: matchedRange,
                replacementLength: replacement.utf16.count
              )
            )
          }
          self.alternatives.insert(
            application.correction.replacement,
            at: 0
          )
          self.application = updatedApplication
          if !self.usesSharedLifecycle {
            self.restartInvalidationMonitor()
          }
          self.refresh(hideFirst: true)
          self.scheduleSelectionStabilization(for: updatedApplication)
        } else {
          switch result.report.status {
          case .superseded, .invalidated:
            self.finishTracking()
          default:
            self.refresh(hideFirst: true)
          }
        }
        self.restoreBearActivationIfNeeded(shouldRestoreBearActivation)
      }
    }
  }

  public func applyVerifiedEdit(_ edit: BearAnnotationVerifiedEdit) async {
    await applyVerifiedEdits([edit])
  }

  /// Applies a burst of already-verified sibling edits with one final AX
  /// re-anchor. Transforming the range is deterministic; querying Bear after
  /// every sibling mutation only creates transient stale-anchor windows.
  public func applyVerifiedEdits(
    _ edits: [BearAnnotationVerifiedEdit]
  ) async {
    guard
      let application,
      var transformedRange = lastResolvedRange
        ?? application.correctionAnchor?.correctionRange
    else {
      finishTracking()
      return
    }
    for edit in edits {
      guard let nextRange = edit.transformedRange(for: transformedRange) else {
        finishTracking()
        return
      }
      transformedRange = nextRange
    }

    // Keep the last verified placement visible while the serialized AX lane
    // refreshes this controller's anchor. Hiding here makes a burst appear to
    // shed overlays in re-anchor order even though their exact ranges remain
    // valid. A failed re-anchor still ends tracking and hides the presenter.
    cancelTextChangeRefresh()
    refreshGeneration += 1
    refreshTask?.cancel()
    refreshTask = nil
    lastResolvedRange = transformedRange

    let adapter = adapter
    let finalRange = transformedRange
    let result = await BearAccessibilityOperationLane.shared.run {
      adapter.reanchor(application, at: finalRange)
    }
    guard !Task.isCancelled, self.application == application else {
      return
    }
    guard let updatedApplication = result.application else {
      finishTracking()
      return
    }
    self.application = updatedApplication
    lastResolvedRange = finalRange
    if !usesSharedLifecycle {
      restartInvalidationMonitor()
    }
    refresh(hideFirst: false)
  }

  private func scheduleSelectionStabilization(
    for application: BearCorrectionApplication
  ) {
    guard
      let anchor = application.correctionAnchor,
      let desiredSelection = application.report.selectionAfter
    else {
      return
    }
    selectionStabilizationTask?.cancel()
    let request = BearCorrectionSelectionStabilizationRequest(
      anchor: anchor,
      expectedText: application.correction.replacement,
      desiredSelection: desiredSelection,
      additionalTransientSelections: [
        application.report.targetRange,
        application.report.replacementRange,
      ].compactMap { range in
        range.map {
          AccessibilityTextRange(
            location: $0.location + $0.length,
            length: 0
          )
        }
      }
    )
    selectionStabilizationTask = Task { [weak self] in
      guard let self else { return }
      await self.stabilizeSelection(request)
    }
  }

  private func stabilizeSelection(
    _ request: BearCorrectionSelectionStabilizationRequest
  ) async {
    let adapter = adapter
    for delay in selectionStabilizationDelays {
      do {
        try await Task.sleep(for: delay)
      } catch {
        return
      }
      let status = await BearAccessibilityOperationLane.shared.run {
        adapter.stabilizeSelection(request)
      }
      if status == .userMovedSelection || status == .staleAnchor {
        return
      }
    }
  }

  private func registerKeyboardShortcut() {
    guard shortcutToken == nil else {
      return
    }
    shortcutToken = shortcutRegistrar.register { [weak self] in
      self?.changeBack()
    }
  }

  private func unregisterKeyboardShortcut() {
    if let shortcutToken {
      shortcutRegistrar.unregister(shortcutToken)
      self.shortcutToken = nil
    }
  }

  private func installWorkspaceObservers() {
    let center = NSWorkspace.shared.notificationCenter
    let names: [Notification.Name] = [
      NSWorkspace.didActivateApplicationNotification,
      NSWorkspace.didHideApplicationNotification,
      NSWorkspace.didTerminateApplicationNotification,
    ]
    workspaceObservers = names.map { name in
      center.addObserver(
        forName: name,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        let name = notification.name
        let bundleIdentifier =
          (notification.userInfo?[NSWorkspace.applicationUserInfoKey]
          as? NSRunningApplication)?.bundleIdentifier
        Task { @MainActor in
          self?.handleWorkspaceApplicationEvent(
            name: name,
            bundleIdentifier: bundleIdentifier
          )
        }
      }
    }
  }

  func handleWorkspaceApplicationEvent(
    name: Notification.Name,
    bundleIdentifier: String?
  ) {
    if name == NSWorkspace.didTerminateApplicationNotification,
      bundleIdentifier == BearAccessibilityProbe.bearBundleIdentifier
    {
      accessibilityInteractionIsActive = false
      finishTracking()
      return
    }

    if name == NSWorkspace.didActivateApplicationNotification {
      cachedFrontmostBundleIdentifier = bundleIdentifier
      if bundleIdentifier == hostApplicationBundleIdentifier,
        voiceOverEnabled()
      {
        accessibilityInteractionIsActive = true
        cancelTextChangeRefresh()
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        if !usesSharedLifecycle {
          invalidationMonitor.stop()
        }
        return
      }
      accessibilityInteractionIsActive = false
    } else if name == NSWorkspace.didHideApplicationNotification,
      bundleIdentifier == BearAccessibilityProbe.bearBundleIdentifier
    {
      cachedFrontmostBundleIdentifier = nil
      accessibilityInteractionIsActive = false
    } else {
      return
    }

    hideAnnotation(reason: "workspaceActivation")
    refreshGeneration += 1
    refreshTask?.cancel()
    if isBearFrontmost {
      if !usesSharedLifecycle {
        restartInvalidationMonitor()
      }
      refresh(hideFirst: false)
    } else {
      selectionStabilizationTask?.cancel()
      selectionStabilizationTask = nil
      if !usesSharedLifecycle {
        invalidationMonitor.stop()
      }
    }
  }

  private func removeWorkspaceObservers() {
    let center = NSWorkspace.shared.notificationCenter
    for observer in workspaceObservers {
      center.removeObserver(observer)
    }
    workspaceObservers = []
  }

  private func finishTracking() {
    let onFinished = onFinished
    stop()
    onFinished?()
  }

  private func beginMarkPresentation() {
    recentMarkTask?.cancel()
    reviewRevealTask?.cancel()
    reviewExitTask?.cancel()
    hoverMenuTask?.cancel()
    recentMarkIsVisible = true
    reviewIsVisible = false
    menuIsVisible = false
    pointerIsNearReview = false
    pointerIsOverMark = false
    hoverMenuWasPresented = false
    presenter.setMarkVisible(true, animated: false)

    let duration = recentMarkDuration
    recentMarkTask = Task { [weak self] in
      do {
        try await Task.sleep(for: duration)
      } catch {
        return
      }
      guard let self else { return }
      self.recentMarkTask = nil
      self.recentMarkIsVisible = false
      self.updateMarkPresentation(animated: true)
    }
  }

  private func updateReviewIntent(isNear: Bool) {
    pointerIsNearReview = isNear
    if isNear {
      reviewExitTask?.cancel()
      reviewExitTask = nil
      guard !reviewIsVisible, reviewRevealTask == nil else {
        return
      }
      let delay = reviewRevealDelay
      reviewRevealTask = Task { [weak self] in
        do {
          try await Task.sleep(for: delay)
        } catch {
          return
        }
        guard let self, self.pointerIsNearReview else { return }
        self.reviewRevealTask = nil
        self.reviewIsVisible = true
        self.updateMarkPresentation(animated: true)
      }
      return
    }

    reviewRevealTask?.cancel()
    reviewRevealTask = nil
    guard reviewIsVisible, reviewExitTask == nil else {
      return
    }
    let delay = reviewExitDelay
    reviewExitTask = Task { [weak self] in
      do {
        try await Task.sleep(for: delay)
      } catch {
        return
      }
      guard let self, !self.pointerIsNearReview else { return }
      self.reviewExitTask = nil
      self.reviewIsVisible = false
      self.updateMarkPresentation(animated: true)
    }
  }

  private func updateHoverMenuIntent(isOverMark: Bool) {
    pointerIsOverMark = isOverMark
    guard isOverMark else {
      hoverMenuTask?.cancel()
      hoverMenuTask = nil
      hoverMenuWasPresented = false
      return
    }
    guard !hoverMenuWasPresented, hoverMenuTask == nil else {
      return
    }
    let delay = hoverMenuDelay
    hoverMenuTask = Task { [weak self] in
      do {
        try await Task.sleep(for: delay)
      } catch {
        return
      }
      self?.hoverMenuTask = nil
      guard
        let self,
        self.pointerIsOverMark,
        self.isMarkVisible,
        self.isBearFrontmost
      else {
        return
      }
      self.hoverMenuWasPresented = true
      self.showMenu()
    }
  }

  private func setMenuVisible(_ visible: Bool) {
    menuIsVisible = visible
    if visible {
      reviewExitTask?.cancel()
      reviewExitTask = nil
    }
    updateMarkPresentation(animated: true)
  }

  private func updateMarkPresentation(animated: Bool) {
    presenter.setMarkVisible(isMarkVisible, animated: animated)
  }

  private var isMarkVisible: Bool {
    marksAlwaysVisible()
      || recentMarkIsVisible
      || reviewIsVisible
      || menuIsVisible
  }

  private func reportVisible(range: AccessibilityTextRange?) {
    guard !reportedVisible, let correctionID = trackedCorrectionID else {
      return
    }
    reportedVisible = true
    let onFirstVisible = onFirstVisible
    self.onFirstVisible = nil
    onFirstVisible?()
    logger.notice(
      "Overlay visible id=\(correctionID, privacy: .public) range=\(range?.location ?? -1, privacy: .public):\(range?.length ?? 0, privacy: .public)"
    )
  }

  private func hideAnnotation(reason: String) {
    presenter.hide()
    guard reportedVisible, let correctionID = trackedCorrectionID else {
      return
    }
    reportedVisible = false
    logger.notice(
      "Overlay hidden id=\(correctionID, privacy: .public) reason=\(reason, privacy: .public)"
    )
  }

  private var isBearFrontmost: Bool {
    cachedFrontmostBundleIdentifier
      == BearAccessibilityProbe.bearBundleIdentifier
  }

  private func restoreBearActivationIfNeeded(_ needed: Bool) {
    guard needed else {
      return
    }
    accessibilityInteractionIsActive = false
    let activateBear = activateBear
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(150))
      activateBear()
    }
  }

  public static func currentDisplays() -> [BearOverlayDisplay] {
    NSScreen.screens.compactMap { screen in
      guard
        let screenNumber = screen.deviceDescription[
          NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber
      else {
        return nil
      }
      let accessibilityFrame = CGDisplayBounds(
        CGDirectDisplayID(screenNumber.uint32Value)
      )
      return BearOverlayDisplay(
        accessibilityFrame: AccessibilityBounds(
          x: accessibilityFrame.minX,
          y: accessibilityFrame.minY,
          width: accessibilityFrame.width,
          height: accessibilityFrame.height
        ),
        appKitFrame: AccessibilityBounds(
          x: screen.frame.minX,
          y: screen.frame.minY,
          width: screen.frame.width,
          height: screen.frame.height
        )
      )
    }
  }
}

extension BearCorrectionGeometryStatus {
  fileprivate var endsTracking: Bool {
    switch self {
    case .superseded, .accessibilityPermissionRequired, .bearNotRunning:
      true
    case .available, .offscreen, .staleAnchor, .ambiguousAnchor,
      .focusedEditorUnavailable, .characterCountUnavailable,
      .visibleRangeUnavailable, .contextUnavailable, .boundsUnsupported,
      .boundsQueryFailed, .invalidBounds:
      false
    }
  }

  fileprivate var isInvalidatedAnchor: Bool {
    self == .staleAnchor || self == .ambiguousAnchor
  }
}
