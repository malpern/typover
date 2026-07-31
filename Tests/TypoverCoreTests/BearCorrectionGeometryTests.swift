import AppKit
import ApplicationServices
import Foundation
import Testing
import TypoverBearAdapter
import TypoverCore

@testable import TypoverAccessibility

@Suite("Bear correction geometry")
struct BearCorrectionGeometryTests {
  @Test("A visible anchored correction returns usable screen bounds")
  func returnsVisibleBounds() {
    let fixture = makeFixture()

    let report = geometry(fixture)

    #expect(report.status == .available)
    #expect(report.isUsable)
    #expect(report.resolvedRange == fixture.anchor.correctionRange)
    #expect(report.bounds == fixture.bounds)
    #expect(fixture.reader.boundsQueryCount == 3)
  }

  @Test("Typing before a correction shifts its resolved geometry range")
  func reanchorsAfterEarlierTyping() {
    let fixture = makeFixture()
    let insertion = "earlier typing "
    fixture.reader.userReplace(
      AccessibilityTextRange(location: 0, length: 0),
      with: insertion
    )
    fixture.reader.visibleRangeValue = AccessibilityTextRange(
      location: 0,
      length: fixture.reader.text.length
    )

    let report = geometry(fixture)

    #expect(report.status == .available)
    #expect(
      report.resolvedRange?.location
        == fixture.anchor.correctionRange.location + insertion.utf16.count
    )
  }

  @Test("An offscreen correction never requests stale bounds")
  func recognizesOffscreenRange() {
    let fixture = makeFixture(
      visibleRange: AccessibilityTextRange(location: 0, length: 30)
    )

    let report = geometry(fixture)

    #expect(report.status == .offscreen)
    #expect(report.bounds == nil)
    #expect(fixture.reader.boundsQueryCount == 0)
  }

  @Test("A partially visible correction is hidden")
  func recognizesPartiallyVisibleRange() {
    let fixture = makeFixture(
      visibleRange: AccessibilityTextRange(location: 62, length: 40)
    )

    let report = geometry(fixture)

    #expect(report.status == .offscreen)
    #expect(fixture.reader.boundsQueryCount == 0)
  }

  @Test("One changed context side preserves unique geometry")
  func acceptsOneChangedSide() {
    let fixture = makeFixture()
    fixture.reader.userReplace(
      AccessibilityTextRange(
        location: fixture.anchor.correctionRange.location - 2,
        length: 1
      ),
      with: "x"
    )

    let report = geometry(fixture)

    #expect(report.status == .available)
    #expect(report.resolvedRange == fixture.anchor.correctionRange)
    #expect(fixture.reader.boundsQueryCount > 0)
  }

  @Test("Changes on both context sides hide stale geometry")
  func refusesTwoChangedSides() {
    let fixture = makeFixture()
    fixture.reader.userReplace(
      AccessibilityTextRange(
        location: fixture.anchor.correctionRange.location - 2,
        length: 1
      ),
      with: "x"
    )
    fixture.reader.userReplace(
      AccessibilityTextRange(
        location: fixture.anchor.correctionRange.location
          + fixture.anchor.correctionRange.length + 2,
        length: 1
      ),
      with: "y"
    )

    let report = geometry(fixture)

    #expect(report.status == .staleAnchor)
    #expect(report.candidateCount == 0)
    #expect(fixture.reader.boundsQueryCount == 0)
  }

  @Test("Typing immediately after a correction keeps its geometry")
  func remainsVisibleWhileTypingContinues() {
    let fixture = makeFixture()
    fixture.reader.userReplace(
      AccessibilityTextRange(
        location: fixture.anchor.correctionRange.location
          + fixture.anchor.correctionRange.length + 1,
        length: 0
      ),
      with: "newly typed "
    )
    fixture.reader.visibleRangeValue = AccessibilityTextRange(
      location: 0,
      length: fixture.reader.text.length
    )

    let report = geometry(fixture)

    #expect(report.status == .available)
    #expect(report.resolvedRange == fixture.anchor.correctionRange)
  }

  @Test("Duplicated one-sided matches remain ambiguous")
  func refusesAmbiguousOneSidedAnchor() {
    let fixture = makeFixture()
    fixture.reader.userReplace(
      AccessibilityTextRange(
        location: fixture.anchor.correctionRange.location
          + fixture.anchor.correctionRange.length + 1,
        length: 0
      ),
      with: "changed "
    )
    fixture.reader.userReplace(
      AccessibilityTextRange(
        location: fixture.reader.text.length,
        length: 0
      ),
      with: String(repeating: "a", count: 39) + " the different"
    )
    fixture.reader.visibleRangeValue = AccessibilityTextRange(
      location: 0,
      length: fixture.reader.text.length
    )

    let report = geometry(fixture)

    #expect(report.status == .ambiguousAnchor)
    #expect(report.candidateCount > 1)
    #expect(fixture.reader.boundsQueryCount == 0)
  }

  @Test("Duplicated context makes geometry ambiguous")
  func refusesAmbiguousAnchor() {
    let fixture = makeFixture()
    fixture.reader.userReplace(
      AccessibilityTextRange(
        location: fixture.reader.text.length,
        length: 0
      ),
      with: String(repeating: "a", count: 39)
        + " the "
        + String(repeating: "z", count: 39)
    )
    fixture.reader.visibleRangeValue = AccessibilityTextRange(
      location: 0,
      length: fixture.reader.text.length
    )

    let report = geometry(fixture)

    #expect(report.status == .ambiguousAnchor)
    #expect(report.candidateCount > 1)
    #expect(fixture.reader.boundsQueryCount == 0)
  }

  @Test("Production anchors distinguish sixteen repeated corrections")
  func retainsRepeatedProductionAnchors() throws {
    let reader = FakeBearGeometryTextClient(
      text: "# testing\n\n",
      visibleRange: nil,
      boundsResult: .success(
        AccessibilityBounds(x: 100, y: 200, width: 24, height: 18)
      )
    )
    var anchors: [BearCorrectionAnchor] = []

    for _ in 0..<16 {
      let target = AccessibilityTextRange(
        location: reader.text.length,
        length: 3
      )
      reader.userReplace(
        AccessibilityTextRange(
          location: reader.text.length,
          length: 0
        ),
        with: "teh "
      )
      reader.selectedRangeValue = AccessibilityTextRange(
        location: reader.text.length,
        length: 0
      )

      let outcome = BearExactRangeTransaction().applyOutcome(
        BearExactRangeReplacementRequest(
          targetRange: target,
          expectedOriginal: "teh",
          replacement: "the"
        ),
        to: reader
      )

      #expect(outcome.report.status == .applied)
      anchors.append(try #require(outcome.correctionAnchor))
    }

    reader.visibleRangeValue = AccessibilityTextRange(
      location: 0,
      length: reader.text.length
    )
    for anchor in anchors {
      let report = BearCorrectionGeometryTransaction().geometry(
        for: BearCorrectionGeometryRequest(
          anchor: anchor,
          expectedReplacement: "the"
        ),
        in: reader
      )
      #expect(report.status == .available)
      #expect(report.resolvedRange == anchor.correctionRange)
    }
  }

  @Test("A manually changed correction is not annotated")
  func refusesSupersededCorrection() {
    let fixture = makeFixture()
    fixture.reader.userReplace(
      fixture.anchor.correctionRange,
      with: "thy"
    )

    let report = geometry(fixture)

    #expect(report.status == .superseded)
    #expect(fixture.reader.boundsQueryCount == 0)
  }

  @Test("Missing visible-range support is explicit")
  func reportsMissingVisibleRange() {
    let fixture = makeFixture(visibleRange: nil)

    let report = geometry(fixture)

    #expect(report.status == .visibleRangeUnavailable)
    #expect(fixture.reader.boundsQueryCount == 0)
  }

  @Test("Unsupported bounds are distinguished from query failures")
  func reportsBoundsFailures() {
    let unsupported = makeFixture(boundsResult: .unsupported)
    let failed = makeFixture(
      boundsResult: .failed(errorCode: AXError.cannotComplete.rawValue)
    )

    let unsupportedReport = geometry(unsupported)
    let failedReport = geometry(failed)

    #expect(unsupportedReport.status == .boundsUnsupported)
    #expect(failedReport.status == .boundsQueryFailed)
    #expect(failedReport.errorCode == AXError.cannotComplete.rawValue)
  }

  @Test("Zero, negative, and non-finite rectangles are rejected")
  func rejectsInvalidBounds() {
    let invalidBounds = [
      AccessibilityBounds(x: 10, y: 10, width: 0, height: 18),
      AccessibilityBounds(x: 10, y: 10, width: 20, height: -1),
      AccessibilityBounds(x: .infinity, y: 10, width: 20, height: 18),
    ]

    for bounds in invalidBounds {
      let fixture = makeFixture(boundsResult: .success(bounds))
      #expect(geometry(fixture).status == .invalidBounds)
    }
  }

  @Test("A wrapped target is decomposed into line-level fragments")
  func fragmentsWrappedTarget() {
    let fixture = makeFixture()
    let target = fixture.anchor.correctionRange
    fixture.reader.boundsByRange = [
      target: .success(
        AccessibilityBounds(x: 200, y: 100, width: 170, height: 54)
      ),
      AccessibilityTextRange(location: target.location, length: 1): .success(
        AccessibilityBounds(x: 350, y: 100, width: 10, height: 27)
      ),
      AccessibilityTextRange(location: target.location + 1, length: 1):
        .success(
          AccessibilityBounds(x: 360, y: 100, width: 10, height: 27)
        ),
      AccessibilityTextRange(location: target.location + 2, length: 1):
        .success(
          AccessibilityBounds(x: 200, y: 127, width: 10, height: 27)
        ),
    ]

    let report = geometry(fixture)

    #expect(report.status == .available)
    #expect(report.fragments.count == 2)
    #expect(
      report.fragments[0]
        == AccessibilityBounds(x: 350, y: 100, width: 20, height: 27)
    )
    #expect(
      report.fragments[1]
        == AccessibilityBounds(x: 200, y: 127, width: 10, height: 27)
    )
  }

  @Test("Geometry refresh reads only bounded neighborhoods in a long note")
  func readsBoundedNeighborhoods() {
    let leading = String(repeating: "a", count: 2_500) + " "
    let trailing = " " + String(repeating: "z", count: 2_500)
    let text = leading + "the" + trailing
    let range = AccessibilityTextRange(
      location: leading.utf16.count,
      length: 3
    )
    let anchor = BearCorrectionAnchor(
      correctionRange: range,
      documentLength: text.utf16.count,
      leadingContext: String(leading.suffix(40)),
      trailingContext: String(trailing.prefix(40))
    )
    let reader = FakeBearGeometryTextClient(
      text: text,
      visibleRange: AccessibilityTextRange(
        location: range.location - 50,
        length: 103
      ),
      boundsResult: .success(
        AccessibilityBounds(x: 100, y: 200, width: 24, height: 18)
      )
    )

    let report = BearCorrectionGeometryTransaction().geometry(
      for: BearCorrectionGeometryRequest(
        anchor: anchor,
        expectedReplacement: "the"
      ),
      in: reader
    )

    #expect(report.status == .available)
    #expect(reader.maximumStringReadLength < text.utf16.count)
    #expect(reader.maximumStringReadLength <= 848)
  }

  @Test("Geometry reports contain no source or replacement text")
  func reportIsContentFree() throws {
    let report = BearCorrectionGeometryReport(
      status: .available,
      resolvedRange: AccessibilityTextRange(location: 61, length: 3),
      visibleRange: AccessibilityTextRange(location: 0, length: 125),
      bounds: AccessibilityBounds(x: 100, y: 200, width: 24, height: 18),
      candidateCount: 1
    )

    let data = try JSONEncoder().encode(report)
    let json = try #require(String(data: data, encoding: .utf8))

    #expect(!json.contains("teh"))
    #expect(!json.contains("the"))
    #expect(!json.contains("original"))
    #expect(!json.contains("replacement"))
  }

  @Test("The Bear adapter exposes geometry only for applied corrections")
  func adapterGatesGeometry() {
    let fixture = makeFixture()
    let correction = Correction(original: "teh", replacement: "the")
    let report = BearExactRangeReplacementReport(
      status: .applied,
      writeOccurred: true,
      targetRange: fixture.anchor.correctionRange,
      replacementRange: fixture.anchor.correctionRange,
      surroundingContextVerified: true,
      caretRestored: true
    )
    let applied = BearCorrectionApplication(
      report: report,
      correction: correction,
      correctionRecord: CorrectionRecord(correction: correction),
      correctionAnchor: fixture.anchor
    )
    let restored = BearCorrectionApplication(
      report: report,
      correction: correction,
      correctionRecord: CorrectionRecord(
        correction: correction,
        disposition: .restored
      ),
      correctionAnchor: fixture.anchor
    )
    let provider = StubBearGeometryProvider(
      report: BearCorrectionGeometryReport(
        status: .available,
        bounds: fixture.bounds
      )
    )
    let adapter = BearCorrectionAdapter(geometryProvider: provider)

    #expect(adapter.geometry(for: applied).status == .available)
    #expect(adapter.geometry(for: restored).status == .staleAnchor)
  }

  @Test(
    "Live Bear geometry is stable for the synthetic correction",
    .enabled(
      if: ProcessInfo.processInfo.environment[
        "TYPOVER_RUN_LIVE_BEAR_GEOMETRY"
      ] == "1"
    )
  )
  func liveBearGeometry() throws {
    let probe = BearAccessibilityProbe().run()
    let selection = try #require(probe.selectedRange)
    #expect(probe.status == .ready)
    let targetRange: AccessibilityTextRange
    if selection.length == 3 {
      targetRange = selection
    } else {
      #expect(selection.length == 0)
      #expect(selection.location >= 4)
      targetRange = AccessibilityTextRange(
        location: selection.location - 4,
        length: 3
      )
    }

    let adapter = BearCorrectionAdapter()
    let application = adapter.apply(
      original: "teh",
      replacement: "the",
      at: targetRange
    )
    _ = try #require(application.correctionRecord)

    let samples = (0..<3).map { _ in
      adapter.geometry(for: application)
    }
    #expect(samples.allSatisfy { $0.isUsable })
    #expect(Set(samples.compactMap(\.resolvedRange)).count == 1)
    #expect(Set(samples.compactMap(\.bounds)).count == 1)

    let restoration = adapter.changeBack(application)
    #expect(restoration.report.status == .restored)
  }

  @Test(
    "Live Bear geometry covers formatting, wrapping, and offscreen ranges",
    .enabled(
      if: ProcessInfo.processInfo.environment[
        "TYPOVER_RUN_LIVE_BEAR_GEOMETRY_MATRIX"
      ] == "1"
    )
  )
  func liveBearGeometryMatrix() throws {
    let application = try #require(
      NSRunningApplication.runningApplications(
        withBundleIdentifier: BearAccessibilityProbe.bearBundleIdentifier
      ).first
    )
    let applicationElement = AXUIElementCreateApplication(
      application.processIdentifier
    )
    let focusedElement = try #require(
      testElementAttribute(
        applicationElement,
        kAXFocusedUIElementAttribute as CFString
      )
    )
    let editorElement = try #require(
      BearAccessibilityProbe().nearestTextArea(startingAt: focusedElement)
    )
    let editor = AXBearEditableTextClient(element: editorElement)
    let originalSelection = try #require(editor.selectedRange())
    let characterCount = try #require(editor.characterCount())
    let text =
      try #require(
        editor.string(
          in: AccessibilityTextRange(location: 0, length: characterCount)
        )
      ) as NSString
    let markers = [
      "GEOM-TOP",
      "GEOM-HEADING",
      "GEOM-LIST",
      "GEOM-WIDTH",
      "GEOM-LINK",
      "GEOM-CODE",
      "GEOM-WRAP",
      "GEOM-ATTACHMENT-NEAR",
      "GEOM-BOTTOM",
    ]
    var requests: [String: BearCorrectionGeometryRequest] = [:]
    for marker in markers {
      let range = text.range(of: marker)
      #expect(range.location != NSNotFound)
      #expect(
        text.range(
          of: marker,
          options: [],
          range: NSRange(
            location: range.location + range.length,
            length: text.length - range.location - range.length
          )
        ).location == NSNotFound
      )
      requests[marker] = BearCorrectionGeometryRequest(
        anchor: liveAnchor(text: text, correctionRange: range),
        expectedReplacement: marker
      )
    }

    var reports: [String: BearCorrectionGeometryReport] = [:]
    for marker in markers {
      let request = try #require(requests[marker])
      let target = request.anchor.correctionRange
      #expect(editor.setSelectedRange(target) == .success)
      CFRunLoopRunInMode(.defaultMode, 0.15, false)
      let samples = (0..<3).map { _ in
        BearCorrectionGeometryTransaction().geometry(
          for: request,
          in: editor
        )
      }
      #expect(samples.allSatisfy { $0.status == .available })
      #expect(Set(samples.compactMap(\.bounds)).count == 1)
      reports[marker] = samples.last
    }

    let bottomRequest = try #require(requests["GEOM-BOTTOM"])
    #expect(
      editor.setSelectedRange(bottomRequest.anchor.correctionRange) == .success
    )
    CFRunLoopRunInMode(.defaultMode, 0.15, false)
    let topRequest = try #require(requests["GEOM-TOP"])
    let topWhileAtBottom = BearCorrectionGeometryTransaction().geometry(
      for: topRequest,
      in: editor
    )
    #expect(topWhileAtBottom.status == .offscreen)
    #expect(topWhileAtBottom.bounds == nil)

    _ = editor.setSelectedRange(originalSelection)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let encoded = try encoder.encode(reports)
    print(try #require(String(data: encoded, encoding: .utf8)))
  }

  private func makeFixture(
    visibleRange: AccessibilityTextRange?? = .some(
      AccessibilityTextRange(location: 0, length: 125)
    ),
    boundsResult: BearRangeBoundsQueryResult? = nil
  ) -> GeometryFixture {
    let leading = String(repeating: "a", count: 60) + " "
    let trailing = " " + String(repeating: "z", count: 60)
    let text = leading + "the" + trailing
    let range = AccessibilityTextRange(location: 61, length: 3)
    let bounds = AccessibilityBounds(
      x: 100,
      y: 200,
      width: 24,
      height: 18
    )
    let anchor = BearCorrectionAnchor(
      correctionRange: range,
      documentLength: text.utf16.count,
      leadingContext: String(leading.suffix(40)),
      trailingContext: String(trailing.prefix(40))
    )
    return GeometryFixture(
      reader: FakeBearGeometryTextClient(
        text: text,
        visibleRange: visibleRange ?? nil,
        boundsResult: boundsResult ?? .success(bounds)
      ),
      anchor: anchor,
      bounds: bounds
    )
  }

  private func geometry(
    _ fixture: GeometryFixture
  ) -> BearCorrectionGeometryReport {
    BearCorrectionGeometryTransaction().geometry(
      for: BearCorrectionGeometryRequest(
        anchor: fixture.anchor,
        expectedReplacement: "the"
      ),
      in: fixture.reader
    )
  }
}

