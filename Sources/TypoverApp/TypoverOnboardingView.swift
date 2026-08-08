import AppKit
import ApplicationServices
import CoreGraphics
import Observation
import SwiftUI

struct TypoverPermissionSnapshot: Equatable, Sendable {
  let accessibilityAllowed: Bool
  let inputMonitoringAllowed: Bool

  /// The `.inputMonitoring` case is unreachable on macOS 27 and is kept
  /// deliberately.
  ///
  /// It needs `accessibilityAllowed && !inputMonitoringAllowed`, and macOS
  /// grants Input Monitoring along with Accessibility: measured on a clean
  /// macOS 27 guest, `tccutil reset ListenEvent` left
  /// `CGPreflightListenEventAccess()` returning true while the same reset
  /// against Accessibility cleared both, so there is no separate approval to
  /// withdraw. That was verified for this app, on that one OS version, in a
  /// VM — narrow enough that removing the branch would be a bet on the
  /// relationship never changing. If a later macOS does separate them, this
  /// keeps guiding people to the right pane instead of silently skipping it.
  var nextSystemSettingsDestination: TypoverSystemSettingsDestination {
    if !accessibilityAllowed {
      return .accessibility
    }
    if !inputMonitoringAllowed {
      return .inputMonitoring
    }
    return .privacyAndSecurity
  }

  var setupButtonTitle: LocalizedStringResource {
    switch nextSystemSettingsDestination {
    case .accessibility:
      "Set Up Accessibility…"
    case .inputMonitoring:
      "Set Up Input Monitoring…"
    case .privacyAndSecurity:
      "Open Privacy & Security…"
    }
  }
}

enum TypoverSystemSettingsDestination: Equatable, Sendable {
  case accessibility
  case inputMonitoring
  case privacyAndSecurity

  var url: URL? {
    let value = switch self {
    case .accessibility:
      "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    case .inputMonitoring:
      "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
    case .privacyAndSecurity:
      "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
    }
    return URL(string: value)
  }
}

protocol TypoverPermissionChecking: Sendable {
  func snapshot() -> TypoverPermissionSnapshot
}

struct SystemTypoverPermissionChecker: TypoverPermissionChecking {
  func snapshot() -> TypoverPermissionSnapshot {
    TypoverPermissionSnapshot(
      accessibilityAllowed: AXIsProcessTrusted(),
      inputMonitoringAllowed: CGPreflightListenEventAccess()
    )
  }
}

@MainActor
@Observable
final class TypoverPermissionModel {
  private(set) var snapshot = TypoverPermissionSnapshot(
    accessibilityAllowed: false,
    inputMonitoringAllowed: false
  )

  private let checker: any TypoverPermissionChecking

  init(checker: any TypoverPermissionChecking = SystemTypoverPermissionChecker()) {
    self.checker = checker
  }

  func refresh() {
    snapshot = checker.snapshot()
  }

  func openSystemSettings() {
    if let destinationURL = snapshot.nextSystemSettingsDestination.url,
       NSWorkspace.shared.open(destinationURL)
    {
      return
    }

    guard
      let settingsURL = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: "com.apple.systempreferences"
      )
    else { return }
    NSWorkspace.shared.openApplication(
      at: settingsURL,
      configuration: NSWorkspace.OpenConfiguration()
    )
  }
}

struct TypoverOnboardingView: View {
  let onContinue: () -> Void
  @State private var permissionModel = TypoverPermissionModel()

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      TypoverOnboardingHeader()
      TypoverPermissionBenefits(
        snapshot: permissionModel.snapshot,
        setupButtonTitle: permissionModel.snapshot.setupButtonTitle,
        onOpenSettings: permissionModel.openSystemSettings
      )
      TypoverOnboardingActions(onContinue: onContinue)
    }
    .padding(30)
    .frame(width: 560)
    .background(Color(nsColor: .windowBackgroundColor))
    .task { permissionModel.refresh() }
    .onReceive(
      NotificationCenter.default.publisher(
        for: NSApplication.didBecomeActiveNotification
      )
    ) { _ in
      permissionModel.refresh()
    }
  }
}

