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
  public let selectionBefore: AccessibilityTextRange?
  public let selectionAfter: AccessibilityTextRange?

  public init(
    status: BearCorrectionRestorationStatus,
    writeOccurred: Bool = false,
    matchedRange: AccessibilityTextRange? = nil,
    candidateCount: Int = 0,
    replacementStatus: BearExactRangeReplacementStatus? = nil,
    selectionBefore: AccessibilityTextRange? = nil,
    selectionAfter: AccessibilityTextRange? = nil
  ) {
    self.status = status
    self.writeOccurred = writeOccurred
    self.matchedRange = matchedRange
    self.candidateCount = candidateCount
    self.replacementStatus = replacementStatus
    self.selectionBefore = selectionBefore
    self.selectionAfter = selectionAfter
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
      expectedTexts: [
        request.original,
        request.expectedReplacement,
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
    case .invalidated(let candidateCount):
      return report(.invalidated, candidateCount: candidateCount)
    case .matched(let range, let text):
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
    let status: BearCorrectionRestorationStatus =
      switch replacementReport.status {
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
      replacementStatus: replacementReport.status,
      selectionBefore: replacementReport.selectionBefore,
      selectionAfter: replacementReport.selectionAfter
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
    expectedTexts: [String],
    in reader: BearTextReadingClient
  ) -> BearCorrectionAnchorResolution {
    guard let documentLength = reader.characterCount() else {
      return .characterCountUnavailable
    }
    let expectedTexts = Set(
      expectedTexts.filter {
        !$0.isEmpty
          && $0.utf16.count <= maximumOrdinaryCorrectionLength
      }
    )
    guard !expectedTexts.isEmpty else {
      return .invalidated(candidateCount: 0)
    }
    let expectedLengths = Set(expectedTexts.map(\.utf16.count))

    guard
      let exactExpectedCandidates = exactlyAnchoredCandidates(
        anchor: anchor,
        candidateLengths: expectedLengths,
        documentLength: documentLength,
        reader: reader
      )
    else {
      return .contextUnavailable
    }
    if !exactExpectedCandidates.isEmpty {
      return resolve(
        exactExpectedCandidates,
        reader: reader
      )
    }

    guard
      let oneSidedCandidates = oneSidedExpectedCandidates(
        anchor: anchor,
        expectedTexts: expectedTexts,
        documentLength: documentLength,
        reader: reader
      )
    else {
      return .contextUnavailable
    }
    if !oneSidedCandidates.isEmpty {
      return resolve(oneSidedCandidates, reader: reader)
    }

    guard
      let supersededCandidates = exactlyAnchoredCandidates(
        anchor: anchor,
        candidateLengths: Set(1...maximumOrdinaryCorrectionLength),
        documentLength: documentLength,
        reader: reader
      )
    else {
      return .contextUnavailable
    }
    return resolve(supersededCandidates, reader: reader)
  }

  private func resolve(
    _ candidates: Set<AccessibilityTextRange>,
    reader: BearTextReadingClient
  ) -> BearCorrectionAnchorResolution {
    guard candidates.count == 1, let candidate = candidates.first else {
      return .invalidated(candidateCount: candidates.count)
    }
    guard let text = reader.string(in: candidate) else {
      return .contextUnavailable
    }
    return .matched(range: candidate, text: text)
  }

  private func exactlyAnchoredCandidates(
    anchor: BearCorrectionAnchor,
    candidateLengths: Set<Int>,
    documentLength: Int,
    reader: BearTextReadingClient
  ) -> Set<AccessibilityTextRange>? {
    var matches = Set<AccessibilityTextRange>()
    let validLengths = candidateLengths.filter {
      $0 > 0 && $0 <= maximumOrdinaryCorrectionLength
    }
    guard !validLengths.isEmpty else {
      return matches
    }
    for searchRange in searchRanges(
      anchor: anchor,
      documentLength: documentLength,
      maximumCandidateLength: validLengths.max() ?? 0
    ) {
      guard let searchText = reader.string(in: searchRange) else {
        return nil
      }
      matches.formUnion(
        exactlyAnchoredCandidates(
          in: searchText,
          globalStart: searchRange.location,
          documentLength: documentLength,
          anchor: anchor,
          candidateLengths: validLengths
        )
      )
    }
    return matches
  }

  private func exactlyAnchoredCandidates(
    in searchText: String,
    globalStart: Int,
    documentLength: Int,
    anchor: BearCorrectionAnchor,
    candidateLengths: Set<Int>
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
        guard
          BearCorrectionAnchor.fingerprint(leading)
            == anchor.leadingContextFingerprint
        else {
          continue
        }
      }

      for candidateLength in candidateLengths {
        let localEnd = localStart + candidateLength
        guard localEnd + anchor.trailingContextLength <= text.length else {
          continue
        }
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
          guard
            BearCorrectionAnchor.fingerprint(trailing)
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

  private func oneSidedExpectedCandidates(
    anchor: BearCorrectionAnchor,
    expectedTexts: Set<String>,
    documentLength: Int,
    reader: BearTextReadingClient
  ) -> Set<AccessibilityTextRange>? {
    var matches = Set<AccessibilityTextRange>()
    for searchRange in searchRanges(
      anchor: anchor,
      documentLength: documentLength,
      maximumCandidateLength: expectedTexts.map(\.utf16.count).max() ?? 0
    ) {
      guard let searchText = reader.string(in: searchRange) else {
        return nil
      }
      let text = searchText as NSString
      for expectedText in expectedTexts {
        let expectedLength = expectedText.utf16.count
        guard expectedLength > 0, expectedLength <= text.length else {
          continue
        }
        var searchLocation = 0
        while searchLocation <= text.length - expectedLength {
          let found = text.range(
            of: expectedText,
            options: [],
            range: NSRange(
              location: searchLocation,
              length: text.length - searchLocation
            )
          )
          guard found.location != NSNotFound else {
            break
          }
          let candidate = AccessibilityTextRange(
            location: searchRange.location + found.location,
            length: found.length
          )
          if leadingContextMatches(
            anchor: anchor,
            candidate: candidate,
            searchText: text,
            searchStart: searchRange.location
          )
            || trailingContextMatches(
              anchor: anchor,
              candidate: candidate,
              documentLength: documentLength,
              searchText: text,
              searchStart: searchRange.location
            )
          {
            matches.insert(candidate)
          }
          searchLocation = found.location + max(1, found.length)
        }
      }
    }
    return matches
  }

  private func leadingContextMatches(
    anchor: BearCorrectionAnchor,
    candidate: AccessibilityTextRange,
    searchText: NSString,
    searchStart: Int
  ) -> Bool {
    if anchor.leadingContextLength == 0 {
      return candidate.location == 0
    }
    let localStart = candidate.location - searchStart
    guard localStart >= anchor.leadingContextLength else {
      return false
    }
    let leading = searchText.substring(
      with: NSRange(
        location: localStart - anchor.leadingContextLength,
        length: anchor.leadingContextLength
      )
    )
    return BearCorrectionAnchor.fingerprint(leading)
      == anchor.leadingContextFingerprint
  }

  private func trailingContextMatches(
    anchor: BearCorrectionAnchor,
    candidate: AccessibilityTextRange,
    documentLength: Int,
    searchText: NSString,
    searchStart: Int
  ) -> Bool {
    let candidateEnd = candidate.location + candidate.length
    if anchor.trailingContextLength == 0 {
      return candidateEnd == documentLength
    }
    let localEnd = candidateEnd - searchStart
    guard localEnd + anchor.trailingContextLength <= searchText.length else {
      return false
    }
    let trailing = searchText.substring(
      with: NSRange(
        location: localEnd,
        length: anchor.trailingContextLength
      )
    )
    return BearCorrectionAnchor.fingerprint(trailing)
      == anchor.trailingContextFingerprint
  }

  private func searchRanges(
    anchor: BearCorrectionAnchor,
    documentLength: Int,
    maximumCandidateLength: Int
  ) -> Set<AccessibilityTextRange> {
    let lengthDelta = documentLength - anchor.documentLength
    let centers = Set([
      anchor.correctionRange.location,
      anchor.correctionRange.location + lengthDelta,
    ])
    return Set(
      centers.compactMap { center in
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
          return nil
        }
        return AccessibilityTextRange(
          location: searchStart,
          length: searchEnd - searchStart
        )
      })
  }
}
