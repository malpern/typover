import AppKit
import TypoverAccessibility
import TypoverBearAdapter

public protocol BearCorrectionGeometryResolving: Sendable {
  func geometry(
    for application: BearCorrectionApplication
  ) -> BearCorrectionGeometryReport
}

extension BearCorrectionAdapter: BearCorrectionGeometryResolving {}

@MainActor
public final class BearAnnotationOverlayController {
  public static let fallbackRefreshInterval = Duration.milliseconds(125)

  private let adapter: any BearCorrectionGeometryResolving
  private let presenter: any BearAnnotationPresenting
  private let invalidationMonitor:
    any BearAccessibilityInvalidationObserving
  private let frontmostBundleIdentifier: @MainActor @Sendable () -> String?
  private let displays: @MainActor @Sendable () -> [BearOverlayDisplay]
  private let fallbackRefreshInterval: Duration

  private var application: BearCorrectionApplication?
  private var refreshGeneration = 0
  private var refreshTask: Task<Void, Never>?
  private var fallbackTask: Task<Void, Never>?
  private var workspaceObservers: [NSObjectProtocol] = []

  public init(
    adapter: any BearCorrectionGeometryResolving = BearCorrectionAdapter(),
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
      BearAnnotationOverlayController.fallbackRefreshInterval
  ) {
    self.adapter = adapter
    self.presenter = presenter
    self.invalidationMonitor = invalidationMonitor
    self.frontmostBundleIdentifier = frontmostBundleIdentifier
    self.displays = displays
    self.fallbackRefreshInterval = fallbackRefreshInterval
  }

  isolated deinit {
    stop()
  }

  public func track(_ application: BearCorrectionApplication) {
    stop()
    self.application = application
    installWorkspaceObservers()
    restartInvalidationMonitor()
    startFallbackRefresh()
    refresh(hideFirst: true)
  }

  public func stop() {
    application = nil
    refreshGeneration += 1
    refreshTask?.cancel()
    refreshTask = nil
    fallbackTask?.cancel()
    fallbackTask = nil
    invalidationMonitor.stop()
    removeWorkspaceObservers()
    presenter.hide()
  }

  private func refresh(hideFirst: Bool) {
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
      self.present(report)
    }
  }

  private func present(_ report: BearCorrectionGeometryReport) {
    guard
      let placements = BearAnnotationLayout.visiblePlacements(
        for: report,
        bearIsFrontmost: isBearFrontmost,
        displays: displays()
      )
    else {
      presenter.hide()
      return
    }
    presenter.show(placements: placements)
  }

  private func handle(
    _ event: BearAccessibilityInvalidationEvent
  ) {
    let invalidatesGeometry = event != .selectionChanged
    refresh(hideFirst: invalidatesGeometry)
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
