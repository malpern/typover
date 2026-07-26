import SwiftUI
import TypoverAccessibility

struct BearCompatibilitySection: View {
  let report: BearAccessibilityReport?
  let eventReport: BearAccessibilityEventReport?
  let isChecking: Bool
  let isObserving: Bool
  let overlayPreviewStatus: BearOverlayPreviewStatus
  let onCheck: () -> Void
  let onObserve: () -> Void
  let onPreviewOverlay: () -> Void
  let onStopOverlayPreview: () -> Void

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
          .disabled(isChecking || isObserving)
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

        if report?.status.allowsEventObservation == true {
          Divider()

          BearEventObservationControl(
            report: eventReport,
            isObserving: isObserving,
            onObserve: onObserve
          )
        }

        Divider()

        BearOverlayPreviewControl(
          status: overlayPreviewStatus,
          onPreview: onPreviewOverlay,
          onStop: onStopOverlayPreview
        )
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

private struct BearOverlayPreviewControl: View {
  let status: BearOverlayPreviewStatus
  let onPreview: () -> Void
  let onStop: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(
        "To test the real overlay, select exactly “teh” in a disposable Bear note. Typover will change only that selection to “the” and place the light-gray mark beneath it.",
        bundle: #bundle,
        comment:
          "Instructions for the bounded Bear annotation overlay preview."
      )
      .font(.callout)
      .foregroundStyle(.secondary)

      if let message = status.message {
        Label(message, systemImage: status.systemImage)
          .font(.callout)
          .foregroundStyle(status == .active ? Color.green : Color.secondary)
      }

      HStack {
        Button(action: onPreview) {
          if status == .preparing {
            ProgressView()
              .controlSize(.small)
            Text(
              "Preparing Preview…",
              bundle: #bundle,
              comment: "Label while Typover starts the Bear overlay preview."
            )
          } else {
            Text(
              "Show Squiggle in Bear",
              bundle: #bundle,
              comment: "Button that begins the bounded Bear overlay preview."
            )
          }
        }
        .disabled(status == .preparing || status == .active)
        .accessibilityIdentifier("typover.settings.bear.preview-overlay")

        if status == .active {
          Button(action: onStop) {
            Text(
              "Stop Preview",
              bundle: #bundle,
              comment: "Button that stops the Bear annotation overlay preview."
            )
          }
          .accessibilityIdentifier("typover.settings.bear.stop-overlay")
        }
      }
    }
  }
}

extension BearOverlayPreviewStatus {
  fileprivate var message: LocalizedStringResource? {
    switch self {
    case .idle:
      nil
    case .preparing:
      "Checking the selected Bear text…"
    case .active:
      "Preview active while Bear remains in front"
    case .bearUnavailable:
      "Open Bear and try again"
    case .selectExactTypo:
      "Select exactly three characters in the Bear editor, then try again"
    case .selectionDidNotMatch:
      "The selected text was not “teh”; nothing was changed"
    }
  }

  fileprivate var systemImage: String {
    switch self {
    case .active:
      "scribble.variable"
    case .preparing:
      "ellipsis"
    case .idle, .bearUnavailable, .selectExactTypo, .selectionDidNotMatch:
      "info.circle"
    }
  }
}

private struct BearEventObservationControl: View {
  let report: BearAccessibilityEventReport?
  let isObserving: Bool
  let onObserve: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if isObserving {
        Label {
          Text(
            "Move the caret, scroll, or resize Bear now.",
            bundle: #bundle,
            comment:
              "Instruction shown while Typover observes read-only Bear Accessibility events."
          )
        } icon: {
          ProgressView()
            .controlSize(.small)
        }
        .font(.callout)
      } else if let report {
        BearEventObservationResult(report: report)
      } else {
        Text(
          "Observe Bear for five seconds, then move the caret, scroll, or resize the window. Typover records only event names and counts.",
          bundle: #bundle,
          comment:
            "Instructions for Typover's timed Bear Accessibility event observation."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      }

      Button(action: onObserve) {
        Text(
          isObserving
            ? "Observing Bear…"
            : "Observe Bear for 5 Seconds",
          bundle: #bundle,
          comment:
            "Button that starts or describes Typover's timed read-only Bear event observation."
        )
      }
      .disabled(isObserving)
      .accessibilityIdentifier("typover.settings.bear.observe-events")
    }
  }
}

private struct BearEventObservationResult: View {
  let report: BearAccessibilityEventReport

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label {
        Text(
          "\(totalEventCount) events observed",
          bundle: #bundle,
          comment:
            "Summary of the number of content-free Bear Accessibility events Typover observed."
        )
      } icon: {
        Image(
          systemName: totalEventCount == 0
            ? "exclamationmark.circle"
            : "checkmark.circle.fill"
        )
      }
      .font(.headline)
      .foregroundStyle(
        totalEventCount == 0 ? Color.secondary : Color.green
      )

      if report.observations.isEmpty {
        Text(
          "No events arrived. Run the observation again and interact with the Bear editor while it is in front.",
          bundle: #bundle,
          comment:
            "Guidance shown when no Bear Accessibility events were observed."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      } else {
        ForEach(report.observations) { observation in
          LabeledContent {
            Text(observation.count, format: .number)
          } label: {
            Text(observation.title)
          }
        }
      }
    }
  }

  private var totalEventCount: Int {
    report.observations.reduce(0) { result, observation in
      result + observation.count
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
  fileprivate var allowsEventObservation: Bool {
    self == .ready || self == .editorAvailableButNotFocused
  }

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

extension AccessibilityEventObservation {
  fileprivate var title: LocalizedStringResource {
    switch name {
    case "AXSelectedTextChanged":
      "Selection"
    case "AXValueChanged":
      "Text"
    case "AXLayoutChanged":
      "Layout"
    case "AXFocusedUIElementChanged":
      "Editor focus"
    case "AXFocusedWindowChanged":
      "Window focus"
    case "AXWindowMoved":
      "Window moved"
    case "AXWindowResized":
      "Window resized"
    default:
      "Other event"
    }
  }
}
