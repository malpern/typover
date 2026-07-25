import Testing

@testable import TypoverAppleSpell
@testable import TypoverCore
@testable import TypoverEvaluation

@MainActor
struct CorrectionCorpusEvaluatorTests {
  @Test("The evaluator classifies corrections and unchanged words")
  func classifiesOutcomes() {
    let corpus = CorrectionCorpus(
      schemaVersion: 1,
      baseline: CorrectionCorpusBaseline(
        platform: "test",
        defaultLanguage: "en_US",
        notes: ""
      ),
      cases: [
        correctionCase(id: "pass-correction", word: "teh", replacement: "the"),
        unchangedCase(id: "pass-unchanged", word: "cat"),
        unchangedCase(id: "false-positive", word: "Micah"),
        correctionCase(
          id: "missed-correction",
          word: "speling",
          replacement: "spelling"
        ),
        correctionCase(
          id: "wrong-correction",
          word: "adress",
          replacement: "address"
        ),
      ]
    )
    let engine = StubCorrectionEngine(
      proposals: [
        "teh": proposal(original: "teh", replacement: "the"),
        "Micah": proposal(original: "Micah", replacement: "Mica"),
        "adress": proposal(original: "adress", replacement: "adores"),
      ]
    )
    let evaluator = CorrectionCorpusEvaluator { _ in engine }

    let report = evaluator.evaluate(corpus)

    #expect(report.totalCount == 5)
    #expect(report.passedCount == 2)
    #expect(report.falsePositiveCount == 1)
    #expect(report.missedCorrectionCount == 1)
    #expect(report.wrongCorrectionCount == 1)
    #expect(report.approvedFailureCount == 3)
  }

  @Test("The bundled corpus has stable unique identifiers")
  func validatesBundledCorpus() throws {
    let corpus = try CorrectionCorpusLoader.loadBundled()
    let identifiers = Set(corpus.cases.map(\.id))

    #expect(corpus.schemaVersion == 1)
    #expect(corpus.cases.count == 131)
    #expect(identifiers.count == corpus.cases.count)
    #expect(
      corpus.cases.count { $0.reviewStatus == .approved } == 106
    )
    #expect(
      corpus.cases.contains {
        $0.reviewStatus == .provisional
      }
    )
  }

  private func correctionCase(
    id: String,
    word: String,
    replacement: String
  ) -> CorrectionCorpusCase {
    CorrectionCorpusCase(
      id: id,
      category: "test",
      word: word,
      reviewStatus: .approved,
      expectation: .correction(replacement)
    )
  }

  private func unchangedCase(
    id: String,
    word: String
  ) -> CorrectionCorpusCase {
    CorrectionCorpusCase(
      id: id,
      category: "test",
      word: word,
      reviewStatus: .approved,
      expectation: .unchanged
    )
  }

  private func proposal(
    original: String,
    replacement: String
  ) -> CorrectionProposal {
    CorrectionProposal(
      correction: Correction(
        original: original,
        replacement: replacement
      ),
      alternatives: [],
      source: .appleSpelling,
      language: "en_US",
      lookupDuration: .milliseconds(1)
    )
  }
}

@Suite(.serialized)
@MainActor
struct CorrectionCorpusAppleBaselineTests {
  @Test("Approved corpus cases match the Apple spelling baseline")
  func approvedCasesMatch() throws {
    let corpus = try CorrectionCorpusLoader.loadBundled()
    let evaluator = CorrectionCorpusEvaluator { language in
      AppleSpellCheckerEngine(language: language)
    }

    let report = evaluator.evaluate(corpus)
    let failedCaseIDs = report.failedResults
      .filter { $0.reviewStatus == .approved }
      .map(\.caseID)

    #expect(
      report.approvedFailureCount == 0,
      "Approved corpus mismatches: \(failedCaseIDs.formatted())"
    )
  }
}

@MainActor
private final class StubCorrectionEngine: CorrectionEngine {
  private let proposals: [String: CorrectionProposal]

  init(proposals: [String: CorrectionProposal]) {
    self.proposals = proposals
  }

  func proposal(for word: String) -> CorrectionProposal? {
    proposals[word]
  }
}
