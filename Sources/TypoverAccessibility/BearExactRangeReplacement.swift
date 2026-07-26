import AppKit
import ApplicationServices
import Foundation

public protocol BearExactRangeReplacing: Sendable {
  func replace(
    _ request: BearExactRangeReplacementRequest
  ) -> BearExactRangeReplacementReport
}

public struct BearExactRangeReplacementRequest: Equatable, Sendable {
  public let targetRange: AccessibilityTextRange
  public let expectedOriginal: String
  public let replacement: String

  public init(
    targetRange: AccessibilityTextRange,
    expectedOriginal: String,
    replacement: String
  ) {
    self.targetRange = targetRange
    self.expectedOriginal = expectedOriginal
    self.replacement = replacement
  }
}

public enum BearExactRangeReplacementStatus:
  String, Codable, Equatable, Sendable
{
  case applied
  case alreadyApplied
  case accessibilityPermissionRequired
  case bearNotRunning
  case focusedEditorUnavailable
  case selectedRangeUnavailable
  case characterCountUnavailable
  case invalidRequest
  case targetOutOfBounds
  case preconditionFailed
  case contextUnavailable
  case selectionWriteFailed
  case replacementWriteFailed
  case selectionRestoreFailed
  case verificationFailed
}

public struct BearExactRangeReplacementReport:
  Codable, Equatable, Sendable
{
  public let status: BearExactRangeReplacementStatus
  public let writeOccurred: Bool
  public let targetRange: AccessibilityTextRange
  public let replacementRange: AccessibilityTextRange?
  public let selectionBefore: AccessibilityTextRange?
  public let selectionAfter: AccessibilityTextRange?
  public let surroundingContextVerified: Bool
  public let caretRestored: Bool
  public let errorCode: Int32?

  public init(
    status: BearExactRangeReplacementStatus,
    writeOccurred: Bool = false,
    targetRange: AccessibilityTextRange,
    replacementRange: AccessibilityTextRange? = nil,
    selectionBefore: AccessibilityTextRange? = nil,
    selectionAfter: AccessibilityTextRange? = nil,
    surroundingContextVerified: Bool = false,
    caretRestored: Bool = false,
    errorCode: Int32? = nil
  ) {
    self.status = status
    self.writeOccurred = writeOccurred
    self.targetRange = targetRange
    self.replacementRange = replacementRange
    self.selectionBefore = selectionBefore
    self.selectionAfter = selectionAfter
    self.surroundingContextVerified = surroundingContextVerified
    self.caretRestored = caretRestored
    self.errorCode = errorCode
  }

  public var isVerifiedApplication: Bool {
    status == .applied
      && writeOccurred
      && surroundingContextVerified
      && caretRestored
  }
}

public struct BearExactRangeReplacer: BearExactRangeReplacing, Sendable {
  public init() {}

  public func replace(
    _ request: BearExactRangeReplacementRequest
  ) -> BearExactRangeReplacementReport {
    guard AXIsProcessTrusted() else {
      return report(
        .accessibilityPermissionRequired,
        request: request
      )
    }

    guard
      let runningApplication = NSRunningApplication.runningApplications(
        withBundleIdentifier: BearAccessibilityProbe.bearBundleIdentifier
      ).first
    else {
      return report(.bearNotRunning, request: request)
    }

    let applicationElement = AXUIElementCreateApplication(
      runningApplication.processIdentifier
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
      return report(.focusedEditorUnavailable, request: request)
    }

    return BearExactRangeTransaction().apply(
      request,
      to: AXBearEditableTextClient(element: editorElement)
    )
  }

  private func report(
    _ status: BearExactRangeReplacementStatus,
    request: BearExactRangeReplacementRequest
  ) -> BearExactRangeReplacementReport {
    BearExactRangeReplacementReport(
      status: status,
      targetRange: request.targetRange
    )
  }
}

