import AppKit
import ApplicationServices
import Testing
import TypoverBearAdapter
import TypoverCore

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

  @Test("The menu is concise, ordered, deduplicated, and bounded")
  func buildsConciseMenu() {
    let application = overlayApplication()
    let items = BearAnnotationMenuModel.items(
      for: application,
      alternatives: [
        "the",
        "ten",
        "tech",
        "tea",
        "ten",
        "them",
        "then",
        "there",
        "extra",
      ]
    )

    #expect(items.first?.title == "Revert to “teh”")
    #expect(items.first?.action == .changeBack)
    #expect(items.count == 1 + BearAnnotationMenuModel.maximumAlternativeCount)
    #expect(items[1].title == "ten")
    #expect(items[1].beginsAlternativeSection)
    #expect(items.dropFirst(2).allSatisfy { !$0.beginsAlternativeSection })
    #expect(items.map(\.title).allSatisfy { !$0.contains("Keep Existing") })
    #expect(
      items.dropFirst().allSatisfy {
        !$0.title.hasPrefix("Change to ")
      }
    )
  }

  @Test("Unsafe alternative labels never enter the menu")
  func filtersUnsafeAlternatives() {
    let items = BearAnnotationMenuModel.items(
      for: overlayApplication(),
      alternatives: [
        "",
        "   ",
        "line\nbreak",
        String(repeating: "x", count: 161),
      ]
    )

    #expect(items.count == 1)
    #expect(items[0].action == .changeBack)
  }

  @MainActor
  @Test("Panels stay nonactivating with a narrow accessible hit target")
  func panelsAreNonactivating() throws {
    let presenter = AppKitBearAnnotationPresenter()
    presenter.show(
      placements: [
        AccessibilityBounds(x: 100, y: 100, width: 40, height: 4),
        AccessibilityBounds(x: 200, y: 200, width: 30, height: 4),
      ],
      interaction: overlayInteraction()
    )

    #expect(presenter.panels.count == 2)
    for panel in presenter.panels {
      #expect(panel.styleMask.contains(.nonactivatingPanel))
      #expect(!panel.ignoresMouseEvents)
      #expect(!panel.canBecomeKey)
      #expect(!panel.canBecomeMain)
      #expect(!panel.collectionBehavior.contains(.canJoinAllSpaces))
    }
    #expect(presenter.panels[0].frame.width == 48)
    #expect(presenter.panels[0].frame.height == 12)
    #expect(presenter.panels[0].isAccessibilityElement())
    #expect(
      presenter.panels[0].accessibilityRole() == .window
    )
    #expect(
      presenter.panels[0].accessibilitySubrole() == .floatingWindow
    )
    #expect(
      presenter.panels[0].accessibilityIdentifier()
        == "typover.bear.correction-overlay"
    )
    #expect(
      presenter.panels[0].accessibilityChildren()?.count == 1
    )
    #expect(!presenter.panels[1].isAccessibilityElement())
    #expect(presenter.panels[1].accessibilityChildren()?.isEmpty == true)
    #expect(
      presenter.panels[0].contentView?.isAccessibilityElement() == true
    )
    #expect(
      presenter.panels[0].contentView?.accessibilityIdentifier()
        == "typover.bear.correction-options"
    )
    #expect(
      presenter.panels[0].contentView?.accessibilityHelp()
        == "Opens the menu for reverting this correction or choosing another suggestion."
    )

    presenter.hide()
    for panel in presenter.panels {
      #expect(!panel.isVisible)
    }
  }

  @MainActor
  @Test("An accessible menu session retains its action target")
  func accessibleMenuSessionRetainsTarget() throws {
    var selectedAction: BearAnnotationAction?
    let session = BearAnnotationMenuSession(
      interaction: overlayInteraction { action in
        selectedAction = action
      }
    )

    let menuItem = session.menu.items[0]
    let target = menuItem.target
    let action = try #require(menuItem.action)
    #expect(target != nil)
    #expect(NSStringFromSelector(action) == "performMenuItem:")
    #expect(target?.responds(to: action) == true)
    #expect(
      NSApplication.shared.sendAction(
        action,
        to: target,
        from: menuItem
      )
    )
    #expect(selectedAction == .changeBack)
  }

  @MainActor
  @Test("Change Back finishes tracking through the guarded service")
  func changeBackFinishesTracking() async {
    let presenter = SpyBearAnnotationPresenter()
    let completion = BearOverlayCompletionSpy()
    let resolution = BearOverlayResolutionSpy()
    let controller = testController(
      presenter: presenter,
      service: StubBearCorrectionService()
    )
    controller.trackWithResolution(
      overlayApplication(),
      alternatives: ["ten"],
      onInteractionLatency: { elapsed in
        completion.interactionLatency = elapsed
      },
      onResolution: { outcome in
        resolution.value = outcome
      },
      onFinished: {
        completion.didFinish = true
      }
    )
    #expect(
      await waitForBearOverlay {
        presenter.interaction != nil
      }
    )

    presenter.interaction?.handler(.changeBack)

    #expect(
      await waitForBearOverlay {
        completion.didFinish
      }
    )
    #expect(!presenter.isVisible)
    #expect(resolution.value == .changedBack)
    #expect(completion.interactionLatency != nil)
    #expect(completion.interactionLatency ?? .zero >= .zero)
  }

  @MainActor
  @Test("Multiple corrections keep independent overlays and actions")
  func multipleCorrectionsRemainIndependent() async {
    let service = StubBearCorrectionService()
    var presenters: [SpyBearAnnotationPresenter] = []
    let collection = BearAnnotationOverlayCollectionController(
      maximumTrackedCorrections: 4
    ) {
      let presenter = SpyBearAnnotationPresenter()
      presenters.append(presenter)
      return testController(
        presenter: presenter,
        service: service,
        handlesKeyboardShortcut: false
      )
    }
    let firstResolution = BearOverlayResolutionSpy()
    let secondResolution = BearOverlayResolutionSpy()

    collection.trackWithResolution(
      overlayApplication(),
      alternatives: ["ten"],
      onResolution: { firstResolution.value = $0 }
    )
    collection.trackWithResolution(
      overlayApplication(replacement: "receive"),
      alternatives: ["receiver"],
      onResolution: { secondResolution.value = $0 }
    )

    #expect(
      await waitForBearOverlay {
        presenters.count == 2
          && presenters.allSatisfy(\.isVisible)
      }
    )
    #expect(collection.trackedCorrectionCount == 2)

    presenters[0].interaction?.handler(.changeBack)

    #expect(
      await waitForBearOverlay {
        collection.trackedCorrectionCount == 1
          && !presenters[0].isVisible
          && presenters[1].isVisible
      }
    )
    #expect(firstResolution.value == .changedBack)
    #expect(secondResolution.value == nil)
    collection.stop()
  }

  @MainActor
  @Test("Changing back correction five preserves twenty repeated overlays")
  func changeBackPreservesRepeatedCorrectionCollection() async {
    let service = CoordinatedEditBearCorrectionService(
      reanchorDelay: 0.002
    )
    var presenters: [SpyBearAnnotationPresenter] = []
    let collection = BearAnnotationOverlayCollectionController(
      maximumTrackedCorrections: 24
    ) {
      let presenter = SpyBearAnnotationPresenter()
      presenters.append(presenter)
      return testController(
        presenter: presenter,
        service: service,
        handlesKeyboardShortcut: false
      )
    }

    for index in 0..<21 {
      collection.trackWithResolution(
        anchoredOverlayApplication(location: index * 4)
      )
    }
    #expect(
      await waitForBearOverlay {
        presenters.count == 21 && presenters.allSatisfy(\.isVisible)
      }
    )

    presenters[4].interaction?.handler(.changeBack)

    #expect(
      await waitForBearOverlay {
        collection.trackedCorrectionCount == 20
          && !presenters[4].isVisible
          && presenters.enumerated().allSatisfy { index, presenter in
            index == 4 || presenter.isVisible
          }
          && service.reanchoredRanges.count == 20
      }
    )
    #expect(
      Set(service.reanchoredRanges.map(\.location))
        == Set((0..<21).filter { $0 != 4 }.map { $0 * 4 })
    )
    #expect(service.maximumConcurrentReanchors == 1)
    collection.stop()
  }

  @MainActor
  @Test("A length-changing alternative shifts later overlays only")
  func alternativeTransformsSiblingRanges() async {
    let service = CoordinatedEditBearCorrectionService()
    var presenters: [SpyBearAnnotationPresenter] = []
    let collection = BearAnnotationOverlayCollectionController(
      maximumTrackedCorrections: 4
    ) {
      let presenter = SpyBearAnnotationPresenter()
      presenters.append(presenter)
      return testController(
        presenter: presenter,
        service: service,
        handlesKeyboardShortcut: false
      )
    }
    collection.trackWithResolution(
      anchoredOverlayApplication(location: 2)
    )
    collection.trackWithResolution(
      anchoredOverlayApplication(location: 10),
      alternatives: ["there"]
    )
    collection.trackWithResolution(
      anchoredOverlayApplication(location: 11)
    )
    collection.trackWithResolution(
      anchoredOverlayApplication(location: 20)
    )
    #expect(
      await waitForBearOverlay {
        presenters.count == 4 && presenters.allSatisfy(\.isVisible)
      }
    )

    presenters[1].interaction?.handler(.chooseAlternative("there"))

    #expect(
      await waitForBearOverlay {
        collection.trackedCorrectionCount == 3
          && presenters[0].isVisible
          && presenters[1].isVisible
          && !presenters[2].isVisible
          && presenters[3].isVisible
          && service.reanchoredRanges.count == 2
      }
    )
    #expect(Set(service.reanchoredRanges.map(\.location)) == [2, 22])
    collection.stop()
  }

  @Test("Verified edit range transforms preserve, shift, or reject")
  func verifiedEditRangeTransform() {
    let edit = BearAnnotationVerifiedEdit(
      replacedRange: AccessibilityTextRange(location: 10, length: 3),
      replacementLength: 5
    )

    #expect(
      edit.transformedRange(
        for: AccessibilityTextRange(location: 2, length: 3)
      ) == AccessibilityTextRange(location: 2, length: 3)
    )
    #expect(
      edit.transformedRange(
        for: AccessibilityTextRange(location: 20, length: 3)
      ) == AccessibilityTextRange(location: 22, length: 3)
    )
    #expect(
      edit.transformedRange(
        for: AccessibilityTextRange(location: 11, length: 3)
      ) == nil
    )
  }

  @MainActor
  @Test("The correction collection prunes its oldest overlay")
  func collectionIsBounded() async {
    let service = StubBearCorrectionService()
    var presenters: [SpyBearAnnotationPresenter] = []
    let collection = BearAnnotationOverlayCollectionController(
      maximumTrackedCorrections: 2
    ) {
      let presenter = SpyBearAnnotationPresenter()
      presenters.append(presenter)
      return testController(
        presenter: presenter,
        service: service,
        handlesKeyboardShortcut: false
      )
    }

    collection.trackWithResolution(overlayApplication())
    collection.trackWithResolution(overlayApplication(replacement: "one"))
    collection.trackWithResolution(overlayApplication(replacement: "two"))

    #expect(
      await waitForBearOverlay {
        presenters.count == 3
          && !presenters[0].isVisible
          && presenters[1].isVisible
          && presenters[2].isVisible
      }
    )
    #expect(collection.trackedCorrectionCount == 2)
    collection.stop()
  }

  @MainActor
  @Test("Choosing an alternative refreshes the menu around its new record")
  func alternativeRefreshesTracking() async {
    let presenter = SpyBearAnnotationPresenter()
    let resolution = BearOverlayResolutionSpy()
    let updatedApplication = overlayApplication(replacement: "ten")
    let service = StubBearCorrectionService(
      alternative: BearCorrectionAlternativeApplication(
        report: BearCorrectionRetargetReport(
          status: .applied,
          replacementReport: updatedApplication.report
        ),
        application: updatedApplication
      )
    )
    let controller = testController(
      presenter: presenter,
      service: service
    )
    controller.trackWithResolution(
      overlayApplication(),
      alternatives: ["ten", "tech"],
      onResolution: { outcome in
        resolution.value = outcome
      },
      onFinished: nil
    )
    #expect(
      await waitForBearOverlay {
        presenter.interaction != nil
      }
    )

    presenter.interaction?.handler(.chooseAlternative("ten"))

    #expect(
      await waitForBearOverlay {
        presenter.interaction?.items.contains {
          $0.action == .chooseAlternative("the")
        } == true
      }
    )
    #expect(
      presenter.interaction?.items.contains {
        $0.action == .chooseAlternative("ten")
      } == false
    )
    #expect(resolution.value == .choseAlternative("ten"))
    controller.stop()
  }

  @MainActor
  @Test("A superseded correction ends the preview session")
  func supersededGeometryFinishesTracking() async {
    let presenter = SpyBearAnnotationPresenter()
    let completion = BearOverlayCompletionSpy()
    let service = StubBearCorrectionService(
      geometryReport: BearCorrectionGeometryReport(status: .superseded)
    )
    let controller = testController(
      presenter: presenter,
      service: service
    )

    controller.track(overlayApplication()) {
      completion.didFinish = true
    }

    #expect(
      await waitForBearOverlay {
        completion.didFinish
      }
    )
    #expect(!presenter.isVisible)
  }

  @MainActor
  @Test("A temporary stale anchor hides without ending the session")
  func staleGeometryRemainsTrackable() async {
    let presenter = SpyBearAnnotationPresenter()
    let completion = BearOverlayCompletionSpy()
    let service = StubBearCorrectionService(
      geometryReport: BearCorrectionGeometryReport(status: .staleAnchor)
    )
    let controller = testController(
      presenter: presenter,
      service: service
    )

    controller.track(overlayApplication()) {
      completion.didFinish = true
    }

    #expect(
      !(await waitForBearOverlay(timeout: .milliseconds(150)) {
        completion.didFinish
      })
    )
    #expect(!presenter.isVisible)
    controller.stop()
  }

  @MainActor
  @Test("A stale anchor after a text change ends the session")
  func valueChangeWithStaleAnchorFinishesTracking() async {
    let presenter = SpyBearAnnotationPresenter()
    let completion = BearOverlayCompletionSpy()
    let monitor = StubBearInvalidationMonitor()
    let service = StubBearCorrectionService(
      geometryReport: BearCorrectionGeometryReport(status: .staleAnchor)
    )
    let controller = testController(
      presenter: presenter,
      service: service,
      invalidationMonitor: monitor
    )

    controller.track(overlayApplication()) {
      completion.didFinish = true
    }
    monitor.send(.valueChanged)

    #expect(
      await waitForBearOverlay {
        completion.didFinish
      }
    )
    #expect(!presenter.isVisible)
  }

  @MainActor
  @Test("Rapid text changes debounce overlay geometry work")
  func rapidTextChangesDebounceGeometry() async throws {
    let presenter = SpyBearAnnotationPresenter()
    let monitor = StubBearInvalidationMonitor()
    let controller = testController(
      presenter: presenter,
      service: StubBearCorrectionService(),
      invalidationMonitor: monitor,
      textChangeRefreshDelay: .milliseconds(100)
    )

    controller.track(overlayApplication())
    #expect(
      await waitForBearOverlay {
        presenter.showCount == 1
      }
    )

    monitor.send(.valueChanged)
    try await Task.sleep(for: .milliseconds(60))
    monitor.send(.selectionChanged)
    try await Task.sleep(for: .milliseconds(60))
    #expect(presenter.showCount == 1)
    #expect(!presenter.isVisible)

    #expect(
      await waitForBearOverlay(timeout: .milliseconds(100)) {
        presenter.showCount == 2
      }
    )
    controller.stop()
  }

  @MainActor
  @Test("Bear termination ends the interaction permanently")
  func bearTerminationFinishesTracking() async {
    let presenter = SpyBearAnnotationPresenter()
    let completion = BearOverlayCompletionSpy()
    let controller = testController(
      presenter: presenter,
      service: StubBearCorrectionService()
    )
    controller.track(overlayApplication()) {
      completion.didFinish = true
    }
    #expect(
      await waitForBearOverlay {
        presenter.isVisible
      }
    )

    controller.handleWorkspaceApplicationEvent(
      name: NSWorkspace.didTerminateApplicationNotification,
      bundleIdentifier: BearAccessibilityProbe.bearBundleIdentifier
    )

    #expect(completion.didFinish)
    #expect(!presenter.isVisible)

    controller.handleWorkspaceApplicationEvent(
      name: NSWorkspace.didActivateApplicationNotification,
      bundleIdentifier: BearAccessibilityProbe.bearBundleIdentifier
    )
    #expect(!presenter.isVisible)
  }

  @MainActor
  @Test("Another app terminating does not end the Bear interaction")
  func unrelatedTerminationPreservesTracking() async {
    let presenter = SpyBearAnnotationPresenter()
    let completion = BearOverlayCompletionSpy()
    let controller = testController(
      presenter: presenter,
      service: StubBearCorrectionService()
    )
    controller.track(overlayApplication()) {
      completion.didFinish = true
    }
    #expect(
      await waitForBearOverlay {
        presenter.isVisible
      }
    )

    controller.handleWorkspaceApplicationEvent(
      name: NSWorkspace.didTerminateApplicationNotification,
      bundleIdentifier: "com.example.OtherApp"
    )

    #expect(!completion.didFinish)
    #expect(
      await waitForBearOverlay {
        presenter.isVisible
      }
    )
    controller.stop()
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
    try BearLiveFixtureLauncher().openStableNote()
    var runningBear: NSRunningApplication?
    #expect(
      await waitForBearOverlay(timeout: .seconds(5)) {
        runningBear =
          NSRunningApplication.runningApplications(
            withBundleIdentifier: BearAccessibilityProbe.bearBundleIdentifier
          ).first
        return runningBear != nil
      }
    )
    let bear = try #require(runningBear)
    bear.activate(options: [.activateAllWindows])
    #expect(
      await waitForBearOverlay {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier
          == BearAccessibilityProbe.bearBundleIdentifier
        {
          return true
        }
        bear.activate(options: [.activateAllWindows])
        return false
      }
    )
    let applicationElement = AXUIElementCreateApplication(
      bear.processIdentifier
    )
    func matchingEditor() -> (AXUIElement, NSString, NSRange)? {
      guard
        let focusedElement = overlayTestElementAttribute(
          applicationElement,
          kAXFocusedUIElementAttribute as CFString
        )
      else {
        return nil
      }
      let probe = BearAccessibilityProbe()
      let focusedWindow = overlayTestElementAttribute(
        applicationElement,
        kAXFocusedWindowAttribute as CFString
      )
      let inactiveEditor = focusedWindow.flatMap { window -> AXUIElement? in
        let candidates = probe.textAreas(in: window)
        return candidates.count == 1 ? candidates.first : nil
      }
      guard
        let editorElement = probe.nearestTextArea(startingAt: focusedElement)
          ?? inactiveEditor
      else {
        return nil
      }
      let candidate = AXBearEditableTextClient(element: editorElement)
      guard let count = candidate.characterCount(),
        let value = candidate.string(
          in: AccessibilityTextRange(location: 0, length: count)
        ) as NSString?
      else {
        return nil
      }
      let range = value.range(of: "Phase 2 marker: teh")
      return range.location == NSNotFound
        ? nil
        : (editorElement, value, range)
    }
    var editorMatch: (AXUIElement, NSString, NSRange)?
    #expect(
      await waitForBearOverlay(timeout: .seconds(5)) {
        editorMatch = matchingEditor()
        return editorMatch != nil
      }
    )
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
    let originalCharacterCount = try #require(editor.characterCount())
    let liveTail = "Typover live interaction tail."
    let liveContinuation = " Typover-live-continued-typing."
    #expect(
      editor.setSelectedRange(
        AccessibilityTextRange(
          location: originalCharacterCount,
          length: 0
        )
      ) == .success
    )
    #expect(editor.replaceSelectedText(with: liveTail) == .success)
    defer {
      cleanupLiveBearOverlayFixture(
        editor: editor,
        tail: liveTail,
        continuation: liveContinuation,
        originalSelection: originalSelection
      )
    }
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
    #expect(
      editor.setSelectedRange(
        AccessibilityTextRange(
          location: typoRange.location + typoRange.length,
          length: 0
        )
      ) == .success
    )
    #expect(editor.replaceSelectedText(with: liveContinuation) == .success)
    let requestedInteractionSelection = AccessibilityTextRange(
      location: typoRange.location + typoRange.length
        + liveContinuation.utf16.count,
      length: 0
    )
    #expect(
      editor.setSelectedRange(requestedInteractionSelection) == .success
    )

    let presenter = AppKitBearAnnotationPresenter()
    let controller = BearAnnotationOverlayController(
      adapter: adapter,
      presenter: presenter
    )
    bear.activate(options: [.activateAllWindows])
    #expect(
      await waitForBearOverlay {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
          == BearAccessibilityProbe.bearBundleIdentifier
      }
    )
    print(
      "Live Bear preflight:",
      NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none",
      adapter.geometry(for: application).status.rawValue
    )
    controller.track(application, alternatives: ["tech"])
    #expect(
      await waitForBearOverlay {
        presenter.panels.contains(where: \.isVisible)
      }
    )
    print(
      "Live Bear overlay frames:",
      presenter.panels.filter(\.isVisible).map(\.frame)
    )

    let holdSeconds =
      Double(
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

    let interactionSelection = try #require(editor.selectedRange())
    let firstInteraction = try #require(
      (presenter.panels.first?.contentView as? BearSquiggleView)?.interaction
    )
    firstInteraction.handler(.chooseAlternative("tech"))
    let alternativeRange = AccessibilityTextRange(
      location: typoRange.location,
      length: "tech".utf16.count
    )
    #expect(
      await waitForBearOverlay {
        editor.string(in: alternativeRange) == "tech"
          && liveBearEditorContains(editor, liveContinuation)
          && presenter.panels.contains(where: \.isVisible)
          && editor.selectedRange()
            == AccessibilityTextRange(
              location: interactionSelection.location + 1,
              length: 0
            )
      }
    )

    let alternativeInteraction = try #require(
      (presenter.panels.first?.contentView as? BearSquiggleView)?.interaction
    )
    alternativeInteraction.handler(.changeBack)
    let changeBackSettled = await waitForBearOverlay {
      editor.string(in: typoRange) == "teh"
        && liveBearEditorContains(editor, liveContinuation)
        && !presenter.panels.contains(where: \.isVisible)
        && editor.selectedRange() == interactionSelection
    }
    if !changeBackSettled {
      print(
        "Live Bear Change Back diagnostics:",
        "word=\(editor.string(in: typoRange) ?? "unavailable")",
        "continuation=\(liveBearEditorContains(editor, liveContinuation))",
        "visible=\(presenter.panels.contains(where: \.isVisible))",
        "selection=\(String(describing: editor.selectedRange()))",
        "expectedSelection=\(interactionSelection)"
      )
    }
    #expect(changeBackSettled)
    controller.stop()
  }

}