private func liveAnchor(
  text: NSString,
  correctionRange: NSRange
) -> BearCorrectionAnchor {
  let leadingLength = min(40, correctionRange.location)
  let trailingStart = correctionRange.location + correctionRange.length
  let trailingLength = min(40, text.length - trailingStart)
  return BearCorrectionAnchor(
    correctionRange: AccessibilityTextRange(
      location: correctionRange.location,
      length: correctionRange.length
    ),
    documentLength: text.length,
    leadingContext: text.substring(
      with: NSRange(
        location: correctionRange.location - leadingLength,
        length: leadingLength
      )
    ),
    trailingContext: text.substring(
      with: NSRange(location: trailingStart, length: trailingLength)
    )
  )
}

private func testElementAttribute(
  _ element: AXUIElement,
  _ name: CFString
) -> AXUIElement? {
  var value: CFTypeRef?
  guard
    AXUIElementCopyAttributeValue(element, name, &value) == .success,
    let value,
    CFGetTypeID(value) == AXUIElementGetTypeID()
  else {
    return nil
  }
  return unsafeDowncast(value, to: AXUIElement.self)
}

private struct GeometryFixture {
  let reader: FakeBearGeometryTextClient
  let anchor: BearCorrectionAnchor
  let bounds: AccessibilityBounds
}

