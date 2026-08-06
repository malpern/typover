import AppKit

@MainActor
public protocol BearAnnotationPointerMonitoring: AnyObject {
  @discardableResult
  func start(
    handler: @escaping @MainActor @Sendable (NSPoint) -> Void
  ) -> Bool
  func stop()
}

@MainActor
public final class AppKitBearAnnotationPointerMonitor:
  BearAnnotationPointerMonitoring
{
  private var globalMonitor: Any?
  private var localMonitor: Any?

  public init() {}

  @discardableResult
  public func start(
    handler: @escaping @MainActor @Sendable (NSPoint) -> Void
  ) -> Bool {
    stop()
    globalMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.mouseMoved]
    ) { _ in
      Task { @MainActor in
        handler(NSEvent.mouseLocation)
      }
    }
    localMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.mouseMoved]
    ) { event in
      Task { @MainActor in
        handler(NSEvent.mouseLocation)
      }
      return event
    }
    return globalMonitor != nil && localMonitor != nil
  }

  public func stop() {
    if let globalMonitor {
      NSEvent.removeMonitor(globalMonitor)
      self.globalMonitor = nil
    }
    if let localMonitor {
      NSEvent.removeMonitor(localMonitor)
      self.localMonitor = nil
    }
  }

  isolated deinit {
    // Event monitors are removed by the owning collection before release.
  }
}