protocol BearEditableTextClient: AnyObject {
  func selectedRange() -> AccessibilityTextRange?
  func characterCount() -> Int?
  func string(in range: AccessibilityTextRange) -> String?
  func setSelectedRange(_ range: AccessibilityTextRange) -> AXError
  func replaceSelectedText(with replacement: String) -> AXError
}

struct BearExactRangeTransaction {
  private let contextRadius = 40

  func apply(
    _ request: BearExactRangeReplacementRequest,
    to editor: BearEditableTextClient
  ) -> BearExactRangeReplacementReport {
    let target = request.targetRange
    let originalLength = request.expectedOriginal.utf16.count
    let replacementLength = request.replacement.utf16.count
    guard
      target.location >= 0,
      target.length == originalLength,
      originalLength > 0,
      replacementLength > 0,
      request.expectedOriginal != request.replacement
    else {
      return report(.invalidRequest, request: request)
    }

    guard let selectionBefore = editor.selectedRange() else {
      return report(.selectedRangeUnavailable, request: request)
    }
    guard let characterCount = editor.characterCount() else {
      return report(
        .characterCountUnavailable,
        request: request,
        selectionBefore: selectionBefore
      )
    }
    guard
      target.location <= characterCount,
      target.length <= characterCount - target.location
    else {
      return report(
        .targetOutOfBounds,
        request: request,
        selectionBefore: selectionBefore
      )
    }

    let replacementRange = AccessibilityTextRange(
      location: target.location,
      length: replacementLength
    )
    if editor.string(in: target) != request.expectedOriginal {
      if editor.string(in: replacementRange) == request.replacement {
        return BearExactRangeReplacementReport(
          status: .alreadyApplied,
          targetRange: target,
          replacementRange: replacementRange,
          selectionBefore: selectionBefore,
          selectionAfter: selectionBefore,
          surroundingContextVerified: true,
          caretRestored: true
        )
      }
      return report(
        .preconditionFailed,
        request: request,
        selectionBefore: selectionBefore
      )
    }

    let contextRange = guardedContextRange(
      around: target,
      characterCount: characterCount
    )
    guard let contextBefore = editor.string(in: contextRange) else {
      return report(
        .contextUnavailable,
        request: request,
        selectionBefore: selectionBefore
      )
    }
    let localTargetRange = NSRange(
      location: target.location - contextRange.location,
      length: target.length
    )
    let expectedContextAfter = (contextBefore as NSString).replacingCharacters(
      in: localTargetRange,
      with: request.replacement
    )

    let selectionError = editor.setSelectedRange(target)
    guard selectionError == .success else {
      if editor.selectedRange() != selectionBefore {
        _ = editor.setSelectedRange(selectionBefore)
      }
      return report(
        .selectionWriteFailed,
        request: request,
        selectionBefore: selectionBefore,
        selectionAfter: editor.selectedRange(),
        errorCode: selectionError.rawValue
      )
    }
    guard editor.selectedRange() == target else {
      _ = editor.setSelectedRange(selectionBefore)
      return report(
        .selectionWriteFailed,
        request: request,
        selectionBefore: selectionBefore,
        selectionAfter: editor.selectedRange()
      )
    }

    let replacementError = editor.replaceSelectedText(
      with: request.replacement
    )
    guard replacementError == .success else {
      _ = editor.setSelectedRange(selectionBefore)
      return report(
        .replacementWriteFailed,
        request: request,
        selectionBefore: selectionBefore,
        selectionAfter: editor.selectedRange(),
        errorCode: replacementError.rawValue
      )
    }

    let adjustedSelection = selectionAfterReplacing(
      target,
      replacementLength: replacementLength,
      selection: selectionBefore
    )
    let restoreError = editor.setSelectedRange(adjustedSelection)
    let selectionAfter = editor.selectedRange()
    guard restoreError == .success, selectionAfter == adjustedSelection else {
      return BearExactRangeReplacementReport(
        status: .selectionRestoreFailed,
        writeOccurred: true,
        targetRange: target,
        replacementRange: replacementRange,
        selectionBefore: selectionBefore,
        selectionAfter: selectionAfter,
        errorCode: restoreError == .success ? nil : restoreError.rawValue
      )
    }

    let contextAfterRange = AccessibilityTextRange(
      location: contextRange.location,
      length: contextRange.length + replacementLength - originalLength
    )
    let contextVerified =
      editor.string(in: contextAfterRange) == expectedContextAfter
    let countVerified = editor.characterCount()
      == characterCount + replacementLength - originalLength
    guard contextVerified, countVerified else {
      return BearExactRangeReplacementReport(
        status: .verificationFailed,
        writeOccurred: true,
        targetRange: target,
        replacementRange: replacementRange,
        selectionBefore: selectionBefore,
        selectionAfter: selectionAfter,
        surroundingContextVerified: false,
        caretRestored: true
      )
    }

    return BearExactRangeReplacementReport(
      status: .applied,
      writeOccurred: true,
      targetRange: target,
      replacementRange: replacementRange,
      selectionBefore: selectionBefore,
      selectionAfter: selectionAfter,
      surroundingContextVerified: true,
      caretRestored: true
    )
  }

