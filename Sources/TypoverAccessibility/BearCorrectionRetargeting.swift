import AppKit
import ApplicationServices
import Foundation

public struct BearCorrectionRetargetRequest: Equatable, Sendable {
  public let anchor: BearCorrectionAnchor
  public let expectedCurrent: String
  public let replacement: String

  public init(
    anchor: BearCorrectionAnchor,
    expectedCurrent: String,
    replacement: String
  ) {
    self.anchor = anchor
    self.expectedCurrent = expectedCurrent
    self.replacement = replacement
  }
}

public enum BearCorrectionRetargetStatus:
  String, Codable, Equatable, Sendable
{
  case applied
  case alreadyApplied
  case superseded
  case invalidated
  case accessibilityPermissionRequired
  case bearNotRunning
  case focusedEditorUnavailable
  case selectedRangeUnavailable
  case characterCountUnavailable
  case contextUnavailable
  case selectionWriteFailed
  case replacementWriteFailed
  case selectionRestoreFailed
  case verificationFailed
}

public struct BearCorrectionRetargetReport:
  Codable, Equatable, Sendable
{
  public let status: BearCorrectionRetargetStatus
  public let writeOccurred: Bool
  public let matchedRange: AccessibilityTextRange?
  public let candidateCount: Int
  public let replacementReport: BearExactRangeReplacementReport?

  public init(
    status: BearCorrectionRetargetStatus,
    writeOccurred: Bool = false,
    matchedRange: AccessibilityTextRange? = nil,
    candidateCount: Int = 0,
    replacementReport: BearExactRangeReplacementReport? = nil
  ) {
    self.status = status
    self.writeOccurred = writeOccurred
    self.matchedRange = matchedRange
    self.candidateCount = candidateCount
    self.replacementReport = replacementReport
  }
}

public struct BearCorrectionRetargetOutcome: Equatable, Sendable {
  public let report: BearCorrectionRetargetReport
  public let correctionAnchor: BearCorrectionAnchor?

  public init(
    report: BearCorrectionRetargetReport,
    correctionAnchor: BearCorrectionAnchor? = nil
  ) {
    self.report = report
    self.correctionAnchor = correctionAnchor
  }
}

public protocol BearCorrectionRetargeting: Sendable {
  func retarget(
    _ request: BearCorrectionRetargetRequest
  ) -> BearCorrectionRetargetOutcome
}

public struct BearCorrectionRetargeter:
  BearCorrectionRetargeting, Sendable
{
  public init() {}

  public func retarget(
    _ request: BearCorrectionRetargetRequest
  ) -> BearCorrectionRetargetOutcome {
    guard AXIsProcessTrusted() else {
      return outcome(.accessibilityPermissionRequired)
    }
    guard
      let application = NSRunningApplication.runningApplications(
        withBundleIdentifier: BearAccessibilityProbe.bearBundleIdentifier
      ).first
    else {
      return outcome(.bearNotRunning)
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
      return outcome(.focusedEditorUnavailable)
    }

    return BearCorrectionRetargetTransaction().retarget(
      request,
      in: AXBearEditableTextClient(element: editorElement)
    )
  }

  private func outcome(
    _ status: BearCorrectionRetargetStatus
  ) -> BearCorrectionRetargetOutcome {
    BearCorrectionRetargetOutcome(
      report: BearCorrectionRetargetReport(status: status)
    )
  }
}

