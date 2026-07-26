import AppKit
import ApplicationServices
import Foundation

public struct BearCorrectionGeometryRequest: Equatable, Sendable {
  public let anchor: BearCorrectionAnchor
  public let expectedReplacement: String

  public init(
    anchor: BearCorrectionAnchor,
    expectedReplacement: String
  ) {
    self.anchor = anchor
    self.expectedReplacement = expectedReplacement
  }
}

public enum BearCorrectionGeometryStatus:
  String, Codable, Equatable, Sendable
{
  case available
  case offscreen
  case staleAnchor
  case ambiguousAnchor
  case superseded
  case accessibilityPermissionRequired
  case bearNotRunning
  case focusedEditorUnavailable
  case characterCountUnavailable
  case visibleRangeUnavailable
  case contextUnavailable
  case boundsUnsupported
  case boundsQueryFailed
  case invalidBounds
}

public struct BearCorrectionGeometryReport:
  Codable, Equatable, Sendable
{
  public let status: BearCorrectionGeometryStatus
  public let resolvedRange: AccessibilityTextRange?
  public let visibleRange: AccessibilityTextRange?
  public let bounds: AccessibilityBounds?
  public let fragments: [AccessibilityBounds]
  public let candidateCount: Int
  public let errorCode: Int32?

  public init(
    status: BearCorrectionGeometryStatus,
    resolvedRange: AccessibilityTextRange? = nil,
    visibleRange: AccessibilityTextRange? = nil,
    bounds: AccessibilityBounds? = nil,
    fragments: [AccessibilityBounds] = [],
    candidateCount: Int = 0,
    errorCode: Int32? = nil
  ) {
    self.status = status
    self.resolvedRange = resolvedRange
    self.visibleRange = visibleRange
    self.bounds = bounds
    self.fragments = fragments
    self.candidateCount = candidateCount
    self.errorCode = errorCode
  }

  public var isUsable: Bool {
    status == .available && bounds != nil && !fragments.isEmpty
  }
}

public protocol BearCorrectionGeometryProviding: Sendable {
  func geometry(
    for request: BearCorrectionGeometryRequest
  ) -> BearCorrectionGeometryReport
}

public struct BearCorrectionGeometryProvider:
  BearCorrectionGeometryProviding, Sendable
{
  public init() {}

  public func geometry(
    for request: BearCorrectionGeometryRequest
  ) -> BearCorrectionGeometryReport {
    guard AXIsProcessTrusted() else {
      return BearCorrectionGeometryReport(
        status: .accessibilityPermissionRequired
      )
    }
    guard
      let application = NSRunningApplication.runningApplications(
        withBundleIdentifier: BearAccessibilityProbe.bearBundleIdentifier
      ).first
    else {
      return BearCorrectionGeometryReport(status: .bearNotRunning)
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
      return BearCorrectionGeometryReport(
        status: .focusedEditorUnavailable
      )
    }

    return BearCorrectionGeometryTransaction().geometry(
      for: request,
      in: AXBearEditableTextClient(element: editorElement)
    )
  }
}

protocol BearGeometryTextClient: BearTextReadingClient {
  func visibleRange() -> AccessibilityTextRange?
  func bounds(
    for range: AccessibilityTextRange
  ) -> BearRangeBoundsQueryResult
}

enum BearRangeBoundsQueryResult: Equatable {
  case success(AccessibilityBounds)
  case unsupported
  case failed(errorCode: Int32?)
}

