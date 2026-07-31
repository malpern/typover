import AppKit
import ApplicationServices
import Foundation

public struct BearCorrectionReanchorRequest: Equatable, Sendable {
  public let targetRange: AccessibilityTextRange
  public let expectedText: String
  public let leadingContextLimit: Int
  public let trailingContextLimit: Int

  public init(
    targetRange: AccessibilityTextRange,
    expectedText: String,
    leadingContextLimit: Int,
    trailingContextLimit: Int
  ) {
    self.targetRange = targetRange
    self.expectedText = expectedText
    self.leadingContextLimit = leadingContextLimit
    self.trailingContextLimit = trailingContextLimit
  }
}

public enum BearCorrectionReanchorStatus: Equatable, Sendable {
  case reanchored
  case invalidRequest
  case targetOutOfBounds
  case superseded
  case accessibilityPermissionRequired
  case bearNotRunning
  case focusedEditorUnavailable
  case characterCountUnavailable
  case contextUnavailable
}

public struct BearCorrectionReanchorOutcome: Equatable, Sendable {
  public let status: BearCorrectionReanchorStatus
  public let correctionAnchor: BearCorrectionAnchor?

  public init(
    status: BearCorrectionReanchorStatus,
    correctionAnchor: BearCorrectionAnchor? = nil
  ) {
    self.status = status
    self.correctionAnchor = correctionAnchor
  }
}

public protocol BearCorrectionReanchoring: Sendable {
  func reanchor(
    _ request: BearCorrectionReanchorRequest
  ) -> BearCorrectionReanchorOutcome
}

public struct BearCorrectionReanchorer:
  BearCorrectionReanchoring, Sendable
{
  public init() {}

  public func reanchor(
    _ request: BearCorrectionReanchorRequest
  ) -> BearCorrectionReanchorOutcome {
    guard AXIsProcessTrusted() else {
      return BearCorrectionReanchorOutcome(
        status: .accessibilityPermissionRequired
      )
    }
    guard
      let application = NSRunningApplication.runningApplications(
        withBundleIdentifier: BearAccessibilityProbe.bearBundleIdentifier
      ).first
    else {
      return BearCorrectionReanchorOutcome(status: .bearNotRunning)
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
      return BearCorrectionReanchorOutcome(
        status: .focusedEditorUnavailable
      )
    }

    return BearCorrectionReanchorTransaction().reanchor(
      request,
      in: AXBearEditableTextClient(element: editorElement)
    )
  }
}

struct BearCorrectionReanchorTransaction {
  func reanchor(
    _ request: BearCorrectionReanchorRequest,
    in editor: BearTextReadingClient
  ) -> BearCorrectionReanchorOutcome {
    guard
      !request.expectedText.isEmpty,
      request.targetRange.location >= 0,
      request.targetRange.length == request.expectedText.utf16.count,
      request.leadingContextLimit >= 0,
      request.trailingContextLimit >= 0
    else {
      return BearCorrectionReanchorOutcome(status: .invalidRequest)
    }
    guard let characterCount = editor.characterCount() else {
      return BearCorrectionReanchorOutcome(
        status: .characterCountUnavailable
      )
    }
    let rangeEnd = request.targetRange.location + request.targetRange.length
    guard rangeEnd <= characterCount else {
      return BearCorrectionReanchorOutcome(status: .targetOutOfBounds)
    }
    guard editor.string(in: request.targetRange) == request.expectedText else {
      return BearCorrectionReanchorOutcome(status: .superseded)
    }

    let leadingLength = min(
      request.leadingContextLimit,
      request.targetRange.location
    )
    let trailingLength = min(
      request.trailingContextLimit,
      characterCount - rangeEnd
    )
    guard
      let leading = editor.string(
        in: AccessibilityTextRange(
          location: request.targetRange.location - leadingLength,
          length: leadingLength
        )
      ),
      let trailing = editor.string(
        in: AccessibilityTextRange(
          location: rangeEnd,
          length: trailingLength
        )
      )
    else {
      return BearCorrectionReanchorOutcome(status: .contextUnavailable)
    }

    return BearCorrectionReanchorOutcome(
      status: .reanchored,
      correctionAnchor: BearCorrectionAnchor(
        correctionRange: request.targetRange,
        documentLength: characterCount,
        leadingContext: leading,
        trailingContext: trailing
      )
    )
  }
}
