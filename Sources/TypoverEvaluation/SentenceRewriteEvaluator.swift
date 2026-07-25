import Foundation
import TypoverCore

public enum SentenceRewriteEvaluationOutcome: String, Codable, Sendable {
  case passed
  case candidateRewrite
  case falsePositive
  case missedRewrite
  case returnedEdits
  case preservationFailure
  case unsafeProposal
  case unavailable
  case error
}

public struct SentenceRewriteEvaluationResult: Codable, Sendable {
  public let caseID: String
  public let category: String
  public let reviewStatus: CorrectionCorpusReviewStatus
  public let expectedRewrite: Bool
  public let outcome: SentenceRewriteEvaluationOutcome
  public let inputSentence: String
  public let actualReplacement: String?
  public let failedProtectedFragments: [String]
  public let presentForbiddenFragments: [String]
  public let proposalRejectedBySafety: Bool
  public let errorDescription: String?
  public let lookupMilliseconds: Double?
}

public struct SentenceRewriteEvaluationReport: Codable, Sendable {
  public let schemaVersion: Int
  public let availability: String
  public let results: [SentenceRewriteEvaluationResult]

  public var totalCount: Int { results.count }

  public var passedUnchangedCount: Int {
    count(.passed)
  }

  public var candidateRewriteCount: Int {
    count(.candidateRewrite)
  }

  public var falsePositiveCount: Int {
    count(.falsePositive)
  }

  public var missedRewriteCount: Int {
    count(.missedRewrite)
  }

  public var returnedEditsCount: Int {
    count(.returnedEdits)
  }

  public var preservationFailureCount: Int {
    count(.preservationFailure)
  }

  public var unsafeProposalCount: Int {
    count(.unsafeProposal)
  }

  public var rejectedProposalCount: Int {
    results.count(where: \.proposalRejectedBySafety)
  }

  public var unavailableCount: Int {
    count(.unavailable)
  }

  public var errorCount: Int {
    count(.error)
  }

  public var unchangedCaseCount: Int {
    results.count { !$0.expectedRewrite }
  }

  public var expectedRewriteCount: Int {
    results.count(where: \.expectedRewrite)
  }

  public var unwarrantedRewriteRate: Double {
    guard unchangedCaseCount > 0 else { return 0 }
    return Double(falsePositiveCount) / Double(unchangedCaseCount)
  }

  public var rewriteCandidateRate: Double {
    guard expectedRewriteCount > 0 else { return 0 }
    return Double(candidateRewriteCount) / Double(expectedRewriteCount)
  }

  public var medianLookupMilliseconds: Double {
    percentile(0.5, values: lookupValues)
  }

  public var p95LookupMilliseconds: Double {
    percentile(0.95, values: lookupValues)
  }

  public var firstLookupMilliseconds: Double {
    lookupValues.first ?? 0
  }

  public var warmMedianLookupMilliseconds: Double {
    percentile(0.5, values: Array(lookupValues.dropFirst()))
  }

  private var lookupValues: [Double] {
    results.compactMap(\.lookupMilliseconds)
  }

  private func count(_ outcome: SentenceRewriteEvaluationOutcome) -> Int {
    results.count { $0.outcome == outcome }
  }

  private func percentile(_ percentile: Double, values: [Double]) -> Double {
    let ordered = values.sorted()
    guard !ordered.isEmpty else { return 0 }
    let index = Int(
      (Double(ordered.count - 1) * percentile).rounded(.up)
    )
    return ordered[index]
  }
}

public struct SentenceRewriteEvaluator {
  private let engine: any ContextualCorrectionEngine

  public init(engine: any ContextualCorrectionEngine) {
    self.engine = engine
  }

  public func evaluate(
    _ corpus: SentenceRewriteCorpus
  ) async -> SentenceRewriteEvaluationReport {
    var results: [SentenceRewriteEvaluationResult] = []
    var availabilityName = "available"

    for testCase in corpus.cases {
      let availability = await engine.availability(for: testCase.language)
      guard availability == .available else {
        availabilityName = Self.name(for: availability)
        results.append(
          result(for: testCase, outcome: .unavailable)
        )
        continue
      }

      do {
        let clock = ContinuousClock()
        let start = clock.now
        let proposal = try await engine.proposal(
          for: ContextualCorrectionRequest(
            sentence: testCase.sentence,
            language: testCase.language,
            scope: .comprehensive,
            allowsSentenceRewrite: true
          )
        )
        let duration = start.duration(to: clock.now)
        results.append(
          evaluate(
            proposal,
            for: testCase,
            lookupDuration: duration
          )
        )
      } catch {
        results.append(
          result(
            for: testCase,
            errorDescription: String(describing: error),
            outcome: .error
          )
        )
      }
    }

    return SentenceRewriteEvaluationReport(
      schemaVersion: corpus.schemaVersion,
      availability: availabilityName,
      results: results
    )
  }

