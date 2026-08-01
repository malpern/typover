import AppKit
import Foundation
import OSLog

@MainActor
protocol BearAnnotationShortcutRegistering: AnyObject {
  @discardableResult
  func register(
    handler: @escaping @MainActor @Sendable () -> Void
  ) -> UUID?

  func unregister(_ token: UUID)
}

@MainActor
final class BearAnnotationShortcutCenter: BearAnnotationShortcutRegistering {
  static let shared = BearAnnotationShortcutCenter(
    backend: AppKitBearAnnotationHotKeyBackend()
  )

  private let logger = Logger(
    subsystem: "com.malpern.typover",
    category: "BearAnnotationShortcut"
  )

  private let backend: any BearAnnotationHotKeyBackend
  private var handlers: [UUID: @MainActor @Sendable () -> Void] = [:]
  private var registrationOrder: [UUID] = []

  init(backend: any BearAnnotationHotKeyBackend) {
    self.backend = backend
  }

  @discardableResult
  func register(
    handler: @escaping @MainActor @Sendable () -> Void
  ) -> UUID? {
    if handlers.isEmpty {
      guard backend.start(handler: { [weak self] in
        self?.performMostRecentAction()
      }) else {
        logger.error("Failed to register global Change Back shortcut")
        return nil
      }
      logger.notice("Registered global Change Back shortcut shortcut=⌃⌥⌘M")
    }

    let token = UUID()
    handlers[token] = handler
    registrationOrder.append(token)
    return token
  }

  func unregister(_ token: UUID) {
    handlers[token] = nil
    registrationOrder.removeAll { $0 == token }
    if handlers.isEmpty {
      backend.stop()
      logger.notice("Unregistered global Change Back shortcut")
    }
  }

  private func performMostRecentAction() {
    guard let token = registrationOrder.last,
      let handler = handlers[token]
    else {
      return
    }
    logger.notice("Received global Change Back shortcut shortcut=⌃⌥⌘M")
    handler()
  }
}

@MainActor
protocol BearAnnotationHotKeyBackend: AnyObject {
  func start(
    handler: @escaping @MainActor @Sendable () -> Void
  ) -> Bool
  func stop()
}

enum BearAnnotationShortcutChord {
  // NSEvent uses the legacy virtual key code for the physical ANSI M key.
  static let keyCode: UInt16 = 46
  static let requiredModifiers: NSEvent.ModifierFlags = [
    .control,
    .option,
    .command,
  ]

  static func matches(
    keyCode: UInt16,
    modifiers: NSEvent.ModifierFlags,
    isRepeat: Bool
  ) -> Bool {
    guard !isRepeat, keyCode == Self.keyCode else {
      return false
    }
    let shortcutModifiers = modifiers.intersection([
      .control,
      .option,
      .command,
      .shift,
    ])
    return shortcutModifiers == requiredModifiers
  }
}

@MainActor
private final class AppKitBearAnnotationHotKeyBackend:
  BearAnnotationHotKeyBackend
{
  private var eventMonitor: Any?
  private var handler: (@MainActor @Sendable () -> Void)?

  func start(
    handler: @escaping @MainActor @Sendable () -> Void
  ) -> Bool {
    guard eventMonitor == nil else {
      self.handler = handler
      return true
    }

    self.handler = handler
    eventMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: .keyDown
    ) { [weak self] event in
      let keyCode = event.keyCode
      let modifierRawValue = event.modifierFlags.rawValue
      let isRepeat = event.isARepeat
      Task { @MainActor [weak self] in
        self?.receive(
          keyCode: keyCode,
          modifiers: NSEvent.ModifierFlags(rawValue: modifierRawValue),
          isRepeat: isRepeat
        )
      }
    }
    guard eventMonitor != nil else {
      self.handler = nil
      return false
    }
    return true
  }

  func stop() {
    if let eventMonitor {
      NSEvent.removeMonitor(eventMonitor)
      self.eventMonitor = nil
    }
    handler = nil
  }

  private func receive(
    keyCode: UInt16,
    modifiers: NSEvent.ModifierFlags,
    isRepeat: Bool
  ) {
    guard BearAnnotationShortcutChord.matches(
      keyCode: keyCode,
      modifiers: modifiers,
      isRepeat: isRepeat
    ) else {
      return
    }
    handler?()
  }
}
