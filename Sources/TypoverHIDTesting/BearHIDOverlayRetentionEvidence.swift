import Foundation

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
}
