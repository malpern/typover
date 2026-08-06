import AppKit
import TypoverAccessibility
import TypoverBearAdapter

@MainActor
public final class BearAnnotationOverlayCollectionController {
  public static let defaultMaximumTrackedCorrections = 24

  private struct Entry {
    let correctionID: String
    let userRecency: Date
    let correctionLocation: Int
    let controller: BearAnnotationOverlayController
  }

  private struct PendingVerifiedEdit {
    let edit: BearAnnotationVerifiedEdit
    let controllers: [BearAnnotationOverlayController]
  }

  private let maximumTrackedCorrections: Int
  private let controllerFactory: @MainActor () -> BearAnnotationOverlayController
  private let fallbackRefreshInterval: Duration
  private let verifiedEditBatchDelay: Duration
  private let workspaceNotificationCenter: NotificationCenter
  private let shortcutRegistrar: any BearAnnotationShortcutRegistering
  private let frontmostBundleIdentifier: @MainActor @Sendable () -> String?
  private let pointerMonitor: any BearAnnotationPointerMonitoring
  private let pointerReviewEnabled: @MainActor @Sendable () -> Bool
  private let pointerRevealDelay: Duration
  private let pointerExitDelay: Duration
  private var entries: [Entry] = []
  private var shortcutToken: UUID?
  private var fallbackTask: Task<Void, Never>?
  private var workspaceObservers: [NSObjectProtocol] = []
  private var verifiedEditTask: Task<Void, Never>?
  private var isProcessingVerifiedEdits = false
  private var suppressedInvalidationDuringVerifiedEdits = false
  private var pendingVerifiedEdits: [PendingVerifiedEdit] = []
  private var latestPointerLocation: NSPoint?
  private var pointerSampleTask: Task<Void, Never>?
  private var pointerRevealTask: Task<Void, Never>?
  private var pointerExitTask: Task<Void, Never>?
  private var contextuallyRevealedControllers: Set<ObjectIdentifier> = []
  private var isPointerMonitorRunning = false

  public convenience init(
    adapter: any BearCorrectionServicing = BearCorrectionAdapter(),
    markVisibility:
      @escaping @MainActor @Sendable () -> BearAnnotationMarkVisibility = {
        .briefAndContextual
      },
    maximumTrackedCorrections: Int =
      BearAnnotationOverlayCollectionController
      .defaultMaximumTrackedCorrections
  ) {
    self.init(
      maximumTrackedCorrections: maximumTrackedCorrections,
      fallbackRefreshInterval: .seconds(2),
      verifiedEditBatchDelay: .milliseconds(120),
      shortcutRegistrar: BearAnnotationShortcutCenter.shared,
      pointerReviewEnabled: {
        markVisibility() == .briefAndContextual
      },
      controllerFactory: {
        BearAnnotationOverlayController(
          adapter: adapter,
          fallbackRefreshInterval: .seconds(2),
          textChangeRefreshDelay: .milliseconds(180),
          handlesKeyboardShortcut: false,
          markVisibility: markVisibility
        )
      }
    )
  }

  public convenience init(
    maximumTrackedCorrections: Int,
    fallbackRefreshInterval: Duration = .seconds(2),
    verifiedEditBatchDelay: Duration = .milliseconds(120),
    workspaceNotificationCenter: NotificationCenter =
      NSWorkspace.shared.notificationCenter,
    controllerFactory:
      @escaping @MainActor () -> BearAnnotationOverlayController
  ) {
    self.init(
      maximumTrackedCorrections: maximumTrackedCorrections,
      fallbackRefreshInterval: fallbackRefreshInterval,
      verifiedEditBatchDelay: verifiedEditBatchDelay,
      workspaceNotificationCenter: workspaceNotificationCenter,
      shortcutRegistrar: BearAnnotationShortcutCenter.shared,
      controllerFactory: controllerFactory
    )
  }