struct BearCorrectionGeometryTransaction {
  func geometry(
    for request: BearCorrectionGeometryRequest,
    in reader: BearGeometryTextClient
  ) -> BearCorrectionGeometryReport {
    let resolution = BearCorrectionAnchorResolver().resolve(
      anchor: request.anchor,
      expectedTexts: [request.expectedReplacement],
      in: reader
    )

    let resolvedRange: AccessibilityTextRange
    let resolvedText: String
    switch resolution {
    case .characterCountUnavailable:
      return report(.characterCountUnavailable)
    case .contextUnavailable:
      return report(.contextUnavailable)
    case .invalidated(let candidateCount):
      return report(
        candidateCount > 1 ? .ambiguousAnchor : .staleAnchor,
        candidateCount: candidateCount
      )
    case .matched(let range, let text):
      resolvedRange = range
      resolvedText = text
    }

    guard resolvedText == request.expectedReplacement else {
      return report(
        .superseded,
        resolvedRange: resolvedRange,
        candidateCount: 1
      )
    }
    guard let visibleRange = reader.visibleRange() else {
      return report(
        .visibleRangeUnavailable,
        resolvedRange: resolvedRange,
        candidateCount: 1
      )
    }
    guard isValid(visibleRange) else {
      return report(
        .visibleRangeUnavailable,
        resolvedRange: resolvedRange,
        visibleRange: visibleRange,
        candidateCount: 1
      )
    }
    guard contains(visibleRange, resolvedRange) else {
      return report(
        .offscreen,
        resolvedRange: resolvedRange,
        visibleRange: visibleRange,
        candidateCount: 1
      )
    }

    switch reader.bounds(for: resolvedRange) {
    case .success(let bounds):
      guard bounds.isUsableScreenRect else {
        return report(
          .invalidBounds,
          resolvedRange: resolvedRange,
          visibleRange: visibleRange,
          candidateCount: 1
        )
      }
      return resolvedGeometryReport(
        wholeBounds: bounds,
        resolvedRange: resolvedRange,
        resolvedText: resolvedText,
        visibleRange: visibleRange,
        reader: reader
      )
    case .unsupported:
      return report(
        .boundsUnsupported,
        resolvedRange: resolvedRange,
        visibleRange: visibleRange,
        candidateCount: 1
      )
    case .failed(let errorCode):
      return BearCorrectionGeometryReport(
        status: .boundsQueryFailed,
        resolvedRange: resolvedRange,
        visibleRange: visibleRange,
        candidateCount: 1,
        errorCode: errorCode
      )
    }
  }

  private func resolvedGeometryReport(
    wholeBounds: AccessibilityBounds,
    resolvedRange: AccessibilityTextRange,
    resolvedText: String,
    visibleRange: AccessibilityTextRange,
    reader: BearGeometryTextClient
  ) -> BearCorrectionGeometryReport {
    let characterRanges = composedCharacterRanges(
      in: resolvedText,
      startingAt: resolvedRange.location
    )
    guard
      let firstRange = characterRanges.first,
      let lastRange = characterRanges.last
    else {
      return report(
        .invalidBounds,
        resolvedRange: resolvedRange,
        visibleRange: visibleRange,
        candidateCount: 1
      )
    }

    let firstResult = reader.bounds(for: firstRange)
    let lastResult =
      firstRange == lastRange
      ? firstResult
      : reader.bounds(for: lastRange)
    guard
      case .success(let firstBounds) = firstResult,
      case .success(let lastBounds) = lastResult,
      firstBounds.isUsableScreenRect,
      lastBounds.isUsableScreenRect
    else {
      return mapFragmentFailure(
        firstResult: firstResult,
        lastResult: lastResult,
        resolvedRange: resolvedRange,
        visibleRange: visibleRange
      )
    }

    let referenceHeight = max(firstBounds.height, lastBounds.height)
    guard wholeBounds.height > referenceHeight * 1.35 else {
      return report(
        .available,
        resolvedRange: resolvedRange,
        visibleRange: visibleRange,
        bounds: wholeBounds,
        fragments: [wholeBounds],
        candidateCount: 1
      )
    }

    var characterBounds: [AccessibilityBounds] = []
    for range in characterRanges {
      let result: BearRangeBoundsQueryResult
      if range == firstRange {
        result = firstResult
      } else if range == lastRange {
        result = lastResult
      } else {
        result = reader.bounds(for: range)
      }
      switch result {
      case .success(let bounds) where bounds.isUsableScreenRect:
        characterBounds.append(bounds)
      case .success(let bounds)
      where bounds.width == 0 && bounds.height.isFinite && bounds.height > 0:
        // A newline can have zero width while still separating valid lines.
        continue
      case .success:
        return report(
          .invalidBounds,
          resolvedRange: resolvedRange,
          visibleRange: visibleRange,
          candidateCount: 1
        )
      case .unsupported:
        return report(
          .boundsUnsupported,
          resolvedRange: resolvedRange,
          visibleRange: visibleRange,
          candidateCount: 1
        )
      case .failed(let errorCode):
        return BearCorrectionGeometryReport(
          status: .boundsQueryFailed,
          resolvedRange: resolvedRange,
          visibleRange: visibleRange,
          candidateCount: 1,
          errorCode: errorCode
        )
      }
    }
    let fragments = lineFragments(from: characterBounds)
    guard !fragments.isEmpty else {
      return report(
        .invalidBounds,
        resolvedRange: resolvedRange,
        visibleRange: visibleRange,
        candidateCount: 1
      )
    }
    return report(
      .available,
      resolvedRange: resolvedRange,
      visibleRange: visibleRange,
      bounds: fragments.unionBounds,
      fragments: fragments,
      candidateCount: 1
    )
  }

