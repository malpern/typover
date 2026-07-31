import AppKit
import TypoverBearAdapter

@MainActor
public final class BearAnnotationOverlayCollectionController {
  public static let defaultMaximumTrackedCorrections = 24

  private struct Entry {
    let correctionID: String
    let controller: BearAnnotationOverlayController
  }

  private let maximumTrackedCorrections: Int
  private let controllerFactory: @MainActor () -> BearAnnotationOverlayController
  private var entries: [Entry] = []
  private var keyboardMonitor: Any?
  private var verifiedEditTask: Task<Void, Never>?

  public convenience init(
    adapter: any BearCorrectionServicing = BearCorrectionAdapter(),
    maximumTrackedCorrections: Int =
      BearAnnotationOverlayCollectionController
      .defaultMaximumTrackedCorrections
  ) {
    self.init(
      maximumTrackedCorrections: maximumTrackedCorrections
    ) {
      BearAnnotationOverlayController(
        adapter: adapter,
        fallbackRefreshInterval: .seconds(2),
        textChangeRefreshDelay: .milliseconds(180),
        handlesKeyboardShortcut: false
      )
    }
  }

  public init(
    maximumTrackedCorrections: Int,
    controllerFactory:
      @escaping @MainActor () -> BearAnnotationOverlayController
  ) {
    self.maximumTrackedCorrections = max(
      1,
      maximumTrackedCorrections
    )
    self.controllerFactory = controllerFactory
  }

  isolated deinit {
    stop()
  }

  public var trackedCorrectionCount: Int {
    entries.count
  }

  public func trackWithResolution(
    _ application: BearCorrectionApplication,
    alternatives: [String] = [],
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
    entries.append(
      Entry(correctionID: correctionID, controller: controller)
    )
    installKeyboardMonitorIfNeeded()
    controller.trackWithResolutionCoordinatingEdits(
      application,
      alternatives: alternatives,
      onInteractionLatency: onInteractionLatency,
      onResolution: onResolution,
      onVerifiedEdit: { [weak self, weak controller] edit in
        guard let self, let controller else {
          return
        }
        self.applyVerifiedEdit(edit, excluding: controller)
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

  private func applyVerifiedEdit(
    _ edit: BearAnnotationVerifiedEdit,
    excluding source: BearAnnotationOverlayController
  ) {
    verifiedEditTask?.cancel()
    let siblingControllers = entries.compactMap { entry in
      entry.controller === source ? nil : entry.controller
    }
    verifiedEditTask = Task { [weak self] in
      for controller in siblingControllers {
        guard !Task.isCancelled else {
          return
        }
        await controller.applyVerifiedEdit(edit)
      }
      self?.verifiedEditTask = nil
    }
  }

  public func stop() {
    verifiedEditTask?.cancel()
    verifiedEditTask = nil
    let controllers = entries.map(\.controller)
    entries = []
    for controller in controllers {
      controller.stop()
    }
    removeKeyboardMonitor()
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
    removeKeyboardMonitorIfEmpty()
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
    removeKeyboardMonitorIfEmpty()
  }

  private func installKeyboardMonitorIfNeeded() {
    guard keyboardMonitor == nil else {
      return
    }
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
        self?.entries.last?.controller.showMenu()
      }
    }
  }

  private func removeKeyboardMonitorIfEmpty() {
    if entries.isEmpty {
      removeKeyboardMonitor()
    }
  }

  private func removeKeyboardMonitor() {
    if let keyboardMonitor {
      NSEvent.removeMonitor(keyboardMonitor)
      self.keyboardMonitor = nil
    }
  }
}
