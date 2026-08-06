import AppKit

public enum BearAnnotationMarkVisibility: Equatable, Sendable {
  case briefAndContextual
  case alwaysVisible
}

@MainActor
protocol BearAnnotationPointerMonitoring: AnyObject {
  @discardableResult
  func start(
    handler: @escaping @MainActor @Sendable (NSPoint) -> Void
  ) -> Bool

  func stop()
}

@MainActor
final class AppKitBearAnnotationPointerMonitor:
  BearAnnotationPointerMonitoring
{
  private var globalMonitor: Any?
  private var localMonitor: Any?
  private var handler: (@MainActor @Sendable (NSPoint) -> Void)?

  @discardableResult
  func start(
    handler: @escaping @MainActor @Sendable (NSPoint) -> Void
  ) -> Bool {
    stop()
    self.handler = handler
    globalMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: .mouseMoved
    ) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        self.handler?(NSEvent.mouseLocation)
      }
    }
    localMonitor = NSEvent.addLocalMonitorForEvents(
      matching: .mouseMoved
    ) { [weak self] event in
      Task { @MainActor in
        guard let self else { return }
        self.handler?(NSEvent.mouseLocation)
      }
      return event
    }
    return globalMonitor != nil || localMonitor != nil
  }

  func stop() {
    if let globalMonitor {
      NSEvent.removeMonitor(globalMonitor)
      self.globalMonitor = nil
    }
    if let localMonitor {
      NSEvent.removeMonitor(localMonitor)
      self.localMonitor = nil
    }
    handler = nil
  }
}
