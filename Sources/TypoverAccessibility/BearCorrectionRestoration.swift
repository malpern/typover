import AppKit
import ApplicationServices
import CryptoKit
import Foundation

/// A content-private, bounded fingerprint of the text surrounding a correction.
///
/// The surrounding prose is hashed immediately and is never retained. The
/// original and replacement remain owned by Typover's correction record.
public struct BearCorrectionAnchor: Codable, Equatable, Sendable {
  public let correctionRange: AccessibilityTextRange
  public let documentLength: Int
  public let leadingContextLength: Int
  public let trailingContextLength: Int
  public let leadingContextFingerprint: String
  public let trailingContextFingerprint: String

  public init(
    correctionRange: AccessibilityTextRange,
    documentLength: Int,
    leadingContext: String,
    trailingContext: String
  ) {
    self.correctionRange = correctionRange
    self.documentLength = documentLength
    leadingContextLength = leadingContext.utf16.count
    trailingContextLength = trailingContext.utf16.count
    leadingContextFingerprint = Self.fingerprint(leadingContext)
    trailingContextFingerprint = Self.fingerprint(trailingContext)
  }

  static func fingerprint(_ text: String) -> String {
    var data = Data(capacity: text.utf16.count * 2)
    for codeUnit in text.utf16 {
      data.append(UInt8(truncatingIfNeeded: codeUnit))
      data.append(UInt8(truncatingIfNeeded: codeUnit >> 8))
    }
    return SHA256.hash(data: data)
      .map { String(format: "%02x", $0) }
      .joined()
  }
}

public struct BearCorrectionRestorationRequest: Equatable, Sendable {
  public let anchor: BearCorrectionAnchor
  public let expectedReplacement: String
  public let original: String

  public init(
    anchor: BearCorrectionAnchor,
    expectedReplacement: String,
    original: String
  ) {
    self.anchor = anchor
    self.expectedReplacement = expectedReplacement
    self.original = original
  }
}

