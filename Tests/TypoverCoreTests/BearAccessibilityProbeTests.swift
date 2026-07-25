import Foundation
import Testing

@testable import TypoverAccessibility

@Suite("Bear Accessibility probe")
struct BearAccessibilityProbeTests {
  @Test(
    "Bounded context never exceeds 80 UTF-16 units",
    arguments: [
      (location: 50, characterCount: 200, expectedLocation: 10, expectedLength: 80),
      (location: 10, characterCount: 200, expectedLocation: 0, expectedLength: 50),
      (location: 195, characterCount: 200, expectedLocation: 155, expectedLength: 45),
    ]
  )
  func boundedContextRange(
    sample: (
      location: Int,
      characterCount: Int,
      expectedLocation: Int,
      expectedLength: Int
    )
  ) {
    let range = BearAccessibilityProbe().boundedRange(
      around: sample.location,
      characterCount: sample.characterCount
    )

    #expect(range?.location == sample.expectedLocation)
    #expect(range?.length == sample.expectedLength)
  }

  @Test("Reports contain capability facts without document text fields")
  func reportEncodingIsContentFree() throws {
    let report = BearAccessibilityReport(
      status: .ready,
      accessibilityTrusted: true,
      bearIsRunning: true,
      editorRole: "AXTextArea",
      editorIdentifier: "editor",
      editorWasFocused: true,
      focusedWindowAvailable: true,
      textAreaCandidateCount: 1,
      selectedRange: AccessibilityTextRange(location: 42, length: 0),
      visibleRange: AccessibilityTextRange(location: 0, length: 80),
      characterCount: 120,
      boundedContextUTF16Length: 80,
      boundedContextReader: "AXStringForRange",
      rangeBounds: AccessibilityBounds(
        x: 20,
        y: 40,
        width: 1,
        height: 18
      ),
      attributes: [
        AccessibilityCapability(
          name: "AXSelectedTextRange",
          state: .available,
          isWritable: true
        )
      ],
      parameterizedAttributes: [
        AccessibilityCapability(
          name: "AXBoundsForRange",
          state: .available
        )
      ],
      notificationRegistrations: [
        AccessibilityCapability(
          name: "AXSelectedTextChanged",
          state: .available
        )
      ]
    )

    let encoded = try JSONEncoder().encode(report)
    let json = try #require(String(data: encoded, encoding: .utf8))

    #expect(!json.contains("documentText"))
    #expect(!json.contains("selectedText"))
    #expect(!json.contains("contextText"))
    #expect(!json.contains("valueText"))
  }

  @Test("Event reports contain names and counts without document text")
  func eventReportEncodingIsContentFree() throws {
    let report = BearAccessibilityEventReport(
      status: .ready,
      editorWasFocused: true,
      durationMilliseconds: 5_000,
      registrations: [
        AccessibilityCapability(
          name: "AXSelectedTextChanged",
          state: .available
        )
      ],
      observations: [
        AccessibilityEventObservation(
          name: "AXSelectedTextChanged",
          count: 2
        )
      ]
    )

    let encoded = try JSONEncoder().encode(report)
    let json = try #require(String(data: encoded, encoding: .utf8))

    #expect(json.contains("AXSelectedTextChanged"))
    #expect(!json.contains("documentText"))
    #expect(!json.contains("selectedText"))
    #expect(!json.contains("contextText"))
    #expect(!json.contains("valueText"))
  }

  @Test(
    "Live Bear probe returns a structured, content-free report",
    .enabled(
      if: ProcessInfo.processInfo.environment[
        "TYPOVER_RUN_LIVE_BEAR_PROBE"
      ] == "1"
    )
  )
  func liveBearProbe() throws {
    let report = BearAccessibilityProbe().run()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let encoded = try encoder.encode(report)
    let json = try #require(String(data: encoded, encoding: .utf8))

    print(json)
    #expect(report.accessibilityTrusted)
    #expect(report.bearIsRunning)
    guard
      ProcessInfo.processInfo.environment[
        "TYPOVER_REQUIRE_BEAR_EDITOR_CAPABILITIES"
      ] == "1"
    else {
      #expect(report.status != .accessibilityPermissionRequired)
      return
    }

    #expect(
      report.status == .ready
        || report.status == .editorAvailableButNotFocused
    )
    #expect(report.editorRole == "AXTextArea")
    #expect(report.selectedRange != nil)
    #expect(report.boundedContextUTF16Length != nil)
    #expect(report.rangeBounds != nil)
    #expect(
      report.notificationRegistrations.allSatisfy { capability in
        capability.state == .available
      }
    )
  }

  @Test(
    "Live Bear monitor records content-free Accessibility events",
    .enabled(
      if: ProcessInfo.processInfo.environment[
        "TYPOVER_RUN_LIVE_BEAR_EVENT_MONITOR"
      ] == "1"
    )
  )
  func liveBearEventMonitor() async throws {
    let report = await Task.detached {
      BearAccessibilityEventMonitor().observe(for: 8)
    }.value
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let encoded = try encoder.encode(report)
    let json = try #require(String(data: encoded, encoding: .utf8))

    print(json)
    #expect(report.status != .accessibilityPermissionRequired)

    guard
      ProcessInfo.processInfo.environment[
        "TYPOVER_REQUIRE_BEAR_EVENTS"
      ] == "1"
    else {
      return
    }

    #expect(report.status == .ready)
    #expect(report.editorWasFocused)
    #expect(
      report.registrations.allSatisfy { capability in
        capability.state == .available
      }
    )
    #expect(!report.observations.isEmpty)
  }
}