  init(
    maximumTrackedCorrections: Int,
    fallbackRefreshInterval: Duration = .seconds(2),
    verifiedEditBatchDelay: Duration = .milliseconds(120),
    workspaceNotificationCenter: NotificationCenter =
      NSWorkspace.shared.notificationCenter,
    shortcutRegistrar: any BearAnnotationShortcutRegistering,
    pointerMonitor: any BearAnnotationPointerMonitoring =
      AppKitBearAnnotationPointerMonitor(),
    pointerReviewEnabled: @escaping @MainActor @Sendable () -> Bool = {
      true
    },
    pointerRevealDelay: Duration = .milliseconds(220),
    pointerExitDelay: Duration = .milliseconds(280),
    frontmostBundleIdentifier: @escaping @MainActor @Sendable () -> String? = {
      NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    },
    controllerFactory:
      @escaping @MainActor () -> BearAnnotationOverlayController
  ) {
    self.maximumTrackedCorrections = max(
      1,
      maximumTrackedCorrections
    )
    self.fallbackRefreshInterval = fallbackRefreshInterval
    self.verifiedEditBatchDelay = verifiedEditBatchDelay
    self.workspaceNotificationCenter = workspaceNotificationCenter
    self.shortcutRegistrar = shortcutRegistrar
    self.pointerMonitor = pointerMonitor
    self.pointerReviewEnabled = pointerReviewEnabled
    self.pointerRevealDelay = pointerRevealDelay
    self.pointerExitDelay = pointerExitDelay
    self.frontmostBundleIdentifier = frontmostBundleIdentifier
    self.controllerFactory = controllerFactory
  }

  isolated deinit {
    stop()
  }

  public var trackedCorrectionCount: Int {
    entries.count
  }

  public func recordVerifiedEdit(_ edit: BearAnnotationVerifiedEdit) {
    enqueueVerifiedEdit(edit, excluding: nil)
  }

  public func trackWithResolution(
    _ application: BearCorrectionApplication,
    alternatives: [String] = [],
    userRecency: Date? = nil,
    onFirstVisible: (@MainActor @Sendable () -> Void)? = nil,
    onInteractionLatency: (
      @MainActor @Sendable (Duration) -> Void
    )? = nil,
    onResolution: (
      @MainActor @Sendable (BearAnnotationResolution) -> Void
    )? = nil,
    onFinished: (@MainActor @Sendable () -> Void)? = nil
  ) {
    let correctionID = application.correction.id.uuidString
    removeEntry(correctionID: correctionID)
    pruneOldestIfNeeded()

    let controller = controllerFactory()
    controller.useSharedLifecycle()
    entries.append(
      Entry(
        correctionID: correctionID,
        userRecency: userRecency ?? application.correction.createdAt,
        correctionLocation: application.report.targetRange.location,
        controller: controller
      )
    )
    startSharedLifecycleIfNeeded()
    registerKeyboardShortcutIfNeeded()
    controller.trackWithResolutionCoordinatingEdits(
      application,
      alternatives: alternatives,
      onFirstVisible: onFirstVisible,
      onInteractionLatency: onInteractionLatency,
      onResolution: onResolution,
      onVerifiedEdit: { [weak self, weak controller] edit in
        guard let self, let controller else {
          return
        }
        self.enqueueVerifiedEdit(edit, excluding: controller)
      },
      onFinished: { [weak self, weak controller] in
        guard let self, let controller else {
          return
        }
        self.removeEntry(controller: controller)
        onFinished?()
      }
    )
  }

  private func enqueueVerifiedEdit(
    _ edit: BearAnnotationVerifiedEdit,
    excluding source: BearAnnotationOverlayController?
  ) {
    let controllers =
      entries
      .filter { $0.controller !== source }
      .map(\.controller)
    pendingVerifiedEdits.append(
      PendingVerifiedEdit(
        edit: edit,
        controllers: controllers
      )
    )
    guard !isProcessingVerifiedEdits else {
      return
    }
    verifiedEditTask?.cancel()
    let delay = verifiedEditBatchDelay
    verifiedEditTask = Task { [weak self] in
      do {
        try await Task.sleep(for: delay)
      } catch {
        return
      }
      guard let self else {
        return
      }
      await self.processPendingVerifiedEdits()
    }
  }

  private func processPendingVerifiedEdits() async {
    guard !isProcessingVerifiedEdits, !pendingVerifiedEdits.isEmpty else {
      verifiedEditTask = nil
      return
    }
    verifiedEditTask = nil
    isProcessingVerifiedEdits = true
    let pending = pendingVerifiedEdits
    pendingVerifiedEdits = []

    var controllerOrder: [BearAnnotationOverlayController] = []
    var editsByController: [ObjectIdentifier: [BearAnnotationVerifiedEdit]] = [:]
    for item in pending {
      for controller in item.controllers {
        let identifier = ObjectIdentifier(controller)
        if editsByController[identifier] == nil {
          controllerOrder.append(controller)
          editsByController[identifier] = []
        }
        editsByController[identifier, default: []].append(item.edit)
      }
    }

    for controller in controllerOrder {
      guard entries.contains(where: { $0.controller === controller }) else {
        continue
      }
      let edits = editsByController[ObjectIdentifier(controller)] ?? []
      await controller.applyVerifiedEdits(edits)
    }
    isProcessingVerifiedEdits = false

    if suppressedInvalidationDuringVerifiedEdits {
      suppressedInvalidationDuringVerifiedEdits = false
      for entry in entries {
        entry.controller.refreshFromSharedFallback()
      }
    }
    if !pendingVerifiedEdits.isEmpty {
      schedulePendingVerifiedEdits()
    }
  }