private func overlayApplication(
  replacement: String = "the"
) -> BearCorrectionApplication {
  let correction = Correction(original: "teh", replacement: replacement)
  return BearCorrectionApplication(
    report: BearExactRangeReplacementReport(
      status: .applied,
      writeOccurred: true,
      targetRange: AccessibilityTextRange(location: 10, length: 3),
      replacementRange: AccessibilityTextRange(location: 10, length: 3),
      surroundingContextVerified: true,
      caretRestored: true
    ),
    correction: correction,
    correctionRecord: CorrectionRecord(correction: correction)
  )
}

private func anchoredOverlayApplication(
  location: Int,
  replacement: String = "the",
  documentLength: Int = 100
) -> BearCorrectionApplication {
  let correction = Correction(original: "teh", replacement: replacement)
  let range = AccessibilityTextRange(
    location: location,
    length: replacement.utf16.count
  )
  return BearCorrectionApplication(
    report: BearExactRangeReplacementReport(
      status: .applied,
      writeOccurred: true,
      targetRange: range,
      replacementRange: range,
      surroundingContextVerified: true,
      caretRestored: true
    ),
    correction: correction,
    correctionRecord: CorrectionRecord(correction: correction),
    correctionAnchor: BearCorrectionAnchor(
      correctionRange: range,
      documentLength: documentLength,
      leadingContext: " ",
      trailingContext: " "
    )
  )
}

