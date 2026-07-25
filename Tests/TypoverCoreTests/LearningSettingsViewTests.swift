import AppKit
import Foundation
import SwiftUI
import Testing
import TypoverCore

@testable import TypoverApp

@MainActor
struct LearningSettingsViewTests {
  @Test("Statistics and preferences settings render at their intended size")
  func rendersSettingsSurface() throws {
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
    populate(store)

    let image = try render(
      LearningSettingsView(
        behaviorSettings: behaviorSettings,
        learningStore: store
      )
      .background(Color(nsColor: .windowBackgroundColor)),
      size: NSSize(width: 640, height: 1_080)
    )

    #expect(image.size.width == 640)
    #expect(image.size.height == 1_080)

    if let snapshotPath = ProcessInfo.processInfo.environment[
      "TYPOVER_SETTINGS_SNAPSHOT_PATH"
    ] {
      try writePNG(image, to: URL(fileURLWithPath: snapshotPath))
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

  private func render<Content: View>(
    _ content: Content,
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
