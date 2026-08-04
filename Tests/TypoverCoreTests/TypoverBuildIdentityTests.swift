import AppKit
import Foundation
import SwiftUI
import Testing

@testable import TypoverApp

struct TypoverBuildIdentityTests {
  @Test("Reads release identity and shortens its source revision")
  func readsReleaseIdentity() {
    let identity = TypoverBuildIdentity(
      infoDictionary: [
        "CFBundleShortVersionString": "0.1.2",
        "CFBundleVersion": "20260802001425",
        "TypoverSourceRevision": "20e8e2f322877a310fddda3fc853414fb0196c77",
        "TypoverSourceDirty": false,
      ]
    )

    #expect(identity.version == "0.1.2")
    #expect(identity.build == "20260802001425")
    #expect(identity.sourceRevision == "20e8e2f322877a310fddda3fc853414fb0196c77")
    #expect(identity.shortSourceRevision == "20e8e2f322")
    #expect(identity.sourceIsDirty == false)
    #expect(identity.versionAndBuild?.version == "0.1.2")
    #expect(identity.versionAndBuild?.build == "20260802001425")
  }

  @Test("Treats incomplete development metadata as unavailable")
  func handlesMissingMetadata() {
    let identity = TypoverBuildIdentity(
      infoDictionary: [
        "CFBundleShortVersionString": "  ",
        "TypoverSourceRevision": "\n",
      ]
    )

    #expect(identity.version == nil)
    #expect(identity.build == nil)
    #expect(identity.versionAndBuild == nil)
    #expect(identity.sourceRevision == nil)
    #expect(identity.shortSourceRevision == nil)
    #expect(identity.sourceIsDirty == nil)
  }

  @Test("Normalizes string metadata written by alternate build tooling")
  func normalizesStringMetadata() {
    let identity = TypoverBuildIdentity(
      infoDictionary: [
        "CFBundleShortVersionString": " 0.2 ",
        "CFBundleVersion": " 42\n",
        "TypoverSourceRevision": " abcdef ",
        "TypoverSourceDirty": "YES",
      ]
    )

    #expect(identity.version == "0.2")
    #expect(identity.build == "42")
    #expect(identity.sourceRevision == "abcdef")
    #expect(identity.shortSourceRevision == "abcdef")
    #expect(identity.sourceIsDirty == true)
  }

  @MainActor
  @Test("About renders a compact release identity")
  func rendersAboutIdentity() throws {
    let identity = TypoverBuildIdentity(
      infoDictionary: [
        "CFBundleShortVersionString": "0.1",
        "CFBundleVersion": "20260802005424",
        "TypoverSourceRevision": "dfc456f9d7aa872e055ea1deee2dfeb9935d2885",
        "TypoverSourceDirty": false,
      ]
    )
    let hostingController = NSHostingController(
      rootView: AboutView(buildIdentity: identity)
        .background(Color(nsColor: .windowBackgroundColor))
    )
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 390, height: 520),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.contentViewController = hostingController
    hostingController.view.frame = NSRect(
      origin: .zero,
      size: NSSize(width: 390, height: 520)
    )
    hostingController.view.layoutSubtreeIfNeeded()
    hostingController.view.displayIfNeeded()

    let image = try render(hostingController.view)
    #expect(image.size == NSSize(width: 390, height: 520))

    if let snapshotPath = ProcessInfo.processInfo.environment[
      "TYPOVER_ABOUT_SNAPSHOT_PATH"
    ] {
      try writePNG(image, to: URL(fileURLWithPath: snapshotPath))
    }
  }

  @MainActor
  private func render(_ view: NSView) throws -> NSImage {
    let bitmap = try #require(
      view.bitmapImageRepForCachingDisplay(in: view.bounds)
    )
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let image = NSImage(size: view.bounds.size)
    image.addRepresentation(bitmap)
    return image
  }

  private func writePNG(_ image: NSImage, to url: URL) throws {
    let tiffData = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiffData))
    let pngData = try #require(
      bitmap.representation(using: .png, properties: [:])
    )
    try pngData.write(to: url, options: .atomic)
  }
}
