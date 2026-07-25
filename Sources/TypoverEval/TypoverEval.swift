import Darwin
import Foundation
import TypoverAppleSpell
import TypoverEvaluation

@main
struct TypoverEvalCommand {
  @MainActor
  static func main() throws {
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

  private static func format(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(2)))
  }

  private static func formatPercentage(_ value: Double) -> String {
    value.formatted(.percent.precision(.fractionLength(2)))
  }
}