  private func schedulePendingVerifiedEdits() {
    guard verifiedEditTask == nil, !isProcessingVerifiedEdits else {
      return
    }
    let delay = verifiedEditBatchDelay
    verifiedEditTask = Task { [weak self] in
      do {
        try await Task.sleep(for: delay)
      } catch {
        return
      }
      await self?.processPendingVerifiedEdits()
    }
  }

  public func stop() {
    verifiedEditTask?.cancel()
    verifiedEditTask = nil
    isProcessingVerifiedEdits = false
    suppressedInvalidationDuringVerifiedEdits = false
    pendingVerifiedEdits = []
    stopPointerReview()
    let controllers = entries.map(\.controller)
    entries = []
    for controller in controllers {
      controller.stop()
    }
    stopSharedLifecycle()
    unregisterKeyboardShortcut()
  }

  /// Receives events from the automatic correction coordinator's single Bear
  /// AX observer. A focused editor/window change ends the current annotation
  /// session because Bear does not expose a stable note identity through AX.
  public func handleInvalidation(
    _ event: BearAccessibilityInvalidationEvent
  ) {
    if event == .focusedElementChanged || event == .focusedWindowChanged {
      stop()
      return
    }
    if event == .valueChanged || event == .selectionChanged,
      verifiedEditTask != nil || isProcessingVerifiedEdits
        || !pendingVerifiedEdits.isEmpty
    {
      suppressedInvalidationDuringVerifiedEdits = true
      return
    }
    for entry in entries {
      entry.controller.handleSharedInvalidation(event)
    }
  }

  private func pruneOldestIfNeeded() {
    while entries.count >= maximumTrackedCorrections {
      let entry = entries.removeFirst()
      contextuallyRevealedControllers.remove(
        ObjectIdentifier(entry.controller)
      )
      entry.controller.stop()
    }
  }

  private func removeEntry(correctionID: String) {
    guard
      let index = entries.firstIndex(where: {
        $0.correctionID == correctionID
      })
    else {
      return
    }
    let controller = entries.remove(at: index).controller
    contextuallyRevealedControllers.remove(ObjectIdentifier(controller))
    controller.stop()
    unregisterKeyboardShortcutIfEmpty()
  }

  private func removeEntry(
    controller: BearAnnotationOverlayController
  ) {
    guard
      let index = entries.firstIndex(where: {
        $0.controller === controller
      })
    else {
      return
    }
    entries.remove(at: index)
    contextuallyRevealedControllers.remove(ObjectIdentifier(controller))
    unregisterKeyboardShortcutIfEmpty()
  }

  private func registerKeyboardShortcutIfNeeded() {
    guard shortcutToken == nil else {
      return
    }
    shortcutToken = shortcutRegistrar.register { [weak self] in
      self?.changeBackMostRecentCorrection()
    }
  }

  private func changeBackMostRecentCorrection() {
    let newestFirst = entries.sorted { lhs, rhs in
      if lhs.userRecency != rhs.userRecency {
        return lhs.userRecency > rhs.userRecency
      }
      return lhs.correctionLocation > rhs.correctionLocation
    }
    for entry in newestFirst {
      if entry.controller.changeBack() {
        return
      }
    }
  }

  private func unregisterKeyboardShortcutIfEmpty() {
    if entries.isEmpty {
      stopSharedLifecycle()
      unregisterKeyboardShortcut()
    }
  }

  private func unregisterKeyboardShortcut() {
    if let shortcutToken {
      shortcutRegistrar.unregister(shortcutToken)
      self.shortcutToken = nil
    }
  }

