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

  /// True when Typover has enough verified state to expose Change Back even
  /// if the original write's final caret/context verification was incomplete.
  public var isReversibleApplication: Bool {
    report.writeOccurred
      && correctionRecord?.disposition == .applied
      && correctionAnchor != nil
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

public struct BearCorrectionReanchoredApplication: Equatable, Sendable {
  public let status: BearCorrectionReanchorStatus
  public let application: BearCorrectionApplication?

  public init(
    status: BearCorrectionReanchorStatus,
    application: BearCorrectionApplication?
  ) {
    self.status = status
    self.application = application
  }
}

public struct BearSyntheticCorrectionAdoptionRequest: Equatable, Sendable {
  public let original: String
  public let replacement: String
  public let originalRange: AccessibilityTextRange
  public let replacementRange: AccessibilityTextRange
  public let selectionAfter: AccessibilityTextRange

  public init(
    original: String,
    replacement: String,
    originalRange: AccessibilityTextRange,
    replacementRange: AccessibilityTextRange,
    selectionAfter: AccessibilityTextRange
  ) {
    self.original = original
    self.replacement = replacement
    self.originalRange = originalRange
    self.replacementRange = replacementRange
    self.selectionAfter = selectionAfter
  }
}

public struct BearCorrectionAdapter: Sendable {
  private let replacer: any BearExactRangeReplacing
  private let restorer: any BearCorrectionRestoring
  private let geometryProvider: any BearCorrectionGeometryProviding
  private let retargeter: any BearCorrectionRetargeting
  private let reanchorer: any BearCorrectionReanchoring
  private let selectionStabilizer: any BearCorrectionSelectionStabilizing

  public init(
    replacer: any BearExactRangeReplacing = BearExactRangeReplacer(),
    restorer: any BearCorrectionRestoring = BearCorrectionRestorer(),
    geometryProvider: any BearCorrectionGeometryProviding =
      BearCorrectionGeometryProvider(),
    retargeter: any BearCorrectionRetargeting = BearCorrectionRetargeter(),
    reanchorer: any BearCorrectionReanchoring = BearCorrectionReanchorer(),
    selectionStabilizer: any BearCorrectionSelectionStabilizing =
      BearCorrectionSelectionStabilizer()
  ) {
    self.replacer = replacer
    self.restorer = restorer
    self.geometryProvider = geometryProvider
    self.retargeter = retargeter
    self.reanchorer = reanchorer
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
    let anchor: BearCorrectionAnchor?
    if let correctionAnchor = outcome.correctionAnchor {
      anchor = correctionAnchor
    } else if report.writeOccurred,
      let replacementRange = report.replacementRange
    {
      // A successful AX write can be followed by a failed caret restoration
      // or bounded verification read. Re-read the exact replacement range and
      // recover an anchor before returning; never silently discard a mutation
      // that the user may need to reverse.
      anchor =
        reanchorer.reanchor(
          BearCorrectionReanchorRequest(
            targetRange: replacementRange,
            expectedText: replacement,
            leadingContextLimit: 256,
            trailingContextLimit: 256
          )
        ).correctionAnchor
    } else {
      anchor = nil
    }
    let record =
      report.writeOccurred && anchor != nil
      ? CorrectionRecord(correction: correction)
      : nil
    return BearCorrectionApplication(
      report: report,
      correction: correction,
      correctionRecord: record,
      correctionAnchor: anchor
    )
  }

  /// Adopts a correction whose text was already changed by the experimental
  /// synthetic-input lane. This method performs no write. It verifies the
  /// replacement again through Bear Accessibility and creates the same
  /// bounded reversible anchor used by exact-range AX applications.
  public func adoptSyntheticCorrection(
    _ request: BearSyntheticCorrectionAdoptionRequest
  ) -> BearCorrectionApplication {
    let correction = Correction(
      original: request.original,
      replacement: request.replacement
    )
    guard
      correction.changesText,
      request.originalRange.location >= 0,
      request.originalRange.length == request.original.utf16.count,
      request.replacementRange.location == request.originalRange.location,
      request.replacementRange.length == request.replacement.utf16.count,
      request.selectionAfter.location >= 0,
      request.selectionAfter.length == 0
    else {
      return syntheticApplication(
        correction: correction,
        request: request,
        status: .invalidRequest,
        anchor: nil
      )
    }

    let outcome = reanchorer.reanchor(
      BearCorrectionReanchorRequest(
        targetRange: request.replacementRange,
        expectedText: request.replacement,
        leadingContextLimit: 256,
        trailingContextLimit: 256
      )
    )
    guard let anchor = outcome.correctionAnchor else {
      return syntheticApplication(
        correction: correction,
        request: request,
        status: .verificationFailed,
        anchor: nil
      )
    }
    return syntheticApplication(
      correction: correction,
      request: request,
      status: .applied,
      anchor: anchor
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

  public func reanchor(
    _ application: BearCorrectionApplication,
    at targetRange: AccessibilityTextRange
  ) -> BearCorrectionReanchoredApplication {
    guard
      application.correctionRecord?.disposition == .applied,
      let oldAnchor = application.correctionAnchor
    else {
      return BearCorrectionReanchoredApplication(
        status: .invalidRequest,
        application: nil
      )
    }
    let outcome = reanchorer.reanchor(
      BearCorrectionReanchorRequest(
        targetRange: targetRange,
        expectedText: application.correction.replacement,
        leadingContextLimit: oldAnchor.leadingContextLength,
        trailingContextLimit: oldAnchor.trailingContextLength
      )
    )
    guard let anchor = outcome.correctionAnchor else {
      return BearCorrectionReanchoredApplication(
        status: outcome.status,
        application: nil
      )
    }
    return BearCorrectionReanchoredApplication(
      status: outcome.status,
      application: BearCorrectionApplication(
        report: application.report,
        correction: application.correction,
        correctionRecord: application.correctionRecord,
        correctionAnchor: anchor
      )
    )
  }

  private func syntheticApplication(
    correction: Correction,
    request: BearSyntheticCorrectionAdoptionRequest,
    status: BearExactRangeReplacementStatus,
    anchor: BearCorrectionAnchor?
  ) -> BearCorrectionApplication {
    BearCorrectionApplication(
      report: BearExactRangeReplacementReport(
        status: status,
        writeOccurred: true,
        targetRange: request.originalRange,
        replacementRange: request.replacementRange,
        selectionBefore: nil,
        selectionAfter: request.selectionAfter,
        surroundingContextVerified: anchor != nil,
        caretRestored: anchor != nil
      ),
      correction: correction,
      correctionRecord: anchor.map { _ in
        CorrectionRecord(correction: correction)
      },
      correctionAnchor: anchor
    )
  }
}