  private func guardedContextRange(
    around target: AccessibilityTextRange,
    characterCount: Int
  ) -> AccessibilityTextRange {
    let location = max(0, target.location - contextRadius)
    let end = min(
      characterCount,
      target.location + target.length + contextRadius
    )
    return AccessibilityTextRange(
      location: location,
      length: end - location
    )
  }

  private func selectionAfterReplacing(
    _ target: AccessibilityTextRange,
    replacementLength: Int,
    selection: AccessibilityTextRange
  ) -> AccessibilityTextRange {
    let targetEnd = target.location + target.length
    let selectionEnd = selection.location + selection.length
    if selectionEnd <= target.location {
      return selection
    }
    if selection.location >= targetEnd {
      return AccessibilityTextRange(
        location: selection.location + replacementLength - target.length,
        length: selection.length
      )
    }
    return AccessibilityTextRange(
      location: target.location + replacementLength,
      length: 0
    )
  }

  private func report(
    _ status: BearExactRangeReplacementStatus,
    request: BearExactRangeReplacementRequest,
    selectionBefore: AccessibilityTextRange? = nil,
    selectionAfter: AccessibilityTextRange? = nil,
    errorCode: Int32? = nil
  ) -> BearExactRangeReplacementReport {
    BearExactRangeReplacementReport(
      status: status,
      targetRange: request.targetRange,
      selectionBefore: selectionBefore,
      selectionAfter: selectionAfter,
      errorCode: errorCode
    )
  }
}

private final class AXBearEditableTextClient: BearEditableTextClient {
  private let element: AXUIElement

  init(element: AXUIElement) {
    self.element = element
  }

  func selectedRange() -> AccessibilityTextRange? {
    copyRangeAttribute(
      element,
      kAXSelectedTextRangeAttribute as CFString
    )
  }

  func characterCount() -> Int? {
    copyIntegerAttribute(
      element,
      kAXNumberOfCharactersAttribute as CFString
    )
  }

  func string(in range: AccessibilityTextRange) -> String? {
    copyParameterizedValue(
      from: element,
      name: kAXStringForRangeParameterizedAttribute as CFString,
      range: range
    ) as? String
  }

  func setSelectedRange(_ range: AccessibilityTextRange) -> AXError {
    var rawRange = CFRange(
      location: range.location,
      length: range.length
    )
    guard let value = AXValueCreate(.cfRange, &rawRange) else {
      return .illegalArgument
    }
    return AXUIElementSetAttributeValue(
      element,
      kAXSelectedTextRangeAttribute as CFString,
      value
    )
  }

  func replaceSelectedText(with replacement: String) -> AXError {
    AXUIElementSetAttributeValue(
      element,
      kAXSelectedTextAttribute as CFString,
      replacement as CFString
    )
  }
}