  private func startSharedLifecycleIfNeeded() {
    guard fallbackTask == nil, !entries.isEmpty else {
      return
    }
    installWorkspaceObservers()
    synchronizePointerMonitoring()
    let interval = fallbackRefreshInterval
    fallbackTask = Task { [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: interval)
        } catch {
          return
        }
        guard let self else {
          return
        }
        self.synchronizePointerMonitoring()
        guard
          self.frontmostBundleIdentifier()
            == BearAccessibilityProbe.bearBundleIdentifier
        else {
          continue
        }
        for entry in self.entries {
          entry.controller.refreshFromSharedFallback()
        }
      }
    }
  }

  private func stopSharedLifecycle() {
    pauseFallbackRefresh()
    stopPointerReview()
    for observer in workspaceObservers {
      workspaceNotificationCenter.removeObserver(observer)
    }
    workspaceObservers = []
  }

  private func pauseFallbackRefresh() {
    fallbackTask?.cancel()
    fallbackTask = nil
  }

  private func handlePointerLocation(_ point: NSPoint) {
    latestPointerLocation = point
    guard pointerSampleTask == nil else {
      return
    }
    pointerSampleTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .milliseconds(40))
      } catch {
        return
      }
      guard let self else { return }
      self.pointerSampleTask = nil
      self.processLatestPointerLocation()
    }
  }

  private func synchronizePointerMonitoring() {
    if pointerReviewEnabled() {
      guard !isPointerMonitorRunning else { return }
      isPointerMonitorRunning = pointerMonitor.start { [weak self] point in
        self?.handlePointerLocation(point)
      }
    } else if isPointerMonitorRunning {
      stopPointerReview()
    }
  }

  private func processLatestPointerLocation() {
    guard
      frontmostBundleIdentifier()
        == BearAccessibilityProbe.bearBundleIdentifier,
      let latestPointerLocation
    else {
      schedulePointerExit()
      return
    }
    let candidates = Set(
      entries.compactMap { entry -> ObjectIdentifier? in
        entry.controller.isPointerNearCachedPlacement(
          latestPointerLocation
        )
          ? ObjectIdentifier(entry.controller)
          : nil
      }
    )
    guard !candidates.isEmpty else {
      pointerRevealTask?.cancel()
      pointerRevealTask = nil
      schedulePointerExit()
      return
    }

    pointerExitTask?.cancel()
    pointerExitTask = nil
    guard candidates != contextuallyRevealedControllers else {
      return
    }
    pointerRevealTask?.cancel()
    let delay = pointerRevealDelay
    pointerRevealTask = Task { [weak self] in
      do {
        try await Task.sleep(for: delay)
      } catch {
        return
      }
      guard let self, let point = self.latestPointerLocation else {
        return
      }
      self.pointerRevealTask = nil
      let currentCandidates = Set(
        self.entries.compactMap { entry -> ObjectIdentifier? in
          entry.controller.isPointerNearCachedPlacement(point)
            ? ObjectIdentifier(entry.controller)
            : nil
        }
      )
      guard !currentCandidates.isEmpty else {
        self.schedulePointerExit()
        return
      }
      self.applyContextualReveal(to: currentCandidates)
    }
  }

  private func schedulePointerExit() {
    guard pointerExitTask == nil else {
      return
    }
    let delay = pointerExitDelay
    pointerExitTask = Task { [weak self] in
      do {
        try await Task.sleep(for: delay)
      } catch {
        return
      }
      guard let self else { return }
      self.pointerExitTask = nil
      self.applyContextualReveal(to: [])
    }
  }

  private func applyContextualReveal(
    to identifiers: Set<ObjectIdentifier>
  ) {
    contextuallyRevealedControllers = identifiers
    for entry in entries {
      entry.controller.setContextualReveal(
        identifiers.contains(ObjectIdentifier(entry.controller))
      )
    }
  }

  private func stopPointerReview() {
    pointerMonitor.stop()
    isPointerMonitorRunning = false
    pointerSampleTask?.cancel()
    pointerSampleTask = nil
    pointerRevealTask?.cancel()
    pointerRevealTask = nil
    pointerExitTask?.cancel()
    pointerExitTask = nil
    latestPointerLocation = nil
    applyContextualReveal(to: [])
  }

  private func installWorkspaceObservers() {
    guard workspaceObservers.isEmpty else {
      return
    }
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
      ) { [weak self] notification in
        let notificationName = notification.name
        let bundleIdentifier =
          (notification.userInfo?[NSWorkspace.applicationUserInfoKey]
          as? NSRunningApplication)?.bundleIdentifier
        Task { @MainActor in
          self?.handleWorkspaceApplicationEvent(
            name: notificationName,
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
      stop()
      return
    }
    for entry in entries {
      entry.controller.handleWorkspaceApplicationEvent(
        name: name,
        bundleIdentifier: bundleIdentifier
      )
    }
    if name == NSWorkspace.didActivateApplicationNotification {
      if bundleIdentifier == BearAccessibilityProbe.bearBundleIdentifier {
        startSharedLifecycleIfNeeded()
      } else {
        pauseFallbackRefresh()
        stopPointerReview()
      }
    } else if name == NSWorkspace.didHideApplicationNotification,
      bundleIdentifier == BearAccessibilityProbe.bearBundleIdentifier
    {
      pauseFallbackRefresh()
      stopPointerReview()
    }
  }
}
