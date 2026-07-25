import SwiftUI
import TypoverAccessibility

struct BearCompatibilitySection: View {
  let report: BearAccessibilityReport?
  let isChecking: Bool
  let onCheck: () -> Void

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 14) {
        if let report {
          BearCompatibilityStatus(report: report)
        } else {
          Text(
            "Typover briefly brings Bear forward to check the caret, a small local context, and range geometry. The check never changes a note or keeps its text.",
            bundle: #bundle,
            comment:
              "Explanation of Typover's read-only Bear compatibility check."
          )
          .font(.callout)
          .foregroundStyle(.secondary)
        }

        HStack {
          Button(action: onCheck) {
            if isChecking {
              ProgressView()
                .controlSize(.small)
              Text(
                "Checking Bear…",
                bundle: #bundle,
                comment:
                  "Label shown while Typover performs its read-only Bear compatibility check."
              )
            } else {
              Text(
                "Run Read-Only Check",
                bundle: #bundle,
                comment:
                  "Button that starts Typover's read-only Bear compatibility check."
              )
            }
          }
          .disabled(isChecking)
          .accessibilityIdentifier("typover.settings.bear.run-probe")

          Spacer()

          Label {
            Text(
              "No note text is shown or saved",
              bundle: #bundle,
              comment:
                "Privacy statement beside Typover's Bear compatibility check."
            )
          } icon: {
            Image(systemName: "lock.shield")
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }
      .padding(4)
    } label: {
      Label {
        Text(
          "Bear compatibility",
          bundle: #bundle,
          comment:
            "Heading for Typover's Bear compatibility diagnostics."
        )
      } icon: {
        Image(systemName: "pawprint")
      }
    }
  }
}

private struct BearCompatibilityStatus: View {
  let report: BearAccessibilityReport

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: report.status.systemImage)
          .font(.title2)
          .foregroundStyle(report.status.tint)
          .frame(width: 28)

        VStack(alignment: .leading, spacing: 4) {
          Text(report.status.title)
            .font(.headline)

          Text(report.status.explanation)
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        Spacer()
      }

      if report.status == .ready
        || report.status == .editorAvailableButNotFocused
      {
        Divider()

        BearCapabilityRow(
          title: "Caret",
          isAvailable: report.selectedRange != nil
        )
        BearCapabilityRow(
          title: "Bounded context",
          isAvailable: report.boundedContextUTF16Length != nil
        )
        BearCapabilityRow(
          title: "Range geometry",
          isAvailable: report.rangeBounds != nil
        )

        LabeledContent {
          Text(
            "\(supportedNotificationCount) of \(report.notificationRegistrations.count)",
            bundle: #bundle,
            comment:
              "Count of supported Accessibility notification registrations; the first value is supported and the second is tested."
          )
        } label: {
          Text(
            "Event registrations",
            bundle: #bundle,
            comment:
              "Label for Bear Accessibility event-registration capabilities."
          )
        }
      }
    }
  }

  private var supportedNotificationCount: Int {
    report.notificationRegistrations.count { capability in
      capability.state == .available
    }
  }
}

private struct BearCapabilityRow: View {
  let title: LocalizedStringResource
  let isAvailable: Bool

  var body: some View {
    LabeledContent {
      if isAvailable {
        Text(
          "Available",
          bundle: #bundle,
          comment:
            "Availability result for a Bear Accessibility capability."
        )
      } else {
        Text(
          "Unavailable",
          bundle: #bundle,
          comment:
            "Unavailability result for a Bear Accessibility capability."
        )
      }
    } label: {
      Text(title)
    }
  }
}

extension BearAccessibilityProbeStatus {
  fileprivate var title: LocalizedStringResource {
    switch self {
    case .ready:
      "Bear editor found"
    case .accessibilityPermissionRequired:
      "Accessibility permission required"
    case .bearNotRunning:
      "Bear is not running"
    case .focusedEditorUnavailable:
      "No focused Bear editor"
    case .focusedElementIsNotTextArea:
      "The focused Bear control is not an editor"
    case .editorAvailableButNotFocused:
      "Bear editor available"
    }
  }

  fileprivate var explanation: LocalizedStringResource {
    switch self {
    case .ready:
      "Typover found Bear’s active editor and completed a content-free capability check."
    case .accessibilityPermissionRequired:
      "Allow Typover in System Settings → Privacy & Security → Accessibility, then run the check again."
    case .bearNotRunning:
      "Open Bear, click inside a note, and run the check again."
    case .focusedEditorUnavailable:
      "Click inside a Bear note, then run the check again."
    case .focusedElementIsNotTextArea:
      "Move focus into the body of a Bear note, then run the check again."
    case .editorAvailableButNotFocused:
      "Typover found the current window’s editor and checked its capabilities. Focus the note body to confirm live caret behavior."
    }
  }

  fileprivate var systemImage: String {
    switch self {
    case .ready:
      "checkmark.circle.fill"
    case .editorAvailableButNotFocused:
      "checkmark.circle"
    case .accessibilityPermissionRequired:
      "lock.fill"
    case .bearNotRunning:
      "pawprint"
    case .focusedEditorUnavailable, .focusedElementIsNotTextArea:
      "cursorarrow.click"
    }
  }

  fileprivate var tint: Color {
    switch self {
    case .ready:
      .green
    case .accessibilityPermissionRequired:
      .orange
    case .bearNotRunning, .focusedEditorUnavailable,
      .focusedElementIsNotTextArea, .editorAvailableButNotFocused:
      .secondary
    }
  }
}
