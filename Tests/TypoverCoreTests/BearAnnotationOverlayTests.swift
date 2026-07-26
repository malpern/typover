import AppKit
import ApplicationServices
import Testing
import TypoverBearAdapter

@testable import TypoverAccessibility
@testable import TypoverOverlay

@Suite("Bear annotation overlay", .serialized)
struct BearAnnotationOverlayTests {
  private let primaryDisplay = BearOverlayDisplay(
    accessibilityFrame: AccessibilityBounds(
      x: 0,
      y: 0,
      width: 1_440,
      height: 900
    ),
    appKitFrame: AccessibilityBounds(
      x: 0,
      y: 0,
      width: 1_440,
      height: 900
    )
  )

  @Test("Accessibility bounds become a narrow AppKit underline strip")
  func convertsScreenCoordinates() throws {
    let placements = try #require(
      BearAnnotationLayout.placements(
        for: [
          AccessibilityBounds(x: 100, y: 200, width: 42, height: 20)
        ],
        displays: [primaryDisplay]
      )
    )

    let placement = try #require(placements.first)
    #expect(placement.x == 100)
    #expect(placement.y == 681.2)
    #expect(placement.width == 42)
    #expect(abs(placement.height - 3.6) < 0.001)
  }

  @Test("Every wrapped geometry fragment receives its own placement")
  func placesWrappedFragments() throws {
    let placements = try #require(
      BearAnnotationLayout.placements(
        for: [
          AccessibilityBounds(x: 800, y: 300, width: 80, height: 24),
          AccessibilityBounds(x: 300, y: 327, width: 35, height: 24),
        ],
        displays: [primaryDisplay]
      )
    )

    #expect(placements.count == 2)
    #expect(placements[0].x == 800)
    #expect(placements[1].x == 300)
    #expect(placements[0].y > placements[1].y)
  }

  @Test("Secondary-display coordinates map into its AppKit frame")
  func convertsSecondaryDisplay() throws {
    let secondaryDisplay = BearOverlayDisplay(
      accessibilityFrame: AccessibilityBounds(
        x: 1_440,
        y: 100,
        width: 1_920,
        height: 1_080
      ),
      appKitFrame: AccessibilityBounds(
        x: 1_440,
        y: -280,
        width: 1_920,
        height: 1_080
      )
    )
    let placement = try #require(
      BearAnnotationLayout.placements(
        for: [
          AccessibilityBounds(x: 1_540, y: 200, width: 60, height: 20)
        ],
        displays: [primaryDisplay, secondaryDisplay]
      )?.first
    )

    #expect(placement.x == 1_540)
    #expect(placement.y == 681.2)
  }

  @Test("One invalid fragment rejects the complete annotation")
  func rejectsPartialPlacement() {
    let fragments = [
      AccessibilityBounds(x: 100, y: 200, width: 42, height: 20),
      AccessibilityBounds(x: 2_000, y: 200, width: 42, height: 20),
    ]

    #expect(
      BearAnnotationLayout.placements(
        for: fragments,
        displays: [primaryDisplay]
      ) == nil
    )
  }

  @Test("Empty, invalid, and excessive fragment sets are hidden")
  func rejectsUnsafeFragmentSets() {
    #expect(
      BearAnnotationLayout.placements(
        for: [],
        displays: [primaryDisplay]
      ) == nil
    )
    #expect(
      BearAnnotationLayout.placements(
        for: [
          AccessibilityBounds(x: 100, y: 200, width: 0, height: 20)
        ],
        displays: [primaryDisplay]
      ) == nil
    )
    #expect(
      BearAnnotationLayout.placements(
        for: Array(
          repeating: AccessibilityBounds(
            x: 100,
            y: 200,
            width: 10,
            height: 20
          ),
          count: BearAnnotationLayout.maximumFragmentCount + 1
        ),
        displays: [primaryDisplay]
      ) == nil
    )
  }

  @Test("Only an available report while Bear is frontmost may draw")
  func hidesEveryUnsafeState() {
    let fragment = AccessibilityBounds(
      x: 100,
      y: 200,
      width: 42,
      height: 20
    )
    let available = BearCorrectionGeometryReport(
      status: .available,
      bounds: fragment,
      fragments: [fragment]
    )
    let stale = BearCorrectionGeometryReport(
      status: .staleAnchor,
      fragments: [fragment]
    )

    #expect(
      BearAnnotationLayout.visiblePlacements(
        for: available,
        bearIsFrontmost: true,
        displays: [primaryDisplay]
      )?.count == 1
    )
    #expect(
      BearAnnotationLayout.visiblePlacements(
        for: available,
        bearIsFrontmost: false,
        displays: [primaryDisplay]
      ) == nil
    )
    #expect(
      BearAnnotationLayout.visiblePlacements(
        for: stale,
        bearIsFrontmost: true,
        displays: [primaryDisplay]
      ) == nil
    )
  }

  @MainActor
  @Test("Panels cannot activate Typover or intercept the pointer")
  func panelsAreNonactivating() throws {
    let presenter = AppKitBearAnnotationPresenter()
    presenter.show(
      placements: [
        AccessibilityBounds(x: 100, y: 100, width: 40, height: 4),
        AccessibilityBounds(x: 200, y: 200, width: 30, height: 4),
      ]
    )

    #expect(presenter.panels.count == 2)
    for panel in presenter.panels {
      #expect(panel.styleMask.contains(.nonactivatingPanel))
      #expect(panel.ignoresMouseEvents)
      #expect(!panel.canBecomeKey)
      #expect(!panel.canBecomeMain)
      #expect(!panel.collectionBehavior.contains(.canJoinAllSpaces))
    }

    presenter.hide()
    for panel in presenter.panels {
      #expect(!panel.isVisible)
    }
  }

  @MainActor
  @Test(
    "Live Bear overlay annotates and restores the synthetic marker",
    .enabled(
      if: ProcessInfo.processInfo.environment[
        "TYPOVER_RUN_LIVE_BEAR_OVERLAY"
      ] == "1"
    )
  )
  func liveBearOverlay() async throws {
    _ = NSApplication.shared
    let bear = try #require(
      NSRunningApplication.runningApplications(
        withBundleIdentifier: BearAccessibilityProbe.bearBundleIdentifier
      ).first
    )
    bear.activate(options: [.activateAllWindows])
    try await Task.sleep(for: .milliseconds(500))

    let applicationElement = AXUIElementCreateApplication(
      bear.processIdentifier
    )
    let focusedElement = try #require(
      overlayTestElementAttribute(
        applicationElement,
        kAXFocusedUIElementAttribute as CFString
      )
    )
    let probe = BearAccessibilityProbe()
    let focusedWindow = overlayTestElementAttribute(
      applicationElement,
      kAXFocusedWindowAttribute as CFString
    )
    let windowEditors = focusedWindow.map(probe.textAreas(in:)) ?? []
    let applicationEditors = probe.textAreas(in: applicationElement)
    let editorCandidates =
      [probe.nearestTextArea(startingAt: focusedElement)]
      + windowEditors.map(Optional.some)
      + applicationEditors.map(Optional.some)
    let editorMatch = editorCandidates.compactMap { $0 }.lazy.compactMap {
      element -> (AXUIElement, NSString, NSRange)? in
      let candidate = AXBearEditableTextClient(element: element)
      guard let count = candidate.characterCount(),
        let value = candidate.string(
          in: AccessibilityTextRange(location: 0, length: count)
        ) as NSString?
      else {
        return nil
      }
      let range = value.range(of: "Phase 2 marker: teh")
      return range.location == NSNotFound ? nil : (element, value, range)
    }.first
    let (editorElement, _, markerRange) = try #require(editorMatch)
    #expect(
      AXUIElementSetAttributeValue(
        editorElement,
        kAXFocusedAttribute as CFString,
        kCFBooleanTrue
      ) == .success
    )
    try await Task.sleep(for: .milliseconds(100))
    let editor = AXBearEditableTextClient(element: editorElement)
    let originalSelection = try #require(editor.selectedRange())
    let typoRange = AccessibilityTextRange(
      location: markerRange.location + markerRange.length - 3,
      length: 3
    )
    #expect(editor.setSelectedRange(typoRange) == .success)

    let adapter = BearCorrectionAdapter()
    let application = adapter.apply(
      original: "teh",
      replacement: "the",
      at: typoRange
    )
    _ = try #require(application.correctionRecord)

    let presenter = AppKitBearAnnotationPresenter()
    let controller = BearAnnotationOverlayController(
      adapter: adapter,
      presenter: presenter
    )
    controller.track(application)
    #expect(
      await waitForBearOverlay {
        presenter.panels.contains(where: \.isVisible)
      }
    )
    print(
      "Live Bear overlay frames:",
      presenter.panels.filter(\.isVisible).map(\.frame)
    )

    let holdSeconds = Double(
      ProcessInfo.processInfo.environment[
        "TYPOVER_LIVE_OVERLAY_HOLD_SECONDS"
      ] ?? "2"
    ) ?? 2
    try await Task.sleep(for: .seconds(holdSeconds))

    if let finder = NSRunningApplication.runningApplications(
      withBundleIdentifier: "com.apple.finder"
    ).first {
      finder.activate(options: [.activateAllWindows])
      #expect(
        await waitForBearOverlay {
          !presenter.panels.contains(where: \.isVisible)
        }
      )
      bear.activate(options: [.activateAllWindows])
      _ = AXUIElementSetAttributeValue(
        editorElement,
        kAXFocusedAttribute as CFString,
        kCFBooleanTrue
      )
      #expect(
        await waitForBearOverlay {
          presenter.panels.contains(where: \.isVisible)
        }
      )
    }

    #expect(editor.setSelectedRange(typoRange) == .success)
    #expect(editor.replaceSelectedText(with: "thy") == .success)
    #expect(
      await waitForBearOverlay {
        !presenter.panels.contains(where: \.isVisible)
      }
    )
    #expect(editor.setSelectedRange(typoRange) == .success)
    #expect(editor.replaceSelectedText(with: "the") == .success)
    #expect(
      await waitForBearOverlay {
        presenter.panels.contains(where: \.isVisible)
      }
    )

    let restoration = adapter.changeBack(application)
    #expect(
      restoration.report.status
        == BearCorrectionRestorationStatus.restored
    )
    controller.stop()
    #expect(editor.setSelectedRange(originalSelection) == .success)
  }

}

@MainActor
private func waitForBearOverlay(
  timeout: Duration = .seconds(2),
  condition: () -> Bool
) async -> Bool {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)
  while clock.now < deadline {
    if condition() {
      return true
    }
    try? await Task.sleep(for: .milliseconds(25))
  }
  return condition()
}

private func overlayTestElementAttribute(
  _ element: AXUIElement,
  _ name: CFString
) -> AXUIElement? {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, name, &value) == .success,
    let value,
    CFGetTypeID(value) == AXUIElementGetTypeID()
  else {
    return nil
  }
  return unsafeDowncast(value, to: AXUIElement.self)
}
