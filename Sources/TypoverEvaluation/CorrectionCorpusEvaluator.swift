import Foundation
import TypoverCore

public enum CorrectionEvaluationOutcome: String, Codable, Sendable {
  case passed
  case falsePositive = "false_positive"
  case missedCorrection = "missed_correction"
  case wrongCorrection = "wrong_correction"
}

public struct CorrectionEvaluationCaseResult: Codable, Sendable {
  public let caseID: String
  public let category: String
  public let reviewStatus: CorrectionCorpusReviewStatus
  public let expectedReplacement: String?
  public let actualReplacement: String?
  public let alternatives: [String]
  public let source: String?
  public let language: String
  public let engineLookupMilliseconds: Double?
  public let totalLookupMilliseconds: Double
  public let outcome: CorrectionEvaluationOutcome

  public var passed: Bool {
    outcome == .passed
  }
}

public struct CorrectionEvaluationReport: Codable, Sendable {
  public let schemaVersion: Int
  public let platform: String
  public let results: [CorrectionEvaluationCaseResult]
  public let totalCount: Int
  public let passedCount: Int
  public let failureCount: Int
  public let falsePositiveCount: Int
  public let missedCorrectionCount: Int
  public let wrongCorrectionCount: Int
  public let approvedCaseCount: Int
  public let approvedFailureCount: Int
  public let provisionalCaseCount: Int
  public let provisionalFailureCount: Int
  public let falsePositiveRate: Double
  public let missedCorrectionRate: Double
  public let medianLookupMilliseconds: Double
  public let p95LookupMilliseconds: Double

  public var failedResults: [CorrectionEvaluationCaseResult] {
    results.filter { !$0.passed }
  }
}

@MainActor
public struct CorrectionCorpusEvaluator {
  public typealias EngineFactory = @MainActor (String) -> any CorrectionEngine

  private let engineFactory: EngineFactory

  public init(engineFactory: @escaping EngineFactory) {
    self.engineFactory = engineFactory
  }

  public func evaluate(_ corpus: CorrectionCorpus) -> CorrectionEvaluationReport {
    var engines: [String: any CorrectionEngine] = [:]
    var results: [CorrectionEvaluationCaseResult] = []
    let clock = ContinuousClock()

    for corpusCase in corpus.cases {
      let language = corpusCase.language ?? corpus.baseline.defaultLanguage
      let engine: any CorrectionEngine
      if let existingEngine = engines[language] {
        engine = existingEngine
      } else {
        let newEngine = engineFactory(language)
        engines[language] = newEngine
        engine = newEngine
      }

      let start = clock.now
      let proposal = engine.proposal(for: corpusCase.word)
      let totalDuration = start.duration(to: clock.now)

      results.append(
        result(
          for: corpusCase,
          language: language,
          proposal: proposal,
          totalDuration: totalDuration
        )
      )
    }

    let lookupTimes = results.map(\.totalLookupMilliseconds).sorted()
    let totalCount = results.count
    let passedCount = results.count(where: \.passed)
    let falsePositiveCount = results.count {
      $0.outcome == .falsePositive
    }
    let missedCorrectionCount = results.count {
      $0.outcome == .missedCorrection
    }
    let expectedUnchangedCount = results.count {
      $0.expectedReplacement == nil
    }
    let expectedCorrectionCount = totalCount - expectedUnchangedCount

    return CorrectionEvaluationReport(
      schemaVersion: corpus.schemaVersion,
      platform: corpus.baseline.platform,
      results: results,
      totalCount: totalCount,
      passedCount: passedCount,
      failureCount: totalCount - passedCount,
      falsePositiveCount: falsePositiveCount,
      missedCorrectionCount: missedCorrectionCount,
      wrongCorrectionCount: results.count {
        $0.outcome == .wrongCorrection
      },
      approvedCaseCount: results.count {
        $0.reviewStatus == .approved
      },
      approvedFailureCount: results.count {
        $0.reviewStatus == .approved && !$0.passed
      },
      provisionalCaseCount: results.count {
        $0.reviewStatus == .provisional
      },
      provisionalFailureCount: results.count {
        $0.reviewStatus == .provisional && !$0.passed
      },
      falsePositiveRate: rate(
        count: falsePositiveCount,
        total: expectedUnchangedCount
      ),
      missedCorrectionRate: rate(
        count: missedCorrectionCount,
        total: expectedCorrectionCount
      ),
      medianLookupMilliseconds: median(of: lookupTimes),
      p95LookupMilliseconds: percentile(0.95, of: lookupTimes)
    )
  }

  private func result(
    for corpusCase: CorrectionCorpusCase,
    language: String,
    proposal: CorrectionProposal?,
    totalDuration: Duration
  ) -> CorrectionEvaluationCaseResult {
    let expectedReplacement: String?
    let outcome: CorrectionEvaluationOutcome

    switch (corpusCase.expectation, proposal?.correction.replacement) {
    case (.unchanged, nil):
      expectedReplacement = nil
      outcome = .passed
    case (.unchanged, .some):
      expectedReplacement = nil
      outcome = .falsePositive
    case let (.correction(expected), .some(actual)) where expected == actual:
      expectedReplacement = expected
      outcome = .passed
    case let (.correction(expected), nil):
      expectedReplacement = expected
      outcome = .missedCorrection
    case let (.correction(expected), .some):
      expectedReplacement = expected
      outcome = .wrongCorrection
    }

    return CorrectionEvaluationCaseResult(
      caseID: corpusCase.id,
      category: corpusCase.category,
      reviewStatus: corpusCase.reviewStatus,
      expectedReplacement: expectedReplacement,
      actualReplacement: proposal?.correction.replacement,
      alternatives: proposal?.alternatives ?? [],
      source: proposal.map { sourceName($0.source) },
      language: proposal?.language ?? language,
      engineLookupMilliseconds: proposal?.lookupDuration.milliseconds,
      totalLookupMilliseconds: totalDuration.milliseconds,
      outcome: outcome
    )
  }

  private func sourceName(_ source: CorrectionSource) -> String {
    switch source {
    case .appleIntelligence:
      "apple-intelligence"
    case .appleIntelligenceRewrite:
      "apple-intelligence-rewrite"
    case .demo:
      "demo"
    case .appleSpelling:
      "apple_spelling"
    case .openAI:
      "openai"
    case .openAIRewrite:
      "openai_rewrite"
    case .anthropic:
      "anthropic"
    case .anthropicRewrite:
      "anthropic_rewrite"
    case .rememberedPreference:
      "remembered_preference"
    }
  }

  private func median(of sortedValues: [Double]) -> Double {
    guard !sortedValues.isEmpty else {
      return 0
    }

    let middle = sortedValues.count / 2
    if sortedValues.count.isMultiple(of: 2) {
      return (sortedValues[middle - 1] + sortedValues[middle]) / 2
    }
    return sortedValues[middle]
  }

  private func percentile(
    _ percentile: Double,
    of sortedValues: [Double]
  ) -> Double {
    guard !sortedValues.isEmpty else {
      return 0
    }

    let rank = Int(ceil(percentile * Double(sortedValues.count))) - 1
    return sortedValues[max(0, min(rank, sortedValues.count - 1))]
  }

  private func rate(
    count: Int,
    total: Int
  ) -> Double {
    guard total > 0 else {
      return 0
    }
    return Double(count) / Double(total)
  }
}

private extension Duration {
  var milliseconds: Double {
    let parts = components
    return Double(parts.seconds) * 1_000
      + Double(parts.attoseconds) / 1_000_000_000_000_000
  }
}
