import AppKit
import ApplicationServices
import Foundation

public struct BearCorrectionSelectionStabilizationRequest:
  Equatable, Sendable
{
  public let anchor: BearCorrectionAnchor
  public let expectedText: String
  public let desiredSelection: AccessibilityTextRange
  public let additionalTransientSelections: [AccessibilityTextRange]

  public init(
    anchor: BearCorrectionAnchor,
    expectedText: String,
    desiredSelection: AccessibilityTextRange,
    additionalTransientSelections: [AccessibilityTextRange] = []
  ) {
    self.anchor = anchor
    self.expectedText = expectedText
    self.desiredSelection = desiredSelection
    self.additionalTransientSelections = additionalTransientSelections
  }
}

public enum BearCorrectionSelectionStabilizationStatus:
  String, Equatable, Sendable
{
  case stabilized
  case alreadyStable
  case userMovedSelection
  case staleAnchor
  case accessibilityPermissionRequired
  case bearNotRunning
  case focusedEditorUnavailable
  case selectionUnavailable
  case selectionWriteFailed
}

public protocol BearCorrectionSelectionStabilizing: Sendable {
  func stabilizeSelection(
    _ request: BearCorrectionSelectionStabilizationRequest
  ) -> BearCorrectionSelectionStabilizationStatus
}

public struct BearCorrectionSelectionStabilizer:
  BearCorrectionSelectionStabilizing, Sendable
{
  public init() {}

  public func stabilizeSelection(
    _ request: BearCorrectionSelectionStabilizationRequest
  ) -> BearCorrectionSelectionStabilizationStatus {
    guard AXIsProcessTrusted() else {
      return .accessibilityPermissionRequired
    }
    guard
      let application = NSRunningApplication.runningApplications(
        withBundleIdentifier: BearAccessibilityProbe.bearBundleIdentifier
      ).first
    else {
      return .bearNotRunning
    }
    let applicationElement = AXUIElementCreateApplication(
      application.processIdentifier
    )
    guard
      let focusedElement = copyElementAttribute(
        applicationElement,
        kAXFocusedUIElementAttribute as CFString
      ),
      let editorElement = BearAccessibilityProbe().nearestTextArea(
        startingAt: focusedElement
      )
    else {
      return .focusedEditorUnavailable
    }
    return BearCorrectionSelectionStabilizationTransaction().stabilize(
      request,
      in: AXBearEditableTextClient(element: editorElement)
    )
  }
}

struct BearCorrectionSelectionStabilizationTransaction {
  func stabilize(
    _ request: BearCorrectionSelectionStabilizationRequest,
    in editor: BearEditableTextClient
  ) -> BearCorrectionSelectionStabilizationStatus {
    let resolution = BearCorrectionAnchorResolver().resolve(
      anchor: request.anchor,
      expectedLengths: [request.expectedText.utf16.count],
      in: editor
    )
    guard case .matched(let range, let text) = resolution,
      text == request.expectedText
    else {
      return .staleAnchor
    }
    guard let currentSelection = editor.selectedRange() else {
      return .selectionUnavailable
    }
    guard currentSelection != request.desiredSelection else {
      return .alreadyStable
    }

    // Bear can post a delayed selection update after AXSelectedText changes.
    // Repair only that known transient caret. Any other range is treated as a
    // newer user action and must win.
    let currentTextTransientSelection = AccessibilityTextRange(
      location: range.location + range.length,
      length: 0
    )
    let transientSelections =
      request.additionalTransientSelections + [currentTextTransientSelection]
    guard transientSelections.contains(currentSelection) else {
      return .userMovedSelection
    }
    guard
      editor.setSelectedRange(request.desiredSelection) == .success,
      editor.selectedRange() == request.desiredSelection
    else {
      return .selectionWriteFailed
    }
    return .stabilized
  }
}
