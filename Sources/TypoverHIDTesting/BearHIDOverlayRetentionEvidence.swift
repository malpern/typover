import Foundation

public enum BearHIDOverlayRetentionClassification: String, Codable, Sendable {
  case retained
  case mismatch
  case unavailable
}

public struct BearHIDOverlayRetentionEvidence: Codable, Equatable, Sendable {
  public let baselineVisibleCorrections: Int?
  public let finalVisibleCorrections: Int?
  public let expectedVisibleCorrectionsFromEmptyBaseline: Int

  public init(
    baselineVisibleCorrections: Int?,
    finalVisibleCorrections: Int?,
    correctedWords: Int,
    maximumTrackedCorrections: Int
  ) {
    self.baselineVisibleCorrections = baselineVisibleCorrections
    self.finalVisibleCorrections = finalVisibleCorrections
    expectedVisibleCorrectionsFromEmptyBaseline = min(
      max(0, correctedWords),
      max(0, maximumTrackedCorrections)
    )
  }

  /// Exact retention evidence is available only when the app began without
  /// prior correction windows. A nonzero baseline is still recorded, but a
  /// final count alone cannot prove that every visible window belongs to the
  /// current physical burst.
  public var fullyRetainedFromEmptyBaseline: Bool? {
    guard baselineVisibleCorrections == 0,
          let finalVisibleCorrections
    else {
      return nil
    }
    return finalVisibleCorrections
      == expectedVisibleCorrectionsFromEmptyBaseline
  }

  public var classification: BearHIDOverlayRetentionClassification {
    switch fullyRetainedFromEmptyBaseline {
    case true: .retained
    case false: .mismatch
    case nil: .unavailable
    }
  }

  public var conciseDescription: String {
    switch classification {
    case .retained:
      "overlays retained \(finalVisibleCorrections ?? 0)/\(expectedVisibleCorrectionsFromEmptyBaseline)"
    case .mismatch:
      "overlay sample \(finalVisibleCorrections ?? 0)/\(expectedVisibleCorrectionsFromEmptyBaseline)"
    case .unavailable:
      "overlay evidence unavailable"
    }
  }
}