public enum BearCorrectionRestorationStatus:
  String, Codable, Equatable, Sendable
{
  case restored
  case alreadyRestored
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

public struct BearCorrectionRestorationReport:
  Codable, Equatable, Sendable
{
  public let status: BearCorrectionRestorationStatus
  public let writeOccurred: Bool
  public let matchedRange: AccessibilityTextRange?
  public let candidateCount: Int
  public let replacementStatus: BearExactRangeReplacementStatus?

  public init(
    status: BearCorrectionRestorationStatus,
    writeOccurred: Bool = false,
    matchedRange: AccessibilityTextRange? = nil,
    candidateCount: Int = 0,
    replacementStatus: BearExactRangeReplacementStatus? = nil
  ) {
    self.status = status
    self.writeOccurred = writeOccurred
    self.matchedRange = matchedRange
    self.candidateCount = candidateCount
    self.replacementStatus = replacementStatus
  }
}

public protocol BearCorrectionRestoring: Sendable {
  func restore(
    _ request: BearCorrectionRestorationRequest
  ) -> BearCorrectionRestorationReport
}

public struct BearCorrectionRestorer: BearCorrectionRestoring, Sendable {
  public init() {}

  public func restore(
    _ request: BearCorrectionRestorationRequest
  ) -> BearCorrectionRestorationReport {
    guard AXIsProcessTrusted() else {
      return BearCorrectionRestorationReport(
        status: .accessibilityPermissionRequired
      )
    }
    guard
      let application = NSRunningApplication.runningApplications(
        withBundleIdentifier: BearAccessibilityProbe.bearBundleIdentifier
      ).first
    else {
      return BearCorrectionRestorationReport(status: .bearNotRunning)
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
      return BearCorrectionRestorationReport(
        status: .focusedEditorUnavailable
      )
    }

    return BearCorrectionRestorationTransaction().restore(
      request,
      in: AXBearEditableTextClient(element: editorElement)
    )
  }
}

struct BearCorrectionRestorationTransaction {
  func restore(
    _ request: BearCorrectionRestorationRequest,
    in editor: BearEditableTextClient
  ) -> BearCorrectionRestorationReport {
    guard editor.selectedRange() != nil else {
      return report(.selectedRangeUnavailable)
    }
    let resolution = BearCorrectionAnchorResolver().resolve(
      anchor: request.anchor,
      expectedLengths: [
        request.original.utf16.count,
        request.expectedReplacement.utf16.count,
      ],
      in: editor
    )
    let candidate: AccessibilityTextRange
    let currentText: String
    switch resolution {
    case .characterCountUnavailable:
      return report(.characterCountUnavailable)
    case .contextUnavailable:
      return report(.contextUnavailable)
    case let .invalidated(candidateCount):
      return report(.invalidated, candidateCount: candidateCount)
    case let .matched(range, text):
      candidate = range
      currentText = text
    }

    if currentText == request.original {
      return report(
        .alreadyRestored,
        matchedRange: candidate,
        candidateCount: 1
      )
    }
    guard currentText == request.expectedReplacement else {
      return report(
        .superseded,
        matchedRange: candidate,
        candidateCount: 1
      )
    }

    let replacementReport = BearExactRangeTransaction().apply(
      BearExactRangeReplacementRequest(
        targetRange: candidate,
        expectedOriginal: request.expectedReplacement,
        replacement: request.original
      ),
      to: editor
    )
    return mapReplacementReport(replacementReport, matchedRange: candidate)
  }

  private func mapReplacementReport(
    _ replacementReport: BearExactRangeReplacementReport,
    matchedRange: AccessibilityTextRange
  ) -> BearCorrectionRestorationReport {
    let status: BearCorrectionRestorationStatus = switch replacementReport.status {
    case .applied: .restored
    case .alreadyApplied: .alreadyRestored
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
    return BearCorrectionRestorationReport(
      status: status,
      writeOccurred: replacementReport.writeOccurred,
      matchedRange: matchedRange,
      candidateCount: 1,
      replacementStatus: replacementReport.status
    )
  }

  private func report(
    _ status: BearCorrectionRestorationStatus,
    matchedRange: AccessibilityTextRange? = nil,
    candidateCount: Int = 0
  ) -> BearCorrectionRestorationReport {
    BearCorrectionRestorationReport(
      status: status,
      matchedRange: matchedRange,
      candidateCount: candidateCount
    )
  }
}

enum BearCorrectionAnchorResolution: Equatable {
  case matched(range: AccessibilityTextRange, text: String)
  case invalidated(candidateCount: Int)
  case characterCountUnavailable
  case contextUnavailable
}

struct BearCorrectionAnchorResolver {
  private let searchRadius = 256
  private let maximumOrdinaryCorrectionLength = 256

  func resolve(
    anchor: BearCorrectionAnchor,
    expectedLengths: [Int],
    in reader: BearTextReadingClient
  ) -> BearCorrectionAnchorResolution {
    guard let documentLength = reader.characterCount() else {
      return .characterCountUnavailable
    }
    guard let candidates = anchoredCandidates(
      anchor: anchor,
      expectedLengths: expectedLengths,
      documentLength: documentLength,
      reader: reader
    ) else {
      return .contextUnavailable
    }
    guard candidates.count == 1, let candidate = candidates.first else {
      return .invalidated(candidateCount: candidates.count)
    }
    guard let text = reader.string(in: candidate) else {
      return .contextUnavailable
    }
    return .matched(range: candidate, text: text)
  }

  private func anchoredCandidates(
    anchor: BearCorrectionAnchor,
    expectedLengths: [Int],
    documentLength: Int,
    reader: BearTextReadingClient
  ) -> Set<AccessibilityTextRange>? {
    let lengthDelta = documentLength - anchor.documentLength
    let centers = Set([
      anchor.correctionRange.location,
      anchor.correctionRange.location + lengthDelta,
    ])
    let maximumCandidateLength = max(
      maximumOrdinaryCorrectionLength,
      expectedLengths.max() ?? 0
    )
    var matches = Set<AccessibilityTextRange>()

    for center in centers {
      let searchStart = max(
        0,
        center - searchRadius - anchor.leadingContextLength
      )
      let searchEnd = min(
        documentLength,
        center + searchRadius + maximumCandidateLength
          + anchor.trailingContextLength
      )
      guard searchEnd >= searchStart else {
        continue
      }
      let searchRange = AccessibilityTextRange(
        location: searchStart,
        length: searchEnd - searchStart
      )
      guard let searchText = reader.string(in: searchRange) else {
        return nil
      }
      matches.formUnion(
        candidates(
          in: searchText,
          globalStart: searchStart,
          documentLength: documentLength,
          anchor: anchor,
          maximumCandidateLength: maximumCandidateLength
        )
      )
    }
    return matches
  }

  private func candidates(
    in searchText: String,
    globalStart: Int,
    documentLength: Int,
    anchor: BearCorrectionAnchor,
    maximumCandidateLength: Int
  ) -> Set<AccessibilityTextRange> {
    let text = searchText as NSString
    var matches = Set<AccessibilityTextRange>()
    let minimumStart = anchor.leadingContextLength
    let maximumStart = text.length - anchor.trailingContextLength - 1
    guard minimumStart <= maximumStart else {
      return matches
    }

    for localStart in minimumStart...maximumStart {
      let candidateStart = globalStart + localStart
      if anchor.leadingContextLength == 0 {
        guard candidateStart == 0 else {
          continue
        }
      } else {
        let leading = text.substring(
          with: NSRange(
            location: localStart - anchor.leadingContextLength,
            length: anchor.leadingContextLength
          )
        )
        guard BearCorrectionAnchor.fingerprint(leading)
          == anchor.leadingContextFingerprint
        else {
          continue
        }
      }

      let availableLength = text.length - localStart
        - anchor.trailingContextLength
      guard availableLength > 0 else {
        continue
      }
      for candidateLength in 1...min(
        maximumCandidateLength,
        availableLength
      ) {
        let localEnd = localStart + candidateLength
        let candidateEnd = globalStart + localEnd
        if anchor.trailingContextLength == 0 {
          guard candidateEnd == documentLength else {
            continue
          }
        } else {
          let trailing = text.substring(
            with: NSRange(
              location: localEnd,
              length: anchor.trailingContextLength
            )
          )
          guard BearCorrectionAnchor.fingerprint(trailing)
            == anchor.trailingContextFingerprint
          else {
            continue
          }
        }
        matches.insert(
          AccessibilityTextRange(
            location: candidateStart,
            length: candidateLength
          )
        )
      }
    }
    return matches
  }
}
