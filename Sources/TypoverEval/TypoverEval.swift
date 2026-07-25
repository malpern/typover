import Darwin
import Foundation
import TypoverAppleIntelligence
import TypoverAppleSpell
import TypoverCore
import TypoverEvaluation

@main
struct TypoverEvalCommand {
  @MainActor
  static func main() async throws {
    if CommandLine.arguments.contains("--contextual") {
      if CommandLine.arguments.contains("--all-prompt-profiles") {
        for profile in AppleContextualPromptProfile.allCases {
          try await runContextualEvaluation(profile: profile)
        }
      } else {
        try await runContextualEvaluation(
          profile: try contextualPromptProfile()
        )
      }
      return
    }

    let corpus = try CorrectionCorpusLoader.loadBundled()
    let evaluator = CorrectionCorpusEvaluator { language in
      AppleSpellCheckerEngine(language: language)
    }
    let report = evaluator.evaluate(corpus)

    if CommandLine.arguments.contains("--json") {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(report)
      FileHandle.standardOutput.write(data)
      FileHandle.standardOutput.write(Data("\n".utf8))
    } else {
      printHumanReport(report)
    }

    if report.approvedFailureCount > 0 {
      exit(EXIT_FAILURE)
    }
  }

  private static func runContextualEvaluation(
    profile: AppleContextualPromptProfile
  ) async throws {
    let scope = try contextualScope()
    let allowsSentenceRewrite =
      scope == .comprehensive
      && CommandLine.arguments.contains("--allow-sentence-rewrites")
    let corpus = try ContextualCorrectionCorpusLoader.loadBundled()
    let evaluator = ContextualCorrectionEvaluator(
      engine: AppleContextualCorrectionEngine(
        promptProfile: profile
      ),
      scope: scope,
      allowsSentenceRewrite: allowsSentenceRewrite
    )
    let report = await evaluator.evaluate(corpus)

    if CommandLine.arguments.contains("--json") {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(report)
      FileHandle.standardOutput.write(data)
      FileHandle.standardOutput.write(Data("\n".utf8))
    } else {
      print("Prompt profile: \(profile.rawValue)")
      print("Correction scope: \(scope.rawValue)")
      print(
        "Sentence rewrites: "
          + (allowsSentenceRewrite ? "allowed" : "disabled")
      )
      printContextualReport(report)
    }
  }

  private static func contextualScope()
    throws -> ContextualCorrectionScope
  {
    let arguments = CommandLine.arguments
    if let index = arguments.firstIndex(of: "--scope") {
      guard arguments.indices.contains(index + 1) else {
        throw TypoverEvalError.missingCorrectionScope
      }
      guard
        let scope = ContextualCorrectionScope(
          rawValue: arguments[index + 1]
        )
      else {
        throw TypoverEvalError.unknownCorrectionScope(
          arguments[index + 1]
        )
      }
      return scope
    }

    if let argument = arguments.first(where: {
      $0.hasPrefix("--scope=")
    }) {
      let rawValue = String(argument.dropFirst("--scope=".count))
      guard
        let scope = ContextualCorrectionScope(rawValue: rawValue)
      else {
        throw TypoverEvalError.unknownCorrectionScope(rawValue)
      }
      return scope
    }

    return .careful
  }

  private static func contextualPromptProfile()
    throws -> AppleContextualPromptProfile
  {
    let arguments = CommandLine.arguments
    if let index = arguments.firstIndex(of: "--prompt-profile") {
      guard arguments.indices.contains(index + 1) else {
        throw TypoverEvalError.missingPromptProfile
      }
      guard
        let profile = AppleContextualPromptProfile(
          rawValue: arguments[index + 1]
        )
      else {
        throw TypoverEvalError.unknownPromptProfile(
          arguments[index + 1]
        )
      }
      return profile
    }

    if let argument = arguments.first(where: {
      $0.hasPrefix("--prompt-profile=")
    }) {
      let rawValue = String(
        argument.dropFirst("--prompt-profile=".count)
      )
      guard
        let profile = AppleContextualPromptProfile(rawValue: rawValue)
      else {
        throw TypoverEvalError.unknownPromptProfile(rawValue)
      }
      return profile
    }

    return .conservative
  }

