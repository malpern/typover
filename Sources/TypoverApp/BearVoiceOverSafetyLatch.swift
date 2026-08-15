import AppKit
import Darwin
import Foundation

/// VoiceOver changes Bear's selected-text replacement semantics for the
/// remainder of the current macOS boot. Once observed, keep Bear mutation
/// disabled until a new boot provides a fresh Accessibility server state.
@MainActor
final class BearVoiceOverSafetyLatch {
  static let shared = BearVoiceOverSafetyLatch()
  static let defaultsKey = "bear-voiceover-safety-pause-boot"

  private let defaults: UserDefaults
  private let bootIdentifier: @MainActor @Sendable () -> String?
  private let voiceOverIsEnabled: @MainActor @Sendable () -> Bool

  init(
    defaults: UserDefaults = .standard,
    bootIdentifier: @escaping @MainActor @Sendable () -> String? = {
      BearVoiceOverSafetyLatch.systemBootIdentifier()
    },
    voiceOverIsEnabled: @escaping @MainActor @Sendable () -> Bool = {
      NSWorkspace.shared.isVoiceOverEnabled
    }
  ) {
    self.defaults = defaults
    self.bootIdentifier = bootIdentifier
    self.voiceOverIsEnabled = voiceOverIsEnabled
  }

  func requiresPause() -> Bool {
    guard let currentBoot = bootIdentifier() else {
      if voiceOverIsEnabled() {
        defaults.set("unknown", forKey: Self.defaultsKey)
      }
      return voiceOverIsEnabled()
        || defaults.string(forKey: Self.defaultsKey) != nil
    }

    let storedBoot = defaults.string(forKey: Self.defaultsKey)
    if let storedBoot, storedBoot != currentBoot {
      defaults.removeObject(forKey: Self.defaultsKey)
    }
    if voiceOverIsEnabled() {
      defaults.set(currentBoot, forKey: Self.defaultsKey)
      return true
    }
    return defaults.string(forKey: Self.defaultsKey) == currentBoot
  }

  /// `kern.boottime` is recomputed as wall clock minus uptime, so it shifts
  /// whenever the clock is adjusted or the Mac sleeps and wakes. A latch that
  /// must hold until a real reboot cannot key off a value that drifts inside a
  /// single boot; one shifted second would silently release the pause.
  /// `kern.bootsessionuuid` is a true per-boot identity and stays put.
  static func systemBootIdentifier() -> String? {
    var size = 0
    guard
      sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0,
      size > 0
    else {
      return nil
    }
    var buffer = [CChar](repeating: 0, count: size)
    guard
      sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0
    else {
      return nil
    }
    return String(cString: buffer)
  }
}