@MainActor
private func testController(
  presenter: SpyBearAnnotationPresenter,
  service: any BearCorrectionServicing,
  invalidationMonitor: StubBearInvalidationMonitor =
    StubBearInvalidationMonitor(),
  handlesKeyboardShortcut: Bool = true,
  textChangeRefreshDelay: Duration = .zero
) -> BearAnnotationOverlayController {
  BearAnnotationOverlayController(
    adapter: service,
    presenter: presenter,
    invalidationMonitor: invalidationMonitor,
    frontmostBundleIdentifier: {
      BearAccessibilityProbe.bearBundleIdentifier
    },
    displays: {
      [
        BearOverlayDisplay(
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
      ]
    },
    fallbackRefreshInterval: .seconds(60),
    textChangeRefreshDelay: textChangeRefreshDelay,
    handlesKeyboardShortcut: handlesKeyboardShortcut
  )
}

private final class CoordinatedEditBearCorrectionService:
  BearCorrectionServicing, @unchecked Sendable
{
  private let lock = NSLock()
  private let reanchorDelay: TimeInterval
  private var storedReanchoredRanges: [AccessibilityTextRange] = []
  private var activeReanchorCount = 0
  private var storedMaximumConcurrentReanchors = 0

  init(reanchorDelay: TimeInterval = 0) {
    self.reanchorDelay = reanchorDelay
  }

  var reanchoredRanges: [AccessibilityTextRange] {
    lock.withLock { storedReanchoredRanges }
  }

  var maximumConcurrentReanchors: Int {
    lock.withLock { storedMaximumConcurrentReanchors }
  }

  func geometry(
    for application: BearCorrectionApplication
  ) -> BearCorrectionGeometryReport {
    guard let range = application.correctionAnchor?.correctionRange else {
      return BearCorrectionGeometryReport(status: .staleAnchor)
    }
    let bounds = AccessibilityBounds(
      x: Double(100 + range.location),
      y: 100,
      width: 40,
      height: 20
    )
    return BearCorrectionGeometryReport(
      status: .available,
      resolvedRange: range,
      bounds: bounds,
      fragments: [bounds]
    )
  }

  func changeBack(
    _ application: BearCorrectionApplication
  ) -> BearCorrectionRestoration {
    BearCorrectionRestoration(
      report: BearCorrectionRestorationReport(
        status: .restored,
        writeOccurred: true,
        matchedRange: application.correctionAnchor?.correctionRange
      ),
      correctionRecord: CorrectionRecord(
        correction: application.correction,
        disposition: .restored
      )
    )
  }

  func chooseAlternative(
    _ replacement: String,
    for application: BearCorrectionApplication
  ) -> BearCorrectionAlternativeApplication {
    guard let oldAnchor = application.correctionAnchor else {
      return BearCorrectionAlternativeApplication(
        report: BearCorrectionRetargetReport(status: .invalidated),
        application: nil
      )
    }
    let newRange = AccessibilityTextRange(
      location: oldAnchor.correctionRange.location,
      length: replacement.utf16.count
    )
    let correction = Correction(
      original: application.correction.original,
      replacement: replacement
    )
    let replacementReport = BearExactRangeReplacementReport(
      status: .applied,
      writeOccurred: true,
      targetRange: oldAnchor.correctionRange,
      replacementRange: newRange,
      surroundingContextVerified: true,
      caretRestored: true
    )
    return BearCorrectionAlternativeApplication(
      report: BearCorrectionRetargetReport(
        status: .applied,
        writeOccurred: true,
        matchedRange: oldAnchor.correctionRange,
        candidateCount: 1,
        replacementReport: replacementReport
      ),
      application: BearCorrectionApplication(
        report: replacementReport,
        correction: correction,
        correctionRecord: CorrectionRecord(correction: correction),
        correctionAnchor: BearCorrectionAnchor(
          correctionRange: newRange,
          documentLength: oldAnchor.documentLength
            + newRange.length - oldAnchor.correctionRange.length,
          leadingContext: " ",
          trailingContext: " "
        )
      )
    )
  }

  func reanchor(
    _ application: BearCorrectionApplication,
    at targetRange: AccessibilityTextRange
  ) -> BearCorrectionReanchoredApplication {
    lock.withLock {
      activeReanchorCount += 1
      storedMaximumConcurrentReanchors = max(
        storedMaximumConcurrentReanchors,
        activeReanchorCount
      )
      storedReanchoredRanges.append(targetRange)
    }
    if reanchorDelay > 0 {
      Thread.sleep(forTimeInterval: reanchorDelay)
    }
    lock.withLock {
      activeReanchorCount -= 1
    }
    let anchor = BearCorrectionAnchor(
      correctionRange: targetRange,
      documentLength: application.correctionAnchor?.documentLength ?? 100,
      leadingContext: " ",
      trailingContext: " "
    )
    return BearCorrectionReanchoredApplication(
      status: .reanchored,
      application: BearCorrectionApplication(
        report: application.report,
        correction: application.correction,
        correctionRecord: application.correctionRecord,
        correctionAnchor: anchor
      )
    )
  }

  func stabilizeSelection(
    _: BearCorrectionSelectionStabilizationRequest
  ) -> BearCorrectionSelectionStabilizationStatus {
    .alreadyStable
  }
}

@MainActor
private func overlayInteraction(
  handler: @escaping @MainActor @Sendable (BearAnnotationAction) -> Void = {
    _ in
  }
) -> BearAnnotationInteraction {
  BearAnnotationInteraction(
    items: BearAnnotationMenuModel.items(
      for: overlayApplication(),
      alternatives: ["ten", "tech"]
    ),
    accessibilityLabel: "Correction options for the"
  ) { action in
    handler(action)
  }
}

@MainActor
private final class SpyBearAnnotationPresenter: BearAnnotationPresenting {
  private(set) var isVisible = false
  private(set) var showCount = 0
  private(set) var interaction: BearAnnotationInteraction?
  private(set) var placements: [AccessibilityBounds] = []

  func show(
    placements: [AccessibilityBounds],
    interaction: BearAnnotationInteraction
  ) {
    isVisible = true
    showCount += 1
    self.placements = placements
    self.interaction = interaction
  }

  func showMenu() {}

  func hide() {
    isVisible = false
  }
}

@MainActor
private final class StubBearInvalidationMonitor:
  BearAccessibilityInvalidationObserving
{
  private typealias Handler =
    @MainActor @Sendable (
      BearAccessibilityInvalidationEvent
    ) -> Void

  private var handler: Handler?

  func start(
    handler:
      @escaping @MainActor @Sendable (
        BearAccessibilityInvalidationEvent
      ) -> Void
  ) -> Bool {
    self.handler = handler
    return true
  }

  func stop() {
    handler = nil
  }

  func send(_ event: BearAccessibilityInvalidationEvent) {
    handler?(event)
  }
}

private struct StubBearCorrectionService: BearCorrectionServicing {
  let alternative: BearCorrectionAlternativeApplication
  let geometryReport: BearCorrectionGeometryReport?

  init(
    alternative: BearCorrectionAlternativeApplication =
      BearCorrectionAlternativeApplication(
        report: BearCorrectionRetargetReport(status: .invalidated),
        application: nil
      ),
    geometryReport: BearCorrectionGeometryReport? = nil
  ) {
    self.alternative = alternative
    self.geometryReport = geometryReport
  }

  func geometry(
    for _: BearCorrectionApplication
  ) -> BearCorrectionGeometryReport {
    if let geometryReport {
      return geometryReport
    }
    let bounds = AccessibilityBounds(
      x: 100,
      y: 100,
      width: 40,
      height: 20
    )
    return BearCorrectionGeometryReport(
      status: .available,
      bounds: bounds,
      fragments: [bounds]
    )
  }

  func changeBack(
    _ application: BearCorrectionApplication
  ) -> BearCorrectionRestoration {
    BearCorrectionRestoration(
      report: BearCorrectionRestorationReport(status: .restored),
      correctionRecord: CorrectionRecord(
        correction: application.correction,
        disposition: .restored
      )
    )
  }

  func chooseAlternative(
    _: String,
    for _: BearCorrectionApplication
  ) -> BearCorrectionAlternativeApplication {
    alternative
  }

  func reanchor(
    _ application: BearCorrectionApplication,
    at targetRange: AccessibilityTextRange
  ) -> BearCorrectionReanchoredApplication {
    guard let oldAnchor = application.correctionAnchor else {
      return BearCorrectionReanchoredApplication(
        status: .invalidRequest,
        application: nil
      )
    }
    let anchor = BearCorrectionAnchor(
      correctionRange: targetRange,
      documentLength: oldAnchor.documentLength,
      leadingContext: String(repeating: "l", count: oldAnchor.leadingContextLength),
      trailingContext: String(repeating: "t", count: oldAnchor.trailingContextLength)
    )
    return BearCorrectionReanchoredApplication(
      status: .reanchored,
      application: BearCorrectionApplication(
        report: application.report,
        correction: application.correction,
        correctionRecord: application.correctionRecord,
        correctionAnchor: anchor
      )
    )
  }

  func stabilizeSelection(
    _: BearCorrectionSelectionStabilizationRequest
  ) -> BearCorrectionSelectionStabilizationStatus {
    .alreadyStable
  }
}

@MainActor
private final class BearOverlayCompletionSpy {
  var didFinish = false
  var interactionLatency: Duration?
}

@MainActor
private final class BearOverlayResolutionSpy {
  var value: BearAnnotationResolution?
}

@MainActor
private func waitForBearOverlay(
  timeout: Duration = .seconds(10),
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

private func cleanupLiveBearOverlayFixture(
  editor: BearEditableTextClient,
  tail: String,
  continuation: String,
  originalSelection: AccessibilityTextRange
) {
  guard let count = editor.characterCount(),
    let value = editor.string(
      in: AccessibilityTextRange(location: 0, length: count)
    ) as NSString?
  else {
    return
  }
  for candidate in ["tech", "the"] {
    let match = value.range(of: "Phase 2 marker: \(candidate)")
    if match.location != NSNotFound {
      let wordRange = AccessibilityTextRange(
        location: match.location + match.length - candidate.utf16.count,
        length: candidate.utf16.count
      )
      _ = editor.setSelectedRange(wordRange)
      _ = editor.replaceSelectedText(with: "teh")
      break
    }
  }
  if let updatedCount = editor.characterCount(),
    let updatedValue = editor.string(
      in: AccessibilityTextRange(location: 0, length: updatedCount)
    ) as NSString?
  {
    let continuationRange = updatedValue.range(of: continuation)
    if continuationRange.location != NSNotFound {
      _ = editor.setSelectedRange(
        AccessibilityTextRange(
          location: continuationRange.location,
          length: continuationRange.length
        )
      )
      _ = editor.replaceSelectedText(with: "")
    }
  }
  if let updatedCount = editor.characterCount(),
    let updatedValue = editor.string(
      in: AccessibilityTextRange(location: 0, length: updatedCount)
    ) as NSString?
  {
    let tailRange = updatedValue.range(of: tail)
    if tailRange.location != NSNotFound {
      _ = editor.setSelectedRange(
        AccessibilityTextRange(
          location: tailRange.location,
          length: tailRange.length
        )
      )
      _ = editor.replaceSelectedText(with: "")
    }
  }
  _ = editor.setSelectedRange(originalSelection)
}

private func liveBearEditorContains(
  _ editor: BearEditableTextClient,
  _ text: String
) -> Bool {
  guard let count = editor.characterCount(),
    let value = editor.string(
      in: AccessibilityTextRange(location: 0, length: count)
    ) as NSString?
  else {
    return false
  }
  return value.range(of: text).location != NSNotFound
}
