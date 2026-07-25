import Foundation
import TypoverCore

public enum ContextualEvaluationOutcome: String, Codable, Sendable {
  case passed
  case falsePositive
  case missedCorrection
  case wrongCorrection
  case unavailable
  case error
}

public struct ContextualEvaluationResult: Codable, Sendable {
  public let caseID: String
  public let category: String
  public let reviewStatus: CorrectionCorpusReviewStatus
  public let outcome: ContextualEvaluationOutcome
  public let expectedOriginal: String?
  public let expectedReplacement: String?
  public let actualOriginal: String?
  public let actualReplacement: String?
  public let lookupMilliseconds: Double?
}

public struct ContextualEvaluationReport: Codable, Sendable {
  public let schemaVersion: Int
  public let availability: String
  public let results: [ContextualEvaluationResult]

  public var totalCount: Int {
    results.count
  }

  public var passedCount: Int {
    results.count(where: { $0.outcome == .passed })
  }

  public var falsePositiveCount: Int {
    results.count(where: { $0.outcome == .falsePositive })
  }

  public var missedCorrectionCount: Int {
    results.count(where: { $0.outcome == .missedCorrection })
  }

  public var wrongCorrectionCount: Int {
    results.count(where: { $0.outcome == .wrongCorrection })
  }

  public var unavailableCount: Int {
    results.count(where: { $0.outcome == .unavailable })
  }

  public var errorCount: Int {
    results.count(where: { $0.outcome == .error })
  }

  public var medianLookupMilliseconds: Double {
    percentile(0.5)
  }

  public var p95LookupMilliseconds: Double {
    percentile(0.95)
  }

  private func percentile(_ percentile: Double) -> Double {
    let values = results.compactMap(\.lookupMilliseconds).sorted()
    guard !values.isEmpty else {
      return 0
    }
    let index = Int(
      (Double(values.count - 1) * percentile).rounded(.up)
    )
    return values[index]
  }
}

public struct ContextualCorrectionEvaluator {
  private let engine: any ContextualCorrectionEngine

  public init(engine: any ContextualCorrectionEngine) {
    self.engine = engine
  }

  public func evaluate(
    _ corpus: ContextualCorrectionCorpus
  ) async -> ContextualEvaluationReport {
    var results: [ContextualEvaluationResult] = []
    var availabilityName = "available"

    for testCase in corpus.cases {
      let availability = await engine.availability(
        for: testCase.language
      )
      guard availability == .available else {
        availabilityName = Self.name(for: availability)
        results.append(
          result(
            for: testCase,
            candidate: nil,
            outcome: .unavailable
          )
        )
        continue
      }

      do {
        let clock = ContinuousClock()
        let start = clock.now
        let candidate = try await engine.proposal(
          for: ContextualCorrectionRequest(
            sentence: testCase.sentence,
            language: testCase.language
          )
        )
        let lookupDuration = start.duration(to: clock.now)
        results.append(
          result(
            for: testCase,
            candidate: candidate,
            lookupDuration: lookupDuration,
            outcome: outcome(
              for: testCase.expectation,
              candidate: candidate
            )
          )
        )
      } catch {
        results.append(
          result(
            for: testCase,
            candidate: nil,
            outcome: .error
          )
        )
      }
    }

    return ContextualEvaluationReport(
      schemaVersion: corpus.schemaVersion,
      availability: availabilityName,
      results: results
    )
  }

  private func outcome(
    for expectation: ContextualCorrectionExpectation,
    candidate: ContextualCorrectionCandidate?
  ) -> ContextualEvaluationOutcome {
    switch (expectation, candidate) {
    case (.unchanged, nil):
      .passed
    case (.unchanged, .some):
      .falsePositive
    case (.correction, nil):
      .missedCorrection
    case (
      .correction(let original, let replacement),
      .some(let candidate)
    ):
      candidate.original == original
        && candidate.replacement == replacement
        ? .passed
        : .wrongCorrection
    }
  }

  private func result(
    for testCase: ContextualCorrectionCorpusCase,
    candidate: ContextualCorrectionCandidate?,
    lookupDuration: Duration? = nil,
    outcome: ContextualEvaluationOutcome
  ) -> ContextualEvaluationResult {
    let expected: (String?, String?) =
      switch testCase.expectation {
      case .correction(let original, let replacement):
        (original, replacement)
      case .unchanged:
        (nil, nil)
      }
    return ContextualEvaluationResult(
      caseID: testCase.id,
      category: testCase.category,
      reviewStatus: testCase.reviewStatus,
      outcome: outcome,
      expectedOriginal: expected.0,
      expectedReplacement: expected.1,
      actualOriginal: candidate?.original,
      actualReplacement: candidate?.replacement,
      lookupMilliseconds: lookupDuration.map(Self.milliseconds)
    )
  }

  private static func milliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
  }

  private static func name(
    for availability: ContextualCorrectionAvailability
  ) -> String {
    switch availability {
    case .available:
      "available"
    case .unavailable(.appleIntelligenceNotEnabled):
      "apple-intelligence-not-enabled"
    case .unavailable(.deviceNotEligible):
      "device-not-eligible"
    case .unavailable(.modelNotReady):
      "model-not-ready"
    case .unavailable(.unsupportedLanguage):
      "unsupported-language"
    }
  }
}