  private func evaluate(
    _ proposal: ContextualCorrectionResult?,
    for testCase: SentenceRewriteCorpusCase,
    lookupDuration: Duration
  ) -> SentenceRewriteEvaluationResult {
    guard let proposal else {
      return result(
        for: testCase,
        lookupDuration: lookupDuration,
        outcome: testCase.expectation == .unchanged
          ? .passed
          : .missedRewrite
      )
    }

    guard
      proposal.candidates.count == 1,
      let candidate = proposal.candidates.first
    else {
      return result(
        for: testCase,
        actualReplacement: proposal.candidates.first?.replacement,
        lookupDuration: lookupDuration,
        outcome: testCase.expectation == .unchanged
          ? .falsePositive
          : .returnedEdits
      )
    }

    if candidate.kind != .sentenceRewrite {
      let applies =
        ContextualCorrectionResolver.resolve(
          proposal,
          in: completedSentence(for: testCase),
          language: testCase.language
        ) != nil
      return result(
        for: testCase,
        actualReplacement: candidate.replacement,
        proposalRejectedBySafety: !applies,
        lookupDuration: lookupDuration,
        outcome:
          applies
          ? (testCase.expectation == .unchanged
            ? .falsePositive
            : .returnedEdits)
          : (testCase.expectation == .unchanged
            ? .passed
            : .missedRewrite)
      )
    }

    guard
      ContextualCorrectionResolver.resolve(
        proposal,
        in: completedSentence(for: testCase),
        language: testCase.language
      ) != nil
    else {
      return result(
        for: testCase,
        actualReplacement: candidate.replacement,
        proposalRejectedBySafety: true,
        lookupDuration: lookupDuration,
        outcome: testCase.expectation == .unchanged
          ? .passed
          : .missedRewrite
      )
    }

    switch testCase.expectation {
    case .unchanged:
      return result(
        for: testCase,
        actualReplacement: candidate.replacement,
        lookupDuration: lookupDuration,
        outcome: .falsePositive
      )
    case .rewrite(let protectedFragments, let forbiddenFragments):
      let failedProtectedFragments = protectedFragments.filter {
        !candidate.replacement.localizedCaseInsensitiveContains($0)
      }
      let presentForbiddenFragments = forbiddenFragments.filter {
        candidate.replacement.localizedCaseInsensitiveContains($0)
      }
      let outcome: SentenceRewriteEvaluationOutcome =
        failedProtectedFragments.isEmpty
          && presentForbiddenFragments.isEmpty
        ? .candidateRewrite
        : .preservationFailure
      return result(
        for: testCase,
        actualReplacement: candidate.replacement,
        failedProtectedFragments: failedProtectedFragments,
        presentForbiddenFragments: presentForbiddenFragments,
        lookupDuration: lookupDuration,
        outcome: outcome
      )
    }
  }

  private func completedSentence(
    for testCase: SentenceRewriteCorpusCase
  ) -> CompletedSentence {
    CompletedSentence(
      range: NSRange(
        location: 0,
        length: testCase.sentence.utf16.count
      ),
      text: testCase.sentence
    )
  }

  private func result(
    for testCase: SentenceRewriteCorpusCase,
    actualReplacement: String? = nil,
    failedProtectedFragments: [String] = [],
    presentForbiddenFragments: [String] = [],
    proposalRejectedBySafety: Bool = false,
    errorDescription: String? = nil,
    lookupDuration: Duration? = nil,
    outcome: SentenceRewriteEvaluationOutcome
  ) -> SentenceRewriteEvaluationResult {
    SentenceRewriteEvaluationResult(
      caseID: testCase.id,
      category: testCase.category,
      reviewStatus: testCase.reviewStatus,
      expectedRewrite: testCase.expectation != .unchanged,
      outcome: outcome,
      inputSentence: testCase.sentence,
      actualReplacement: actualReplacement,
      failedProtectedFragments: failedProtectedFragments,
      presentForbiddenFragments: presentForbiddenFragments,
      proposalRejectedBySafety: proposalRejectedBySafety,
      errorDescription: errorDescription,
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
