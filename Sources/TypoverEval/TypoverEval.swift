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
    if CommandLine.arguments.contains("--rewrite") {
      try await runSentenceRewriteEvaluation(
        profile: try contextualPromptProfile()
      )
      return
    }

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

  private static func runSentenceRewriteEvaluation(
    profile: AppleContextualPromptProfile
  ) async throws {
    let corpus = try SentenceRewriteCorpusLoader.loadBundled()
    let evaluator = SentenceRewriteEvaluator(
      engine: AppleContextualCorrectionEngine(
        promptProfile: profile
      )
    )
    let resourceStart = ProcessResourceSnapshot.current()
    let report = await evaluator.evaluate(corpus)
    let operatingCost = resourceStart.flatMap { start in
      ProcessResourceSnapshot.current().map {
        start.cost(to: $0)
      }
    }

    if CommandLine.arguments.contains("--json") {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(
        SentenceRewriteBenchmarkOutput(
          promptProfile: profile.rawValue,
          report: report,
          operatingCost: operatingCost
        )
      )
      FileHandle.standardOutput.write(data)
      FileHandle.standardOutput.write(Data("\n".utf8))
    } else {
      print("Prompt profile: \(profile.rawValue)")
      printSentenceRewriteReport(
        report,
        operatingCost: operatingCost
      )
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

  private static func printSentenceRewriteReport(
    _ report: SentenceRewriteEvaluationReport,
    operatingCost: ProcessOperatingCost?
  ) {
    print("Typover sentence-rewrite corpus v\(report.schemaVersion)")
    print("Apple on-device model: \(report.availability)")
    print(
      "Cases: \(report.totalCount), "
        + "\(report.passedUnchangedCount) unchanged controls passed, "
        + "\(report.candidateRewriteCount) candidate rewrites, "
        + "\(report.falsePositiveCount) false positives"
    )
    print(
      "Rewrite misses: \(report.missedRewriteCount), "
        + "returned edits: \(report.returnedEditsCount), "
        + "preservation failures: \(report.preservationFailureCount), "
        + "safety rejections: \(report.rejectedProposalCount), "
        + "errors: \(report.errorCount)"
    )
    print(
      "Rates: "
        + "\(formatPercentage(report.unwarrantedRewriteRate)) unwarranted, "
        + "\(formatPercentage(report.rewriteCandidateRate)) rewrite candidate"
    )
    print(
      "Latency: first \(format(report.firstLookupMilliseconds)) ms, "
        + "warm median \(format(report.warmMedianLookupMilliseconds)) ms, "
        + "p95 \(format(report.p95LookupMilliseconds)) ms"
    )

    if let operatingCost {
      print(
        "Process cost: "
          + "\(format(operatingCost.userCPUMilliseconds)) ms user CPU, "
          + "\(format(operatingCost.systemCPUMilliseconds)) ms system CPU, "
          + "\(format(operatingCost.energyMillijoules)) mJ attributed energy"
      )
      print(
        "Memory: \(format(operatingCost.physicalFootprintMegabytes)) MB footprint, "
          + "\(format(operatingCost.peakPhysicalFootprintMegabytes)) MB peak, "
          + "\(format(operatingCost.neuralFootprintMegabytes)) MB neural footprint"
      )
      print(
        "Wakeups: \(operatingCost.interruptWakeups) interrupt, "
          + "\(operatingCost.packageIdleWakeups) package-idle"
      )
    }

    let candidates = report.results.filter {
      $0.outcome == .candidateRewrite
    }
    if !candidates.isEmpty {
      print("\nCandidate rewrites requiring human review:")
      for result in candidates {
        print("- \(result.caseID)")
        print("  Original: \(result.inputSentence)")
        print("  Rewrite:  \(result.actualReplacement ?? "")")
      }
    }

    let failures = report.results.filter {
      ![.passed, .candidateRewrite].contains($0.outcome)
    }
    if !failures.isEmpty {
      print("\nOther outcomes:")
      for result in failures {
        print("- \(result.caseID): \(result.outcome.rawValue)")
        if let replacement = result.actualReplacement {
          print("  Proposed: \(replacement)")
        }
        if !result.failedProtectedFragments.isEmpty {
          print(
            "  Lost: \(result.failedProtectedFragments.joined(separator: ", "))"
          )
        }
        if !result.presentForbiddenFragments.isEmpty {
          print(
            "  Forbidden: \(result.presentForbiddenFragments.joined(separator: ", "))"
          )
        }
        if let errorDescription = result.errorDescription {
          print("  Error: \(errorDescription)")
        }
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

private struct SentenceRewriteBenchmarkOutput: Codable {
  let promptProfile: String
  let report: SentenceRewriteEvaluationReport
  let operatingCost: ProcessOperatingCost?
}

private struct ProcessOperatingCost: Codable {
  let userCPUMilliseconds: Double
  let systemCPUMilliseconds: Double
  let energyMillijoules: Double
  let physicalFootprintMegabytes: Double
  let peakPhysicalFootprintMegabytes: Double
  let neuralFootprintMegabytes: Double
  let interruptWakeups: UInt64
  let packageIdleWakeups: UInt64
}

private struct ProcessResourceSnapshot {
  let userTimeNanoseconds: UInt64
  let systemTimeNanoseconds: UInt64
  let energyNanojoules: UInt64
  let physicalFootprintBytes: UInt64
  let peakPhysicalFootprintBytes: UInt64
  let neuralFootprintBytes: UInt64
  let interruptWakeups: UInt64
  let packageIdleWakeups: UInt64

  static func current() -> ProcessResourceSnapshot? {
    var info = rusage_info_v6()
    let status = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(
        to: rusage_info_t?.self,
        capacity: 1
      ) {
        proc_pid_rusage(getpid(), RUSAGE_INFO_V6, $0)
      }
    }
    guard status == 0 else { return nil }

    return ProcessResourceSnapshot(
      userTimeNanoseconds: info.ri_user_time,
      systemTimeNanoseconds: info.ri_system_time,
      energyNanojoules: info.ri_energy_nj,
      physicalFootprintBytes: info.ri_phys_footprint,
      peakPhysicalFootprintBytes: info.ri_lifetime_max_phys_footprint,
      neuralFootprintBytes: info.ri_neural_footprint,
      interruptWakeups: info.ri_interrupt_wkups,
      packageIdleWakeups: info.ri_pkg_idle_wkups
    )
  }

  func cost(to end: ProcessResourceSnapshot) -> ProcessOperatingCost {
    ProcessOperatingCost(
      userCPUMilliseconds: Double(
        delta(userTimeNanoseconds, end.userTimeNanoseconds)
      ) / 1_000_000,
      systemCPUMilliseconds: Double(
        delta(systemTimeNanoseconds, end.systemTimeNanoseconds)
      ) / 1_000_000,
      energyMillijoules: Double(
        delta(energyNanojoules, end.energyNanojoules)
      ) / 1_000_000,
      physicalFootprintMegabytes: megabytes(
        end.physicalFootprintBytes
      ),
      peakPhysicalFootprintMegabytes: megabytes(
        end.peakPhysicalFootprintBytes
      ),
      neuralFootprintMegabytes: megabytes(
        end.neuralFootprintBytes
      ),
      interruptWakeups: delta(
        interruptWakeups,
        end.interruptWakeups
      ),
      packageIdleWakeups: delta(
        packageIdleWakeups,
        end.packageIdleWakeups
      )
    )
  }

  private func delta(_ start: UInt64, _ end: UInt64) -> UInt64 {
    end >= start ? end - start : 0
  }

  private func megabytes(_ bytes: UInt64) -> Double {
    Double(bytes) / 1_048_576
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