  private func composedCharacterRanges(
    in text: String,
    startingAt globalLocation: Int
  ) -> [AccessibilityTextRange] {
    var ranges: [AccessibilityTextRange] = []
    text.enumerateSubstrings(
      in: text.startIndex..<text.endIndex,
      options: .byComposedCharacterSequences
    ) { _, range, _, _ in
      let localRange = NSRange(range, in: text)
      ranges.append(
        AccessibilityTextRange(
          location: globalLocation + localRange.location,
          length: localRange.length
        )
      )
    }
    return ranges
  }

  private func lineFragments(
    from characterBounds: [AccessibilityBounds]
  ) -> [AccessibilityBounds] {
    let sorted = characterBounds.sorted {
      if abs($0.y - $1.y) < 0.5 {
        return $0.x < $1.x
      }
      return $0.y < $1.y
    }
    var lines: [AccessibilityBounds] = []
    for bounds in sorted {
      if let index = lines.lastIndex(where: { sameLine($0, bounds) }) {
        lines[index] = lines[index].union(bounds)
      } else {
        lines.append(bounds)
      }
    }
    return lines.sorted {
      if abs($0.y - $1.y) < 0.5 {
        return $0.x < $1.x
      }
      return $0.y < $1.y
    }
  }

  private func sameLine(
    _ lhs: AccessibilityBounds,
    _ rhs: AccessibilityBounds
  ) -> Bool {
    let overlap =
      min(lhs.y + lhs.height, rhs.y + rhs.height)
      - max(lhs.y, rhs.y)
    return overlap > min(lhs.height, rhs.height) * 0.5
  }

  private func mapFragmentFailure(
    firstResult: BearRangeBoundsQueryResult,
    lastResult: BearRangeBoundsQueryResult,
    resolvedRange: AccessibilityTextRange,
    visibleRange: AccessibilityTextRange
  ) -> BearCorrectionGeometryReport {
    if firstResult == .unsupported || lastResult == .unsupported {
      return report(
        .boundsUnsupported,
        resolvedRange: resolvedRange,
        visibleRange: visibleRange,
        candidateCount: 1
      )
    }
    var errorCode: Int32?
    for result in [firstResult, lastResult] {
      if case .failed(let code) = result, let code {
        errorCode = code
        break
      }
    }
    if [firstResult, lastResult].contains(where: {
      if case .failed = $0 { return true }
      return false
    }) {
      return BearCorrectionGeometryReport(
        status: .boundsQueryFailed,
        resolvedRange: resolvedRange,
        visibleRange: visibleRange,
        candidateCount: 1,
        errorCode: errorCode
      )
    }
    return report(
      .invalidBounds,
      resolvedRange: resolvedRange,
      visibleRange: visibleRange,
      candidateCount: 1
    )
  }

