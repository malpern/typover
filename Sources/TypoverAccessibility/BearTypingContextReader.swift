import AppKit
import ApplicationServices
import Foundation

public struct BearTypingContextSnapshot: Equatable, Sendable {
  public let leadingRange: AccessibilityTextRange
  public let leadingText: String
  public let trailingText: String
  public let caretLocation: Int
  public let documentLength: Int

  public init(
    leadingRange: AccessibilityTextRange,
    leadingText: String,
    trailingText: String,
    caretLocation: Int,
    documentLength: Int
  ) {
    self.leadingRange = leadingRange
    self.leadingText = leadingText
    self.trailingText = trailingText
    self.caretLocation = caretLocation
    self.documentLength = documentLength
  }
}

public enum BearTypingContextReadResult: Equatable, Sendable {
  case ready(BearTypingContextSnapshot)
  case accessibilityPermissionRequired
  case bearNotRunning
  case bearNotFrontmost
  case focusedEditorUnavailable
  case selectionActive
  case contextUnavailable
}

public protocol BearTypingContextReading: AnyObject, Sendable {
  func read() -> BearTypingContextReadResult
}

/// Reads only a bounded neighborhood around the caret in Bear's focused
/// editor. The returned strings are transient and are never persisted.
public final class BearTypingContextReader:
  BearTypingContextReading, @unchecked Sendable
{
  private let leadingLimit: Int
  private let trailingLimit: Int

  public init(
    leadingLimit: Int = 96,
    trailingLimit: Int = 24
  ) {
    self.leadingLimit = max(32, min(leadingLimit, 400))
    self.trailingLimit = max(0, min(trailingLimit, 64))
  }

  public func read() -> BearTypingContextReadResult {
    guard AXIsProcessTrusted() else {
      return .accessibilityPermissionRequired
    }
    guard
      let runningApplication = NSRunningApplication.runningApplications(
        withBundleIdentifier: BearAccessibilityProbe.bearBundleIdentifier
      ).first
    else {
      return .bearNotRunning
    }
    guard
      runningApplication.isActive
    else {
      return .bearNotFrontmost
    }

    let applicationElement = AXUIElementCreateApplication(
      runningApplication.processIdentifier
    )
    configureBearAccessibilityMessagingTimeout(applicationElement)
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
    guard
      let selection = copyRangeAttribute(
        editorElement,
        kAXSelectedTextRangeAttribute as CFString
      ),
      selection.length == 0
    else {
      return .selectionActive
    }
    guard
      let characterCount = copyIntegerAttribute(
        editorElement,
        kAXNumberOfCharactersAttribute as CFString
      ),
      selection.location >= 0,
      selection.location <= characterCount
    else {
      return .contextUnavailable
    }

    let leadingRange = AccessibilityTextRange(
      location: max(0, selection.location - leadingLimit),
      length: min(leadingLimit, selection.location)
    )
    let trailingRange = AccessibilityTextRange(
      location: selection.location,
      length: min(trailingLimit, characterCount - selection.location)
    )
    guard
      let leadingText = string(in: leadingRange, from: editorElement),
      let trailingText = string(in: trailingRange, from: editorElement)
    else {
      return .contextUnavailable
    }

    return .ready(
      BearTypingContextSnapshot(
        leadingRange: leadingRange,
        leadingText: leadingText,
        trailingText: trailingText,
        caretLocation: selection.location,
        documentLength: characterCount
      )
    )
  }

  private func string(
    in range: AccessibilityTextRange,
    from element: AXUIElement
  ) -> String? {
    guard range.length > 0 else {
      return ""
    }
    return copyParameterizedValue(
      from: element,
      name: kAXStringForRangeParameterizedAttribute as CFString,
      range: range
    ) as? String
  }
}
