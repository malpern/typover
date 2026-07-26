import AppKit
import TypoverAccessibility
import TypoverBearAdapter

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

  func stabilizeSelection(
    _ request: BearCorrectionSelectionStabilizationRequest
  ) -> BearCorrectionSelectionStabilizationStatus
}

extension BearCorrectionAdapter: BearCorrectionServicing {}

@MainActor
public final class BearAnnotationOverlayController {
  public static let fallbackRefreshInterval = Duration.milliseconds(125)

  private let adapter: any BearCorrectionServicing
  private let presenter: any BearAnnotationPresenting
  private let invalidationMonitor: any BearAccessibilityInvalidationObserving
  private let frontmostBundleIdentifier: @MainActor @Sendable () -> String?
  private let displays: @MainActor @Sendable () -> [BearOverlayDisplay]
  private let fallbackRefreshInterval: Duration
  private let selectionStabilizationDelays: [Duration]

  private var application: BearCorrectionApplication?
  private var refreshGeneration = 0
  private var refreshTask: Task<Void, Never>?
  private var fallbackTask: Task<Void, Never>?
  private var interactionTask: Task<Void, Never>?
  private var selectionStabilizationTask: Task<Void, Never>?
  private var workspaceObservers: [NSObjectProtocol] = []
  private var keyboardMonitor: Any?
  private var alternatives: [String] = []
  private var onFinished: (@MainActor @Sendable () -> Void)?

  public init(
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
    selectionStabilizationDelays: [Duration] = [
      .milliseconds(40),
      .milliseconds(180),
    ]
  ) {
    self.adapter = adapter
    self.presenter = presenter
    self.invalidationMonitor = invalidationMonitor
    self.frontmostBundleIdentifier = frontmostBundleIdentifier
    self.displays = displays
    self.fallbackRefreshInterval = fallbackRefreshInterval
    self.selectionStabilizationDelays = selectionStabilizationDelays
  }

  isolated deinit {
    stop()
  }

  public func track(
    _ application: BearCorrectionApplication,
    alternatives: [String] = [],
    onFinished: (@MainActor @Sendable () -> Void)? = nil
  ) {
    stop()
    self.application = application
    self.alternatives = alternatives
    self.onFinished = onFinished
    installWorkspaceObservers()
    installKeyboardMonitor()
    restartInvalidationMonitor()
    startFallbackRefresh()
    refresh(hideFirst: true)
    scheduleSelectionStabilization(for: application)
  }

  public func stop() {
    application = nil
    refreshGeneration += 1
    refreshTask?.cancel()
    refreshTask = nil
    fallbackTask?.cancel()
    fallbackTask = nil
    interactionTask?.cancel()
    interactionTask = nil
    selectionStabilizationTask?.cancel()
    selectionStabilizationTask = nil
    invalidationMonitor.stop()
    removeWorkspaceObservers()
    removeKeyboardMonitor()
    presenter.hide()
    alternatives = []
    onFinished = nil
  }

  private func refresh(
    hideFirst: Bool,
    finishIfInvalidated: Bool = false
  ) {
    guard let application else {
      presenter.hide()
      return
    }
    if hideFirst {
      presenter.hide()
    }
    guard isBearFrontmost else {
      presenter.hide()
      return
    }

    refreshGeneration += 1
    let generation = refreshGeneration
    refreshTask?.cancel()
    let adapter = adapter
    refreshTask = Task { [weak self] in
      let report = await Task.detached(priority: .userInitiated) {
        adapter.geometry(for: application)
      }.value
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
    guard
      let placements = BearAnnotationLayout.visiblePlacements(
        for: report,
        bearIsFrontmost: isBearFrontmost,
        displays: displays()
      )
    else {
      presenter.hide()
      if report.status.endsTracking
        || (finishIfInvalidated && report.status.isInvalidatedAnchor)
      {
        finishTracking()
      }
      return
    }
    guard let application else {
      presenter.hide()
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
        )
      ) { [weak self] action in
        self?.perform(action)
      }
    )
  }

  private func handle(
    _ event: BearAccessibilityInvalidationEvent
  ) {
    let invalidatesGeometry = event != .selectionChanged
    refresh(
      hideFirst: invalidatesGeometry,
      finishIfInvalidated: event == .valueChanged
    )
    if event == .focusedElementChanged || event == .focusedWindowChanged {
      restartInvalidationMonitor()
    }
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
        self?.refresh(hideFirst: false)
      }
    }
  }

  private func perform(_ action: BearAnnotationAction) {
    guard let application else {
      return
    }
    selectionStabilizationTask?.cancel()
    selectionStabilizationTask = nil
    presenter.hide()
    refreshGeneration += 1
    refreshTask?.cancel()
    let adapter = adapter
    interactionTask?.cancel()
    interactionTask = Task { [weak self] in
      switch action {
      case .changeBack:
        let result = await Task.detached(priority: .userInitiated) {
          adapter.changeBack(application)
        }.value
        guard !Task.isCancelled, let self,
          self.application == application
        else {
          return
        }
        switch result.report.status {
        case .restored, .alreadyRestored:
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

      case .chooseAlternative(let replacement):
        let result = await Task.detached(priority: .userInitiated) {
          adapter.chooseAlternative(replacement, for: application)
        }.value
        guard !Task.isCancelled, let self,
          self.application == application
        else {
          return
        }
        if let updatedApplication = result.application {
          self.alternatives.insert(
            application.correction.replacement,
            at: 0
          )
          self.application = updatedApplication
          self.restartInvalidationMonitor()
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
      }
    }
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
      let status = await Task.detached(priority: .userInitiated) {
        adapter.stabilizeSelection(request)
      }.value
      if status == .userMovedSelection || status == .staleAnchor {
        return
      }
    }
  }

  private func installKeyboardMonitor() {
    keyboardMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: .keyDown
    ) { [weak self] event in
      let modifiers = event.modifierFlags.intersection(
        .deviceIndependentFlagsMask
      )
      guard event.keyCode == 36,
        modifiers == [.control, .option, .command]
      else {
        return
      }
      Task { @MainActor in
        guard let self, self.isBearFrontmost else {
          return
        }
        self.presenter.showMenu()
      }
    }
  }

  private func removeKeyboardMonitor() {
    if let keyboardMonitor {
      NSEvent.removeMonitor(keyboardMonitor)
      self.keyboardMonitor = nil
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
      ) { [weak self] _ in
        Task { @MainActor in
          guard let self else { return }
          self.presenter.hide()
          self.refreshGeneration += 1
          self.refreshTask?.cancel()
          if self.isBearFrontmost {
            self.restartInvalidationMonitor()
            self.refresh(hideFirst: false)
          } else {
            self.selectionStabilizationTask?.cancel()
            self.selectionStabilizationTask = nil
            self.invalidationMonitor.stop()
          }
        }
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

  private var isBearFrontmost: Bool {
    frontmostBundleIdentifier()
      == BearAccessibilityProbe.bearBundleIdentifier
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
