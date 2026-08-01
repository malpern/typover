import AppKit
import ApplicationServices
import Foundation

public protocol BearExactRangeReplacing: Sendable {
  func replace(
    _ request: BearExactRangeReplacementRequest
  ) -> BearExactRangeReplacementOutcome
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

public struct BearExactRangeReplacementOutcome: Equatable, Sendable {
  public let report: BearExactRangeReplacementReport
  public let correctionAnchor: BearCorrectionAnchor?

  public init(
    report: BearExactRangeReplacementReport,
    correctionAnchor: BearCorrectionAnchor? = nil
  ) {
    self.report = report
    self.correctionAnchor = correctionAnchor
  }
}

public struct BearExactRangeReplacer: BearExactRangeReplacing, Sendable {
  public init() {}

  public func replace(
    _ request: BearExactRangeReplacementRequest
  ) -> BearExactRangeReplacementOutcome {
    guard AXIsProcessTrusted() else {
      return BearExactRangeReplacementOutcome(
        report: report(
          .accessibilityPermissionRequired,
          request: request
        )
      )
    }

    guard
      let runningApplication = NSRunningApplication.runningApplications(
        withBundleIdentifier: BearAccessibilityProbe.bearBundleIdentifier
      ).first
    else {
      return BearExactRangeReplacementOutcome(
        report: report(.bearNotRunning, request: request)
      )
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
      return BearExactRangeReplacementOutcome(
        report: report(.focusedEditorUnavailable, request: request)
      )
    }

    return BearExactRangeTransaction().applyOutcome(
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

protocol BearTextReadingClient: AnyObject {
  func characterCount() -> Int?
  func string(in range: AccessibilityTextRange) -> String?
}

protocol BearEditableTextClient: BearTextReadingClient {
  func selectedRange() -> AccessibilityTextRange?
  func setSelectedRange(_ range: AccessibilityTextRange) -> AXError
  func replaceSelectedText(with replacement: String) -> AXError
}

struct BearExactRangeTransaction {
  // Keep enough bounded context to distinguish the complete overlay
  // collection during ordinary repeated typing. Forty UTF-16 units made the
  // eleventh identical "the " correction indistinguishable from its
  // predecessors even though every correction still occupied its original
  // range.
  private let contextRadius = 256

  func apply(
    _ request: BearExactRangeReplacementRequest,
    to editor: BearEditableTextClient
  ) -> BearExactRangeReplacementReport {
    applyOutcome(request, to: editor).report
  }

  func applyOutcome(
    _ request: BearExactRangeReplacementRequest,
    to editor: BearEditableTextClient
  ) -> BearExactRangeReplacementOutcome {
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
      return outcome(report(.invalidRequest, request: request))
    }

    guard let selectionBefore = editor.selectedRange() else {
      return outcome(report(.selectedRangeUnavailable, request: request))
    }
    guard let characterCount = editor.characterCount() else {
      return outcome(
        report(
          .characterCountUnavailable,
          request: request,
          selectionBefore: selectionBefore
        )
      )
    }
    guard
      target.location <= characterCount,
      target.length <= characterCount - target.location
    else {
      return outcome(
        report(
          .targetOutOfBounds,
          request: request,
          selectionBefore: selectionBefore
        )
      )
    }

    let replacementRange = AccessibilityTextRange(
      location: target.location,
      length: replacementLength
    )
    if editor.string(in: target) != request.expectedOriginal {
      if editor.string(in: replacementRange) == request.replacement {
        return outcome(
          BearExactRangeReplacementReport(
            status: .alreadyApplied,
            targetRange: target,
            replacementRange: replacementRange,
            selectionBefore: selectionBefore,
            selectionAfter: selectionBefore,
            surroundingContextVerified: true,
            caretRestored: true
          )
        )
      }
      return outcome(
        report(
          .preconditionFailed,
          request: request,
          selectionBefore: selectionBefore
        )
      )
    }

    let contextRange = guardedContextRange(
      around: target,
      characterCount: characterCount
    )
    guard let contextBefore = editor.string(in: contextRange) else {
      return outcome(
        report(
          .contextUnavailable,
          request: request,
          selectionBefore: selectionBefore
        )
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
      return outcome(
        report(
          .selectionWriteFailed,
          request: request,
          selectionBefore: selectionBefore,
          selectionAfter: editor.selectedRange(),
          errorCode: selectionError.rawValue
        )
      )
    }
    guard editor.selectedRange() == target else {
      _ = editor.setSelectedRange(selectionBefore)
      return outcome(
        report(
          .selectionWriteFailed,
          request: request,
          selectionBefore: selectionBefore,
          selectionAfter: editor.selectedRange()
        )
      )
    }

    let replacementError = editor.replaceSelectedText(
      with: request.replacement
    )
    guard replacementError == .success else {
      _ = editor.setSelectedRange(selectionBefore)
      return outcome(
        report(
          .replacementWriteFailed,
          request: request,
          selectionBefore: selectionBefore,
          selectionAfter: editor.selectedRange(),
          errorCode: replacementError.rawValue
        )
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
      return outcome(
        BearExactRangeReplacementReport(
          status: .selectionRestoreFailed,
          writeOccurred: true,
          targetRange: target,
          replacementRange: replacementRange,
          selectionBefore: selectionBefore,
          selectionAfter: selectionAfter,
          errorCode: restoreError == .success ? nil : restoreError.rawValue
        )
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
      return outcome(
        BearExactRangeReplacementReport(
          status: .verificationFailed,
          writeOccurred: true,
          targetRange: target,
          replacementRange: replacementRange,
          selectionBefore: selectionBefore,
          selectionAfter: selectionAfter,
          surroundingContextVerified: false,
          caretRestored: true
        )
      )
    }

    let report = BearExactRangeReplacementReport(
      status: .applied,
      writeOccurred: true,
      targetRange: target,
      replacementRange: replacementRange,
      selectionBefore: selectionBefore,
      selectionAfter: selectionAfter,
      surroundingContextVerified: true,
      caretRestored: true
    )
    return BearExactRangeReplacementOutcome(
      report: report,
      correctionAnchor: BearCorrectionAnchor(
        correctionRange: replacementRange,
        documentLength: characterCount + replacementLength - originalLength,
        leadingContext: (expectedContextAfter as NSString).substring(
          with: NSRange(
            location: 0,
            length: localTargetRange.location
          )
        ),
        trailingContext: (expectedContextAfter as NSString).substring(
          from: localTargetRange.location + replacementLength
        )
      )
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

  private func outcome(
    _ report: BearExactRangeReplacementReport
  ) -> BearExactRangeReplacementOutcome {
    BearExactRangeReplacementOutcome(report: report)
  }
}

final class AXBearEditableTextClient: BearEditableTextClient {
  let element: AXUIElement

  init(element: AXUIElement) {
    self.element = element
    configureBearAccessibilityMessagingTimeout(element)
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
