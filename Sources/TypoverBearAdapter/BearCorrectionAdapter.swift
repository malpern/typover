import TypoverAccessibility
import TypoverCore

public struct BearCorrectionApplication: Equatable, Sendable {
  public let report: BearExactRangeReplacementReport
  public let correction: Correction
  public let correctionRecord: CorrectionRecord?
  public let correctionAnchor: BearCorrectionAnchor?

  public init(
    report: BearExactRangeReplacementReport,
    correction: Correction,
    correctionRecord: CorrectionRecord?,
    correctionAnchor: BearCorrectionAnchor? = nil
  ) {
    self.report = report
    self.correction = correction
    self.correctionRecord = correctionRecord
    self.correctionAnchor = correctionAnchor
  }
}

public struct BearCorrectionRestoration: Equatable, Sendable {
  public let report: BearCorrectionRestorationReport
  public let correctionRecord: CorrectionRecord

  public init(
    report: BearCorrectionRestorationReport,
    correctionRecord: CorrectionRecord
  ) {
    self.report = report
    self.correctionRecord = correctionRecord
  }
}

public struct BearCorrectionAlternativeApplication: Equatable, Sendable {
  public let report: BearCorrectionRetargetReport
  public let application: BearCorrectionApplication?

  public init(
    report: BearCorrectionRetargetReport,
    application: BearCorrectionApplication?
  ) {
    self.report = report
    self.application = application
  }
}

public struct BearCorrectionAdapter: Sendable {
  private let replacer: any BearExactRangeReplacing
  private let restorer: any BearCorrectionRestoring
  private let geometryProvider: any BearCorrectionGeometryProviding
  private let retargeter: any BearCorrectionRetargeting
  private let selectionStabilizer: any BearCorrectionSelectionStabilizing

  public init(
    replacer: any BearExactRangeReplacing = BearExactRangeReplacer(),
    restorer: any BearCorrectionRestoring = BearCorrectionRestorer(),
    geometryProvider: any BearCorrectionGeometryProviding =
      BearCorrectionGeometryProvider(),
    retargeter: any BearCorrectionRetargeting = BearCorrectionRetargeter(),
    selectionStabilizer: any BearCorrectionSelectionStabilizing =
      BearCorrectionSelectionStabilizer()
  ) {
    self.replacer = replacer
    self.restorer = restorer
    self.geometryProvider = geometryProvider
    self.retargeter = retargeter
    self.selectionStabilizer = selectionStabilizer
  }

  public func apply(
    original: String,
    replacement: String,
    at targetRange: AccessibilityTextRange
  ) -> BearCorrectionApplication {
    let outcome = replacer.replace(
      BearExactRangeReplacementRequest(
        targetRange: targetRange,
        expectedOriginal: original,
        replacement: replacement
      )
    )
    let report = outcome.report
    let correction = Correction(
      original: original,
      replacement: replacement
    )
    let record =
      report.isVerifiedApplication && outcome.correctionAnchor != nil
      ? CorrectionRecord(correction: correction)
      : nil
    return BearCorrectionApplication(
      report: report,
      correction: correction,
      correctionRecord: record,
      correctionAnchor: outcome.correctionAnchor
    )
  }

  public func changeBack(
    _ application: BearCorrectionApplication
  ) -> BearCorrectionRestoration {
    guard
      let anchor = application.correctionAnchor,
      let currentRecord = application.correctionRecord
    else {
      return BearCorrectionRestoration(
        report: BearCorrectionRestorationReport(status: .invalidated),
        correctionRecord: CorrectionRecord(
          correction: application.correction,
          disposition: .invalidated
        )
      )
    }

    let report = restorer.restore(
      BearCorrectionRestorationRequest(
        anchor: anchor,
        expectedReplacement: application.correction.replacement,
        original: application.correction.original
      )
    )
    let disposition: CorrectionDisposition =
      switch report.status {
      case .restored, .alreadyRestored:
        .restored
      case .superseded:
        .superseded
      case .invalidated:
        .invalidated
      default:
        currentRecord.disposition
      }
    return BearCorrectionRestoration(
      report: report,
      correctionRecord: CorrectionRecord(
        correction: application.correction,
        disposition: disposition
      )
    )
  }

  public func geometry(
    for application: BearCorrectionApplication
  ) -> BearCorrectionGeometryReport {
    guard
      application.correctionRecord?.disposition == .applied,
      let anchor = application.correctionAnchor
    else {
      return BearCorrectionGeometryReport(status: .staleAnchor)
    }
    return geometryProvider.geometry(
      for: BearCorrectionGeometryRequest(
        anchor: anchor,
        expectedReplacement: application.correction.replacement
      )
    )
  }

  public func chooseAlternative(
    _ replacement: String,
    for application: BearCorrectionApplication
  ) -> BearCorrectionAlternativeApplication {
    guard
      application.correctionRecord?.disposition == .applied,
      let anchor = application.correctionAnchor,
      !replacement.isEmpty,
      replacement != application.correction.original
    else {
      return BearCorrectionAlternativeApplication(
        report: BearCorrectionRetargetReport(status: .invalidated),
        application: nil
      )
    }

    let outcome = retargeter.retarget(
      BearCorrectionRetargetRequest(
        anchor: anchor,
        expectedCurrent: application.correction.replacement,
        replacement: replacement
      )
    )
    guard
      outcome.report.status == .applied
        || outcome.report.status == .alreadyApplied,
      let replacementReport = outcome.report.replacementReport,
      let updatedAnchor = outcome.correctionAnchor
    else {
      return BearCorrectionAlternativeApplication(
        report: outcome.report,
        application: nil
      )
    }

    let correction = Correction(
      original: application.correction.original,
      replacement: replacement
    )
    return BearCorrectionAlternativeApplication(
      report: outcome.report,
      application: BearCorrectionApplication(
        report: replacementReport,
        correction: correction,
        correctionRecord: CorrectionRecord(correction: correction),
        correctionAnchor: updatedAnchor
      )
    )
  }

  public func stabilizeSelection(
    _ request: BearCorrectionSelectionStabilizationRequest
  ) -> BearCorrectionSelectionStabilizationStatus {
    selectionStabilizer.stabilizeSelection(request)
  }
}
