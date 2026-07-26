import TypoverAccessibility
import TypoverCore

public struct BearCorrectionApplication: Equatable, Sendable {
  public let report: BearExactRangeReplacementReport
  public let correction: Correction
  public let correctionRecord: CorrectionRecord?

  public init(
    report: BearExactRangeReplacementReport,
    correction: Correction,
    correctionRecord: CorrectionRecord?
  ) {
    self.report = report
    self.correction = correction
    self.correctionRecord = correctionRecord
  }
}

public struct BearCorrectionAdapter: Sendable {
  private let replacer: any BearExactRangeReplacing

  public init(
    replacer: any BearExactRangeReplacing = BearExactRangeReplacer()
  ) {
    self.replacer = replacer
  }

  public func apply(
    original: String,
    replacement: String,
    at targetRange: AccessibilityTextRange
  ) -> BearCorrectionApplication {
    let report = replacer.replace(
      BearExactRangeReplacementRequest(
        targetRange: targetRange,
        expectedOriginal: original,
        replacement: replacement
      )
    )
    let correction = Correction(
      original: original,
      replacement: replacement
    )
    let record = report.isVerifiedApplication
      ? CorrectionRecord(correction: correction)
      : nil
    return BearCorrectionApplication(
      report: report,
      correction: correction,
      correctionRecord: record
    )
  }
}
