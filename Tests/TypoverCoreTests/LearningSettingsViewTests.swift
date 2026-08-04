import AppKit
import Foundation
import SwiftUI
import Testing
import TypoverAccessibility
@testable import TypoverApp
import TypoverCore

@MainActor
struct LearningSettingsViewTests {
  @Test
  func `Correction counts use singular and plural labels`() {
    #expect(String(localized: correctionCountLabel(0)) == "0 corrections")
    #expect(String(localized: correctionCountLabel(1)) == "1 correction")
    #expect(String(localized: correctionCountLabel(2)) == "2 corrections")
  }

  @Test
  func `Permission model reports the current checker snapshot`() {
    let model = TypoverPermissionModel(
      checker: TestPermissionChecker(
        value: TypoverPermissionSnapshot(
          accessibilityAllowed: true,
          inputMonitoringAllowed: false
        )
      )
    )

    model.refresh()

    #expect(model.snapshot.accessibilityAllowed)
    #expect(model.snapshot.inputMonitoringAllowed == false)
  }

  @Test
  func `A new Bear preview supersedes only an active interaction`() {
    #expect(BearOverlayPreviewStatus.idle.previewRequestAction == .start)
    #expect(
      BearOverlayPreviewStatus.editorUnavailable.previewRequestAction == .start
    )
    #expect(BearOverlayPreviewStatus.active.previewRequestAction == .supersede)
    #expect(BearOverlayPreviewStatus.preparing.previewRequestAction == .ignore)
  }

  @Test
  func `Bear preview reports missing Accessibility permission`() {
    let report = BearAccessibilityReport(
      status: .accessibilityPermissionRequired,
      accessibilityTrusted: false,
      bearIsRunning: true
    )

    #expect(
      BearOverlayPreviewStatus.failure(for: report)
        == .accessibilityPermissionRequired
    )
  }

  @Test
  func `Bear preview distinguishes selection and editor failures`() {
    let missingSelection = BearAccessibilityReport(
      status: .ready,
      accessibilityTrusted: true,
      bearIsRunning: true
    )
    let unfocusedEditor = BearAccessibilityReport(
      status: .editorAvailableButNotFocused,
      accessibilityTrusted: true,
      bearIsRunning: true,
      selectedRange: AccessibilityTextRange(location: 20, length: 3)
    )

    #expect(
      BearOverlayPreviewStatus.failure(for: missingSelection)
        == .selectExactTypo
    )
    #expect(
      BearOverlayPreviewStatus.failure(for: unfocusedEditor)
        == .editorUnavailable
    )
  }

  @Test
  func `Bear preview preserves the exact replacement failure`() {
    let report = BearExactRangeReplacementReport(
      status: .replacementWriteFailed,
      targetRange: AccessibilityTextRange(location: 20, length: 3)
    )

    #expect(
      BearOverlayPreviewStatus.failure(for: report)
        == .correctionFailed(.replacementWriteFailed)
    )
  }

  @Test
  func `Settings panes render at their intended size`() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CorrectionLearningStore(
      fileURL: directory.appendingPathComponent("learning.json")
    )
    let defaultsName = "LearningSettingsViewTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: defaultsName))
    defer { defaults.removePersistentDomain(forName: defaultsName) }
    let behaviorSettings = CorrectionBehaviorSettings(
      defaults: defaults
    )
    behaviorSettings.contextualScope = .comprehensive
    behaviorSettings.allowsSentenceRewrites = true
    if let rawModel = ProcessInfo.processInfo.environment[
      "TYPOVER_SETTINGS_MODEL"
    ], let model = ContextualCorrectionModel(rawValue: rawModel) {
      behaviorSettings.contextualModel = model
    }
    populate(store)
    let credentialStore = SecretsAppCredentialStore(
      environment: [
        "OPENAI_API_KEY": "test-credential",
        "ANTHROPIC_API_KEY": "test-credential"
      ]
    )

    let standardDefaults = UserDefaults.standard
    let previousPane = standardDefaults.string(
      forKey: LearningSettingsView.selectedPaneDefaultsKey
    )
    let previousBearAdvanced = standardDefaults.object(
      forKey: BearCompatibilitySection.advancedExpandedDefaultsKey
    )
    defer {
      if let previousPane {
        standardDefaults.set(
          previousPane,
          forKey: LearningSettingsView.selectedPaneDefaultsKey
        )
      } else {
        standardDefaults.removeObject(
          forKey: LearningSettingsView.selectedPaneDefaultsKey
        )
      }
      if let previousBearAdvanced {
        standardDefaults.set(
          previousBearAdvanced,
          forKey: BearCompatibilitySection.advancedExpandedDefaultsKey
        )
      } else {
        standardDefaults.removeObject(
          forKey: BearCompatibilitySection.advancedExpandedDefaultsKey
        )
      }
    }
    let snapshotHeight = ProcessInfo.processInfo.environment[
      "TYPOVER_SETTINGS_SNAPSHOT_HEIGHT"
    ].flatMap(Double.init) ?? 540
    let requestedPane = ProcessInfo.processInfo.environment[
      "TYPOVER_SETTINGS_PANE"
    ]
    let panes = requestedPane.map { [$0] }
      ?? ["general", "bear", "learning", "privacy"]

    for pane in panes {
      standardDefaults.set(
        pane,
        forKey: LearningSettingsView.selectedPaneDefaultsKey
      )
      standardDefaults.set(
        ProcessInfo.processInfo.environment[
          "TYPOVER_SETTINGS_BEAR_ADVANCED"
        ] == "1",
        forKey: BearCompatibilitySection.advancedExpandedDefaultsKey
      )

      let image = try render(
        LearningSettingsView(
          behaviorSettings: behaviorSettings,
          learningStore: store,
          credentialStore: credentialStore
        )
        .background(Color(nsColor: .windowBackgroundColor)),
        size: NSSize(width: 680, height: snapshotHeight)
      )

      #expect(image.size.width == 680)
      #expect(image.size.height == CGFloat(snapshotHeight))

      if panes.count == 1,
         let snapshotPath = ProcessInfo.processInfo.environment[
           "TYPOVER_SETTINGS_SNAPSHOT_PATH"
         ]
      {
        try writePNG(image, to: URL(fileURLWithPath: snapshotPath))
      }
    }
  }

  private func populate(_ store: CorrectionLearningStore) {
    let alternative = proposal(
      original: "teh",
      replacement: "the"
    )
    let reverted = proposal(
      original: "wrod",
      replacement: "word"
    )
    let edited = proposal(
      original: "recieve",
      replacement: "receive"
    )
    store.recordApplied(alternative)
    store.recordApplied(reverted)
    store.recordApplied(edited)
    store.recordPreferred(
      "ten",
      for: alternative,
      outcome: .alternativeChosen
    )
    store.recordReverted(reverted)
    store.recordManualEdit("recipe", for: edited)
  }

  private func proposal(
    original: String,
    replacement: String
  ) -> CorrectionProposal {
    CorrectionProposal(
      correction: Correction(
        original: original,
        replacement: replacement
      ),
      alternatives: [],
      source: .appleSpelling,
      language: "en_US",
      lookupDuration: .zero
    )
  }

  private func writePNG(_ image: NSImage, to url: URL) throws {
    let tiffData = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiffData))
    let pngData = try #require(
      bitmap.representation(using: .png, properties: [:])
    )
    try pngData.write(to: url, options: .atomic)
  }

  private func render(
    _ content: some View,
    size: NSSize
  ) throws -> NSImage {
    let hostingController = NSHostingController(rootView: content)
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.contentViewController = hostingController
    hostingController.view.frame = NSRect(origin: .zero, size: size)
    hostingController.view.layoutSubtreeIfNeeded()
    hostingController.view.displayIfNeeded()

    let bitmap = try #require(
      hostingController.view.bitmapImageRepForCachingDisplay(
        in: hostingController.view.bounds
      )
    )
    hostingController.view.cacheDisplay(
      in: hostingController.view.bounds,
      to: bitmap
    )
    let image = NSImage(size: size)
    image.addRepresentation(bitmap)
    return image
  }
}

private struct TestPermissionChecker: TypoverPermissionChecking {
  let value: TypoverPermissionSnapshot

  func snapshot() -> TypoverPermissionSnapshot {
    value
  }
}