  private static func printHumanReport(
    _ report: CorrectionEvaluationReport
  ) {
    print("Typover correction corpus v\(report.schemaVersion)")
    print("Baseline: \(report.platform)")
    print(
      "Cases: \(report.totalCount) "
        + "(\(report.approvedCaseCount) approved, "
        + "\(report.provisionalCaseCount) provisional)"
    )
    print(
      "Outcomes: \(report.passedCount) passed, "
        + "\(report.falsePositiveCount) false positives, "
        + "\(report.missedCorrectionCount) missed, "
        + "\(report.wrongCorrectionCount) wrong"
    )
    print(
      "Approved gate: "
        + "\(report.approvedCaseCount - report.approvedFailureCount)"
        + "/\(report.approvedCaseCount) passed"
    )
    print(
      "Overall rates: "
        + "\(formatPercentage(report.falsePositiveRate)) false positive, "
        + "\(formatPercentage(report.missedCorrectionRate)) missed correction"
    )
    print(
      "Latency: median \(format(report.medianLookupMilliseconds)) ms, "
        + "p95 \(format(report.p95LookupMilliseconds)) ms"
    )

    if !report.failedResults.isEmpty {
      print("\nMismatches:")
      for result in report.failedResults {
        let expected = result.expectedReplacement ?? "unchanged"
        let actual = result.actualReplacement ?? "unchanged"
        print(
          "- [\(result.reviewStatus.rawValue)] \(result.caseID): "
            + "expected \(expected), got \(actual)"
        )
      }
    }
  }

  private static func printContextualReport(
    _ report: ContextualEvaluationReport
  ) {
    print("Typover contextual corpus v\(report.schemaVersion)")
    print("Apple on-device model: \(report.availability)")
    print(
      "Cases: \(report.totalCount), "
        + "\(report.passedCount) passed, "
        + "\(report.falsePositiveCount) false positives, "
        + "\(report.missedCorrectionCount) missed, "
        + "\(report.wrongCorrectionCount) wrong, "
        + "\(report.errorCount) errors"
    )
    print(
      "Latency: median \(format(report.medianLookupMilliseconds)) ms, "
        + "p95 \(format(report.p95LookupMilliseconds)) ms"
    )

    let mismatches = report.results.filter { $0.outcome != .passed }
    if !mismatches.isEmpty {
      print("\nMismatches:")
      for result in mismatches {
        let expected =
          result.expectedOriginal.map { original in
            "\(original) → \(result.expectedReplacement ?? "")"
          } ?? "unchanged"
        let actual =
          result.actualOriginal.map { original in
            "\(original) → \(result.actualReplacement ?? "")"
          } ?? result.outcome.rawValue
        print(
          "- \(result.caseID): expected \(expected), got \(actual)"
        )
      }
    }
  }

  private static func format(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(2)))
  }

  private static func formatPercentage(_ value: Double) -> String {
    value.formatted(.percent.precision(.fractionLength(2)))
  }
}

private enum TypoverEvalError: Error, CustomStringConvertible {
  case missingCorrectionScope
  case missingPromptProfile
  case unknownCorrectionScope(String)
  case unknownPromptProfile(String)

  var description: String {
    switch self {
    case .missingCorrectionScope:
      "Expected careful or comprehensive after --scope."
    case .missingPromptProfile:
      "Expected conservative or focused-grammar after --prompt-profile."
    case .unknownCorrectionScope(let scope):
      "Unknown correction scope “\(scope)”; use careful or comprehensive."
    case .unknownPromptProfile(let profile):
      "Unknown prompt profile “\(profile)”; use conservative or focused-grammar."
    }
  }
}
