import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BearDiagnosticsPrivacySection: View {
  let store: BearPrivateDiagnosticsStore

  @AppStorage(
    BearPrivateDiagnosticsConfiguration.enabledDefaultsKey
  ) private var isEnabled = false
  @AppStorage(
    BearPrivateDiagnosticsConfiguration.includesWritingDefaultsKey
  ) private var includesWriting = false
  @State private var storedBytes = 0
  @State private var isConfirmingDelete = false
  @State private var isExporting = false
  @State private var isShowingError = false
  @State private var errorMessage: String?

  init(store: BearPrivateDiagnosticsStore = .shared) {
    self.store = store
  }

  var body: some View {
    BearDiagnosticsPrivacyContent(
      isEnabled: $isEnabled,
      includesWriting: $includesWriting,
      storedBytes: storedBytes,
      isExporting: isExporting,
      onExport: exportTrace,
      onDelete: { isConfirmingDelete = true }
    )
    .task { await refreshSize() }
    .onChange(of: isEnabled) {
      if !isEnabled {
        includesWriting = false
      }
    }
    .confirmationDialog(
      String(
        localized: "Delete the local Bear diagnostic trace?",
        bundle: #bundle,
        comment:
          "Title of the confirmation shown before deleting Typover's local Bear diagnostic trace."
      ),
      isPresented: $isConfirmingDelete,
      titleVisibility: .visible
    ) {
      Button(role: .destructive) {
        Task { await deleteTrace() }
      } label: {
        Text(
          "Delete Trace",
          bundle: #bundle,
          comment:
            "Confirmation button that deletes Typover's local Bear diagnostic trace."
        )
      }
      Button(role: .cancel) {} label: {
        Text(
          "Cancel",
          bundle: #bundle,
          comment:
            "Button that cancels deleting Typover's local Bear diagnostic trace."
        )
      }
    } message: {
      Text(
        "This removes the trace from this Mac. Typover's content-free session counters and remembered correction choices are unchanged.",
        bundle: #bundle,
        comment:
          "Explanation of what deleting Typover's local Bear diagnostic trace does and does not remove."
      )
    }
    .alert(
      String(
        localized: "Diagnostic Trace Error",
        bundle: #bundle,
        comment:
          "Title of an error alert for Typover's local Bear diagnostic trace."
      ),
      isPresented: $isShowingError
    ) {
      Button(role: .cancel) {} label: {
        Text(
          "OK",
          bundle: #bundle,
          comment:
            "Button that dismisses a Typover diagnostic-trace error alert."
        )
      }
    } message: {
      if let errorMessage {
        Text(errorMessage)
      }
    }
  }

  private func refreshSize() async {
    storedBytes = await store.size()
  }

  private func exportTrace() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Typover Bear Diagnostic Trace.jsonl"
    panel.allowedContentTypes = [
      UTType(filenameExtension: "jsonl") ?? .json,
    ]
    guard panel.runModal() == .OK, let destination = panel.url else {
      return
    }
    isExporting = true
    Task {
      do {
        try await store.export(to: destination)
      } catch {
        errorMessage = error.localizedDescription
        isShowingError = true
      }
      isExporting = false
      await refreshSize()
    }
  }

  private func deleteTrace() async {
    do {
      try await store.delete()
    } catch {
      errorMessage = error.localizedDescription
      isShowingError = true
    }
    await refreshSize()
  }
}

private struct BearDiagnosticsPrivacyContent: View {
  @Binding var isEnabled: Bool
  @Binding var includesWriting: Bool
  let storedBytes: Int
  let isExporting: Bool
  let onExport: () -> Void
  let onDelete: () -> Void

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 14) {
        BearDiagnosticsCaptureControls(
          isEnabled: $isEnabled,
          includesWriting: $includesWriting
        )
        Divider()
        BearDiagnosticsStorageControls(
          storedBytes: storedBytes,
          isExporting: isExporting,
          onExport: onExport,
          onDelete: onDelete
        )
      }
      .padding(4)
    } label: {
      Label {
        Text(
          "Bear diagnostics privacy",
          bundle: #bundle,
          comment:
            "Heading for Typover's Bear diagnostic privacy and retention controls."
        )
      } icon: {
        Image(systemName: "lock.doc")
      }
    }
  }
}

private struct BearDiagnosticsCaptureControls: View {
  @Binding var isEnabled: Bool
  @Binding var includesWriting: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Toggle(isOn: $isEnabled) {
        Text(
          "Save a local Bear diagnostic trace",
          bundle: #bundle,
          comment:
            "Setting that enables Typover's bounded local Bear diagnostic trace."
        )
      }
      .accessibilityIdentifier("typover.settings.bear-diagnostics.enabled")

      Text(
        "Off by default. When enabled, Typover keeps content-free event timing on this Mac for up to 24 hours or 1 MB. It never uploads the trace.",
        bundle: #bundle,
        comment:
          "Privacy and retention explanation for Typover's local Bear diagnostic trace."
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      .padding(.leading, 20)

      Toggle(isOn: $includesWriting) {
        Text(
          "Include bounded writing context",
          bundle: #bundle,
          comment:
            "Setting that allows Typover's local diagnostic trace to include bounded Bear writing context."
        )
      }
      .disabled(!isEnabled)
      .accessibilityIdentifier(
        "typover.settings.bear-diagnostics.includes-writing"
      )

      if includesWriting && isEnabled {
        Label {
          Text(
            "The trace may contain words near the caret, originals, and replacements. Use this only for a diagnostic session, then export or delete it.",
            bundle: #bundle,
            comment:
              "Warning shown when the user permits bounded writing in Typover's local diagnostic trace."
          )
        } icon: {
          Image(systemName: "exclamationmark.shield")
        }
        .font(.callout)
        .foregroundStyle(.orange)
        .padding(.leading, 20)
      }
    }
  }
}

private struct BearDiagnosticsStorageControls: View {
  let storedBytes: Int
  let isExporting: Bool
  let onExport: () -> Void
  let onDelete: () -> Void

  var body: some View {
    HStack {
      HStack(spacing: 3) {
        Text(
          "Stored locally:",
          bundle: #bundle,
          comment:
            "Label before the size of Typover's local Bear diagnostic trace."
        )
        Text(Int64(storedBytes), format: .byteCount(style: .file))
      }
      .font(.caption)
      .foregroundStyle(.secondary)

      Spacer()

      Button(action: onExport) {
        if isExporting {
          ProgressView()
            .controlSize(.small)
        } else {
          Text(
            "Export…",
            bundle: #bundle,
            comment:
              "Button that exports Typover's local Bear diagnostic trace."
          )
        }
      }
      .disabled(storedBytes == 0 || isExporting)
      .accessibilityIdentifier("typover.settings.bear-diagnostics.export")

      Button(role: .destructive, action: onDelete) {
        Text(
          "Delete",
          bundle: #bundle,
          comment:
            "Button that deletes Typover's local Bear diagnostic trace."
        )
      }
      .disabled(storedBytes == 0)
      .accessibilityIdentifier("typover.settings.bear-diagnostics.delete")
    }
  }
}