  private func isValid(_ range: AccessibilityTextRange) -> Bool {
    range.location >= 0 && range.length >= 0
  }

  private func contains(
    _ visibleRange: AccessibilityTextRange,
    _ targetRange: AccessibilityTextRange
  ) -> Bool {
    targetRange.location >= visibleRange.location
      && targetRange.location + targetRange.length
        <= visibleRange.location + visibleRange.length
  }

  private func report(
    _ status: BearCorrectionGeometryStatus,
    resolvedRange: AccessibilityTextRange? = nil,
    visibleRange: AccessibilityTextRange? = nil,
    bounds: AccessibilityBounds? = nil,
    fragments: [AccessibilityBounds] = [],
    candidateCount: Int = 0
  ) -> BearCorrectionGeometryReport {
    BearCorrectionGeometryReport(
      status: status,
      resolvedRange: resolvedRange,
      visibleRange: visibleRange,
      bounds: bounds,
      fragments: fragments,
      candidateCount: candidateCount
    )
  }
}

extension AccessibilityBounds {
  fileprivate var isUsableScreenRect: Bool {
    x.isFinite
      && y.isFinite
      && width.isFinite
      && height.isFinite
      && width > 0
      && height > 0
  }

  fileprivate func union(_ other: AccessibilityBounds) -> AccessibilityBounds {
    let minimumX = min(x, other.x)
    let minimumY = min(y, other.y)
    let maximumX = max(x + width, other.x + other.width)
    let maximumY = max(y + height, other.y + other.height)
    return AccessibilityBounds(
      x: minimumX,
      y: minimumY,
      width: maximumX - minimumX,
      height: maximumY - minimumY
    )
  }
}

extension [AccessibilityBounds] {
  fileprivate var unionBounds: AccessibilityBounds? {
    guard let first else {
      return nil
    }
    return dropFirst().reduce(first) { partial, next in
      partial.union(next)
    }
  }
}

extension AXBearEditableTextClient: BearGeometryTextClient {
  func visibleRange() -> AccessibilityTextRange? {
    copyRangeAttribute(
      element,
      kAXVisibleCharacterRangeAttribute as CFString
    )
  }

  func bounds(
    for range: AccessibilityTextRange
  ) -> BearRangeBoundsQueryResult {
    var rawRange = CFRange(
      location: range.location,
      length: range.length
    )
    guard let parameter = AXValueCreate(.cfRange, &rawRange) else {
      return .failed(errorCode: AXError.illegalArgument.rawValue)
    }

    var rawValue: CFTypeRef?
    let error = AXUIElementCopyParameterizedAttributeValue(
      element,
      kAXBoundsForRangeParameterizedAttribute as CFString,
      parameter,
      &rawValue
    )
    guard error == .success else {
      if error == .parameterizedAttributeUnsupported
        || error == .attributeUnsupported
      {
        return .unsupported
      }
      return .failed(errorCode: error.rawValue)
    }
    guard
      let rawValue,
      CFGetTypeID(rawValue) == AXValueGetTypeID()
    else {
      return .failed(errorCode: nil)
    }
    let value = unsafeDowncast(rawValue, to: AXValue.self)
    guard AXValueGetType(value) == .cgRect else {
      return .failed(errorCode: nil)
    }
    var rect = CGRect.zero
    guard AXValueGetValue(value, .cgRect, &rect) else {
      return .failed(errorCode: nil)
    }
    return .success(
      AccessibilityBounds(
        x: rect.origin.x,
        y: rect.origin.y,
        width: rect.size.width,
        height: rect.size.height
      )
    )
  }
}