struct BearCorrectionRetargetTransaction {
  func retarget(
    _ request: BearCorrectionRetargetRequest,
    in editor: BearEditableTextClient
  ) -> BearCorrectionRetargetOutcome {
    guard !request.expectedCurrent.isEmpty, !request.replacement.isEmpty else {
      return outcome(.invalidated)
    }
    guard editor.selectedRange() != nil else {
      return outcome(.selectedRangeUnavailable)
    }
    let resolution = BearCorrectionAnchorResolver().resolve(
      anchor: request.anchor,
      expectedTexts: [
        request.expectedCurrent,
        request.replacement,
      ],
      in: editor
    )
    let candidate: AccessibilityTextRange
    let currentText: String
    switch resolution {
    case .characterCountUnavailable:
      return outcome(.characterCountUnavailable)
    case .contextUnavailable:
      return outcome(.contextUnavailable)
    case .invalidated(let candidateCount):
      return outcome(.invalidated, candidateCount: candidateCount)
    case .matched(let range, let text):
      candidate = range
      currentText = text
    }

    if currentText == request.replacement {
      guard
        let refreshedAnchor = refreshedAnchor(
          for: candidate,
          request: request,
          editor: editor
        )
      else {
        return outcome(.contextUnavailable, matchedRange: candidate)
      }
      return BearCorrectionRetargetOutcome(
        report: BearCorrectionRetargetReport(
          status: .alreadyApplied,
          matchedRange: candidate,
          candidateCount: 1,
          replacementReport: BearExactRangeReplacementReport(
            status: .alreadyApplied,
            targetRange: candidate,
            replacementRange: candidate
          )
        ),
        correctionAnchor: refreshedAnchor
      )
    }
    guard currentText == request.expectedCurrent else {
      return outcome(
        .superseded,
        matchedRange: candidate,
        candidateCount: 1
      )
    }

    let replacementOutcome = BearExactRangeTransaction().applyOutcome(
      BearExactRangeReplacementRequest(
        targetRange: candidate,
        expectedOriginal: request.expectedCurrent,
        replacement: request.replacement
      ),
      to: editor
    )
    return BearCorrectionRetargetOutcome(
      report: BearCorrectionRetargetReport(
        status: map(replacementOutcome.report.status),
        writeOccurred: replacementOutcome.report.writeOccurred,
        matchedRange: candidate,
        candidateCount: 1,
        replacementReport: replacementOutcome.report
      ),
      correctionAnchor: replacementOutcome.correctionAnchor
    )
  }

  private func refreshedAnchor(
    for range: AccessibilityTextRange,
    request: BearCorrectionRetargetRequest,
    editor: BearEditableTextClient
  ) -> BearCorrectionAnchor? {
    guard let characterCount = editor.characterCount() else {
      return nil
    }
    let leadingLength = min(
      request.anchor.leadingContextLength,
      range.location
    )
    let trailingStart = range.location + range.length
    let trailingLength = min(
      request.anchor.trailingContextLength,
      max(0, characterCount - trailingStart)
    )
    guard
      let leading = editor.string(
        in: AccessibilityTextRange(
          location: range.location - leadingLength,
          length: leadingLength
        )
      ),
      let trailing = editor.string(
        in: AccessibilityTextRange(
          location: trailingStart,
          length: trailingLength
        )
      )
    else {
      return nil
    }
    return BearCorrectionAnchor(
      correctionRange: range,
      documentLength: characterCount,
      leadingContext: leading,
      trailingContext: trailing
    )
  }

  private func map(
    _ status: BearExactRangeReplacementStatus
  ) -> BearCorrectionRetargetStatus {
    switch status {
    case .applied: .applied
    case .alreadyApplied: .alreadyApplied
    case .selectedRangeUnavailable: .selectedRangeUnavailable
    case .characterCountUnavailable: .characterCountUnavailable
    case .contextUnavailable: .contextUnavailable
    case .selectionWriteFailed: .selectionWriteFailed
    case .replacementWriteFailed: .replacementWriteFailed
    case .selectionRestoreFailed: .selectionRestoreFailed
    case .verificationFailed: .verificationFailed
    case .accessibilityPermissionRequired: .accessibilityPermissionRequired
    case .bearNotRunning: .bearNotRunning
    case .focusedEditorUnavailable: .focusedEditorUnavailable
    case .invalidRequest, .targetOutOfBounds, .preconditionFailed: .invalidated
    }
  }

  private func outcome(
    _ status: BearCorrectionRetargetStatus,
    matchedRange: AccessibilityTextRange? = nil,
    candidateCount: Int = 0
  ) -> BearCorrectionRetargetOutcome {
    BearCorrectionRetargetOutcome(
      report: BearCorrectionRetargetReport(
        status: status,
        matchedRange: matchedRange,
        candidateCount: candidateCount
      )
    )
  }
}
