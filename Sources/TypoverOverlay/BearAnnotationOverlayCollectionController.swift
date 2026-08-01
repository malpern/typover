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
  private var entries: [Entry] = []
  private var shortcutToken: UUID?
  private var fallbackTask: Task<Void, Never>?
  private var workspaceObservers: [NSObjectProtocol] = []
  private var verifiedEditTask: Task<Void, Never>?
  private var isProcessingVerifiedEdits = false
  private var suppressedInvalidationDuringVerifiedEdits = false
  private var pendingVerifiedEdits: [PendingVerifiedEdit] = []

  public convenience init(
    adapter: any BearCorrectionServicing = BearCorrectionAdapter(),
    maximumTrackedCorrections: Int =
      BearAnnotationOverlayCollectionController
      .defaultMaximumTrackedCorrections
  ) {
    self.init(
      maximumTrackedCorrections: maximumTrackedCorrections,
      fallbackRefreshInterval: .seconds(2),
      verifiedEditBatchDelay: .milliseconds(120)
    ) {
      BearAnnotationOverlayController(
        adapter: adapter,
        fallbackRefreshInterval: .seconds(2),
        textChangeRefreshDelay: .milliseconds(180),
        handlesKeyboardShortcut: false
      )
    }
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
    entries.remove(at: index).controller.stop()
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
        for entry in self.entries {
          entry.controller.refreshFromSharedFallback()
        }
      }
    }
  }

  private func stopSharedLifecycle() {
    fallbackTask?.cancel()
    fallbackTask = nil
    for observer in workspaceObservers {
      workspaceNotificationCenter.removeObserver(observer)
    }
    workspaceObservers = []
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

  private func handleWorkspaceApplicationEvent(
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
  }
}