private final class FakeBearGeometryTextClient:
  BearGeometryTextClient, BearEditableTextClient
{
  let text: NSMutableString
  var visibleRangeValue: AccessibilityTextRange?
  var selectedRangeValue: AccessibilityTextRange?
  var boundsResult: BearRangeBoundsQueryResult
  var boundsByRange: [AccessibilityTextRange: BearRangeBoundsQueryResult] = [:]
  private(set) var boundsQueryCount = 0
  private(set) var maximumStringReadLength = 0

  init(
    text: String,
    visibleRange: AccessibilityTextRange?,
    boundsResult: BearRangeBoundsQueryResult
  ) {
    self.text = NSMutableString(string: text)
    visibleRangeValue = visibleRange
    selectedRangeValue = AccessibilityTextRange(
      location: self.text.length,
      length: 0
    )
    self.boundsResult = boundsResult
  }

  func characterCount() -> Int? {
    text.length
  }

  func string(in range: AccessibilityTextRange) -> String? {
    guard
      range.location >= 0,
      range.length >= 0,
      range.location + range.length <= text.length
    else {
      return nil
    }
    maximumStringReadLength = max(maximumStringReadLength, range.length)
    return text.substring(
      with: NSRange(location: range.location, length: range.length)
    )
  }

  func visibleRange() -> AccessibilityTextRange? {
    visibleRangeValue
  }

  func selectedRange() -> AccessibilityTextRange? {
    selectedRangeValue
  }

  func setSelectedRange(_ range: AccessibilityTextRange) -> AXError {
    guard
      range.location >= 0,
      range.length >= 0,
      range.location + range.length <= text.length
    else {
      return .illegalArgument
    }
    selectedRangeValue = range
    return .success
  }

  func replaceSelectedText(with replacement: String) -> AXError {
    guard let selectedRangeValue else {
      return .failure
    }
    text.replaceCharacters(
      in: NSRange(
        location: selectedRangeValue.location,
        length: selectedRangeValue.length
      ),
      with: replacement
    )
    self.selectedRangeValue = AccessibilityTextRange(
      location: selectedRangeValue.location + replacement.utf16.count,
      length: 0
    )
    return .success
  }

  func bounds(
    for range: AccessibilityTextRange
  ) -> BearRangeBoundsQueryResult {
    boundsQueryCount += 1
    return boundsByRange[range] ?? boundsResult
  }

  func userReplace(
    _ range: AccessibilityTextRange,
    with replacement: String
  ) {
    text.replaceCharacters(
      in: NSRange(location: range.location, length: range.length),
      with: replacement
    )
  }
}

private struct StubBearGeometryProvider: BearCorrectionGeometryProviding {
  let report: BearCorrectionGeometryReport

  func geometry(
    for _: BearCorrectionGeometryRequest
  ) -> BearCorrectionGeometryReport {
    report
  }
}