private struct TypoverOnboardingHeader: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Image(nsImage: TypoverBrand.appIcon)
        .resizable()
        .scaledToFit()
        .frame(width: 72, height: 72)
        .accessibilityHidden(true)

      Text(
        "Corrections you can trust—and take back.",
        bundle: #bundle,
        comment: "Headline in Typover's first-run permission explanation."
      )
      .font(.largeTitle)
      .fontWeight(.semibold)

      Text(
        "Typover corrects the smallest verified range, leaves a light-gray squiggle, and keeps every change reversible. To do that in Bear, macOS asks for two permissions.",
        bundle: #bundle,
        comment:
        "Benefit-led introduction to Typover's first-run permission explanation."
      )
      .font(.title3)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct TypoverPermissionBenefits: View {
  let snapshot: TypoverPermissionSnapshot
  let setupButtonTitle: LocalizedStringResource
  let onOpenSettings: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      TypoverPermissionRow(
        title: "Accessibility",
        explanation:
        "Lets Typover verify and replace only the intended Bear word, position its squiggle, and change the word back.",
        isAllowed: snapshot.accessibilityAllowed,
        systemImage: "accessibility"
      )
      TypoverPermissionRow(
        title: "Input Monitoring",
        explanation:
        "Lets Typover tell a word you just finished typing from pasted or programmatic text. macOS includes this with Accessibility, so there is no separate switch to turn on. Typover does not record your keystrokes.",
        isAllowed: snapshot.inputMonitoringAllowed,
        systemImage: "keyboard",
        isImpliedByAccessibility: true
      )

      HStack {
        Button(action: onOpenSettings) {
          Text(setupButtonTitle)
        }
        .accessibilityIdentifier("typover.onboarding.open-system-settings")

        Spacer()

        Label {
          Text(
            "You stay in control",
            bundle: #bundle,
            comment:
            "Reassurance beside Typover's first-run permission setup button."
          )
        } icon: {
          Image(systemName: "lock.shield")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
  }
}

enum TypoverPermissionStatus {
  /// Input Monitoring has no control a user can reach. macOS includes it with
  /// Accessibility, so an app holding Accessibility is never added to the
  /// Input Monitoring list and is never asked about it. Showing "Not yet
  /// allowed" sent the reader looking for a switch that is not there, and
  /// offered a choice they had in fact already made by granting Accessibility.
  static func title(
    isAllowed: Bool,
    isImpliedByAccessibility: Bool
  ) -> LocalizedStringResource {
    if isImpliedByAccessibility {
      return "Included with Accessibility"
    }
    return isAllowed ? "Allowed" : "Not yet allowed"
  }
}

private struct TypoverPermissionRow: View {
  let title: LocalizedStringResource
  let explanation: LocalizedStringResource
  let isAllowed: Bool
  let systemImage: String
  var isCompact = false
  /// Set for a capability macOS grants along with Accessibility rather than
  /// through a switch of its own.
  var isImpliedByAccessibility = false

  private var statusTitle: LocalizedStringResource {
    TypoverPermissionStatus.title(
      isAllowed: isAllowed,
      isImpliedByAccessibility: isImpliedByAccessibility
    )
  }

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: systemImage)
        .font(isCompact ? .body : .title2)
        .foregroundStyle(.tint)
        .frame(width: isCompact ? 22 : 30)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(title)
            .font(isCompact ? .body : .headline)
          Spacer()
          Label {
            Text(statusTitle)
          } icon: {
            Image(
              systemName: isAllowed
                ? "checkmark.circle.fill"
                : "circle.dashed"
            )
          }
          .font(.callout)
          .foregroundStyle(isAllowed ? .green : .secondary)
        }

        Text(explanation)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
    .padding(isCompact ? 0 : 14)
    .background {
      if !isCompact {
        RoundedRectangle(cornerRadius: 12)
          .fill(.quaternary.opacity(0.5))
      }
    }
    .accessibilityElement(children: .combine)
  }
}

private struct TypoverOnboardingActions: View {
  let onContinue: () -> Void

  var body: some View {
    HStack {
      Text(
        "You can finish permission setup later in Typover Settings.",
        bundle: #bundle,
        comment:
        "Explanation that Typover's first-run permission setup can be deferred."
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      Spacer()

      Button(action: onContinue) {
        Text(
          "Continue to Typover",
          bundle: #bundle,
          comment:
          "Button that finishes Typover's first-run explanation and opens the editor."
        )
      }
      .buttonStyle(.borderedProminent)
      .keyboardShortcut(.defaultAction)
      .accessibilityIdentifier("typover.onboarding.continue")
    }
  }
}

struct TypoverPermissionsSettingsSection: View {
  @State private var permissionModel = TypoverPermissionModel()

  var body: some View {
    Section {
      TypoverPermissionRow(
        title: "Accessibility",
        explanation:
        "Required for exact Bear ranges, reversible changes, and squiggle geometry.",
        isAllowed: permissionModel.snapshot.accessibilityAllowed,
        systemImage: "accessibility",
        isCompact: true
      )
      TypoverPermissionRow(
        title: "Input Monitoring",
        explanation:
        "Required to pair a real completion key with Bear's text change. macOS includes it with Accessibility.",
        isAllowed: permissionModel.snapshot.inputMonitoringAllowed,
        systemImage: "keyboard",
        isCompact: true,
        isImpliedByAccessibility: true
      )
      HStack {
        Button(action: permissionModel.openSystemSettings) {
          Text(permissionModel.snapshot.setupButtonTitle)
        }
        .accessibilityIdentifier("typover.settings.permissions.open")

        Button(action: permissionModel.refresh) {
          Text(
            "Refresh",
            bundle: #bundle,
            comment:
            "Button that refreshes Typover's macOS permission status."
          )
        }
        .accessibilityIdentifier("typover.settings.permissions.refresh")
      }
    } header: {
      Text(
        "Permissions",
        bundle: #bundle,
        comment: "Heading for Typover's macOS permission status."
      )
    } footer: {
      Text(
        "Typover must remain open while you write in Bear.",
        bundle: #bundle,
        comment: "Explanation of Typover's manual-launch behavior."
      )
    }
    .task { permissionModel.refresh() }
    .onReceive(
      NotificationCenter.default.publisher(
        for: NSApplication.didBecomeActiveNotification
      )
    ) { _ in
      permissionModel.refresh()
    }
  }
}
