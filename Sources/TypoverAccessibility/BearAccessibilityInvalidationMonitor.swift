import AppKit
import ApplicationServices
import Foundation

public enum BearAccessibilityInvalidationEvent: String, Sendable {
  case selectionChanged
  case valueChanged
  case layoutChanged
  case focusedElementChanged
  case focusedWindowChanged
  case windowMoved
  case windowResized

  fileprivate init?(notification: String) {
    if notification == kAXSelectedTextChangedNotification {
      self = .selectionChanged
    } else if notification == kAXValueChangedNotification {
      self = .valueChanged
    } else if notification == kAXLayoutChangedNotification {
      self = .layoutChanged
    } else if notification == kAXFocusedUIElementChangedNotification {
      self = .focusedElementChanged
    } else if notification == kAXFocusedWindowChangedNotification {
      self = .focusedWindowChanged
    } else if notification == kAXWindowMovedNotification {
      self = .windowMoved
    } else if notification == kAXWindowResizedNotification {
      self = .windowResized
    } else {
      return nil
    }
  }
}

@MainActor
public protocol BearAccessibilityInvalidationObserving: AnyObject {
  @discardableResult
  func start(
    handler: @escaping @MainActor @Sendable (
      BearAccessibilityInvalidationEvent
    ) -> Void
  ) -> Bool

  func stop()
}

/// A long-lived, content-free observer for events that can invalidate an
/// annotation's screen position or text anchor.
///
/// The callback carries only an event category. It never reads or retains note
/// text, selection text, or geometry.
@MainActor
public final class BearAccessibilityInvalidationMonitor:
  BearAccessibilityInvalidationObserving
{
  private var observer: AXObserver?
  private var registrations: [(element: AXUIElement, name: String)] = []
  private var callbackBox: BearAccessibilityInvalidationCallbackBox?

  public init() {}

  isolated deinit {
    stop()
  }

  @discardableResult
  public func start(
    handler: @escaping @MainActor @Sendable (
      BearAccessibilityInvalidationEvent
    ) -> Void
  ) -> Bool {
    stop()

    guard AXIsProcessTrusted(),
      let runningApplication = NSRunningApplication.runningApplications(
        withBundleIdentifier: BearAccessibilityProbe.bearBundleIdentifier
      ).first
    else {
      return false
    }

    let applicationElement = AXUIElementCreateApplication(
      runningApplication.processIdentifier
    )
    guard
      let focusedElement = copyElementAttribute(
        applicationElement,
        kAXFocusedUIElementAttribute as CFString
      ),
      let editorElement = BearAccessibilityProbe().nearestTextArea(
        startingAt: focusedElement
      )
    else {
      return false
    }

    let windowElement = copyElementAttribute(
      editorElement,
      kAXWindowAttribute as CFString
    )
    var createdObserver: AXObserver?
    let observerError = AXObserverCreate(
      runningApplication.processIdentifier,
      bearAccessibilityInvalidationCallback,
      &createdObserver
    )
    guard observerError == .success, let createdObserver else {
      return false
    }

    let callbackBox = BearAccessibilityInvalidationCallbackBox(
      handler: handler
    )
    let callbackPointer = Unmanaged.passUnretained(callbackBox).toOpaque()
    var targets: [(element: AXUIElement, name: String)] = [
      (editorElement, kAXSelectedTextChangedNotification as String),
      (editorElement, kAXValueChangedNotification as String),
      (editorElement, kAXLayoutChangedNotification as String),
      (applicationElement, kAXFocusedUIElementChangedNotification as String),
      (applicationElement, kAXFocusedWindowChangedNotification as String),
    ]
    if let windowElement {
      targets.append(
        (windowElement, kAXWindowMovedNotification as String)
      )
      targets.append(
        (windowElement, kAXWindowResizedNotification as String)
      )
    }

    let successfulRegistrations = targets.filter { target in
      AXObserverAddNotification(
        createdObserver,
        target.element,
        target.name as CFString,
        callbackPointer
      ) == .success
    }
    let requiredNotifications = Set([
      kAXSelectedTextChangedNotification as String,
      kAXValueChangedNotification as String,
      kAXFocusedUIElementChangedNotification as String,
      kAXFocusedWindowChangedNotification as String,
    ])
    let registeredNotifications = Set(
      successfulRegistrations.map(\.name)
    )
    guard requiredNotifications.isSubset(of: registeredNotifications) else {
      for registration in successfulRegistrations {
        AXObserverRemoveNotification(
          createdObserver,
          registration.element,
          registration.name as CFString
        )
      }
      return false
    }

    observer = createdObserver
    registrations = successfulRegistrations
    self.callbackBox = callbackBox
    CFRunLoopAddSource(
      CFRunLoopGetMain(),
      AXObserverGetRunLoopSource(createdObserver),
      .commonModes
    )
    return true
  }

  public func stop() {
    guard let observer else {
      callbackBox = nil
      registrations = []
      return
    }

    CFRunLoopRemoveSource(
      CFRunLoopGetMain(),
      AXObserverGetRunLoopSource(observer),
      .commonModes
    )
    for registration in registrations {
      AXObserverRemoveNotification(
        observer,
        registration.element,
        registration.name as CFString
      )
    }
    self.observer = nil
    callbackBox = nil
    registrations = []
  }
}

private final class BearAccessibilityInvalidationCallbackBox:
  @unchecked Sendable
{
  let handler: @MainActor @Sendable (
    BearAccessibilityInvalidationEvent
  ) -> Void

  init(
    handler: @escaping @MainActor @Sendable (
      BearAccessibilityInvalidationEvent
    ) -> Void
  ) {
    self.handler = handler
  }
}

private func bearAccessibilityInvalidationCallback(
  _: AXObserver,
  _: AXUIElement,
  notification: CFString,
  context: UnsafeMutableRawPointer?
) {
  guard
    let context,
    let event = BearAccessibilityInvalidationEvent(
      notification: notification as String
    )
  else {
    return
  }
  let callbackBox = Unmanaged<
    BearAccessibilityInvalidationCallbackBox
  >.fromOpaque(context).takeUnretainedValue()
  Task { @MainActor in
    callbackBox.handler(event)
  }
}
