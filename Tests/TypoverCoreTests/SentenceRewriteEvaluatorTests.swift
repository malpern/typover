import Foundation
import Testing
import TypoverCore
import TypoverEvaluation

struct SentenceRewriteEvaluatorTests {
  @Test("The rewrite corpus is reviewed, bounded, unique, and safety-weighted")
  func loadsBundledCorpus() throws {
    let corpus = try SentenceRewriteCorpusLoader.loadBundled()
    let ids = Set(corpus.cases.map(\.id))
    let rewriteCount = corpus.cases.count { testCase in
      if case .rewrite = testCase.expectation { return true }
      return false
    }
    let unchangedCount = corpus.cases.count { testCase in
      testCase.expectation == .unchanged
    }

    #expect(corpus.schemaVersion == 1)
    #expect(corpus.cases.count == 35)
    #expect(ids.count == corpus.cases.count)
    #expect(rewriteCount == 16)
    #expect(unchangedCount == 19)
    #expect(
      corpus.cases.allSatisfy {
        $0.reviewStatus == .approved
          && $0.sentence.utf16.count <= 400
          && $0.sentence.last.map { ".!?…”".contains($0) } == true
      }
    )
  }

  @Test("The evaluator separates safety failures from review candidates")
  func classifiesOutcomes() async {
    let candidateSentence = "The report was long in length."
    let preservationSentence = "Maya waited for a brief period in duration."
    let unchangedSentence = "Please be advised that the report is ready."
    let editSentence = "We made a decision to wait."
    let unsafeSentence = "The note was brief in length."
    let missedSentence = "At this point in time, we are ready."
    let corpus = SentenceRewriteCorpus(
      schemaVersion: 1,
      cases: [
        testCase(
          id: "candidate",
          sentence: candidateSentence,
          expectation: .rewrite(
            protectedFragments: ["report"],
            forbiddenFragments: []
          )
        ),
        testCase(
          id: "preservation",
          sentence: preservationSentence,
          expectation: .rewrite(
            protectedFragments: ["Maya"],
            forbiddenFragments: []
          )
        ),
        testCase(
          id: "false-positive",
          sentence: unchangedSentence,
          expectation: .unchanged
        ),
        testCase(
          id: "returned-edit",
          sentence: editSentence,
          expectation: .rewrite(
            protectedFragments: [],
            forbiddenFragments: []
          )
        ),
        testCase(
          id: "unsafe",
          sentence: unsafeSentence,
          expectation: .rewrite(
            protectedFragments: [],
            forbiddenFragments: []
          )
        ),
        testCase(
          id: "missed",
          sentence: missedSentence,
          expectation: .rewrite(
            protectedFragments: [],
            forbiddenFragments: []
          )
        ),
      ]
    )
    let engine = RewriteStubEngine(
      results: [
        candidateSentence: rewrite(
          original: candidateSentence,
          replacement: "The report was long."
        ),
        preservationSentence: rewrite(
          original: preservationSentence,
          replacement: "She waited briefly."
        ),
        unchangedSentence: rewrite(
          original: unchangedSentence,
          replacement: "Please note that the report is ready."
        ),
        editSentence: ContextualCorrectionResult(
          candidates: [
            ContextualCorrectionCandidate(
              original: "made a decision to wait",
              replacement: "decided to wait",
              kind: .comprehensiveEdit
            )
          ]
        ),
        unsafeSentence: rewrite(
          original: unsafeSentence,
          replacement: "The note was brief"
        ),
      ]
    )

    let report = await SentenceRewriteEvaluator(
      engine: engine
    ).evaluate(corpus)

    #expect(report.candidateRewriteCount == 1)
    #expect(report.preservationFailureCount == 1)
    #expect(report.falsePositiveCount == 1)
    #expect(report.returnedEditsCount == 1)
    #expect(report.unsafeProposalCount == 0)
    #expect(report.rejectedProposalCount == 1)
    #expect(report.missedRewriteCount == 2)
    #expect(report.unwarrantedRewriteRate == 1)
    #expect(report.rewriteCandidateRate == 0.2)
  }

  @Test("The comparison scores one proposal before and after Typover safety")
  func comparesModelOnlyAndFilteredOutcomes() async {
    let sentence = "Please be advised that the report is ready."
    let corpus = SentenceRewriteCorpus(
      schemaVersion: 1,
      cases: [
        testCase(
          id: "polite-control",
          sentence: sentence,
          expectation: .unchanged
        )
      ]
    )
    let engine = RewriteStubEngine(
      results: [
        sentence: rewrite(
          original: sentence,
          replacement: "The report is ready."
        )
      ]
    )

    let comparison = await SentenceRewriteEvaluator(
      engine: engine
    ).evaluateSafetyComparison(corpus)

    #expect(comparison.modelOnly.falsePositiveCount == 1)
    #expect(comparison.modelOnly.rejectedProposalCount == 0)
    #expect(comparison.typoverFiltered.passedUnchangedCount == 1)
    #expect(comparison.typoverFiltered.falsePositiveCount == 0)
    #expect(comparison.typoverFiltered.rejectedProposalCount == 1)
  }

  private func testCase(
    id: String,
    sentence: String,
    expectation: SentenceRewriteExpectation
  ) -> SentenceRewriteCorpusCase {
    SentenceRewriteCorpusCase(
      id: id,
      category: "test",
      sentence: sentence,
      language: "en_US",
      reviewStatus: .approved,
      expectation: expectation
    )
  }

  private func rewrite(
    original: String,
    replacement: String
  ) -> ContextualCorrectionResult {
    ContextualCorrectionResult(
      candidates: [
        ContextualCorrectionCandidate(
          original: original,
          replacement: replacement,
          kind: .sentenceRewrite
        )
      ]
    )
  }
}

private actor RewriteStubEngine: ContextualCorrectionEngine {
  let results: [String: ContextualCorrectionResult]

  init(results: [String: ContextualCorrectionResult]) {
    self.results = results
  }

  func availability(
    for _: String?
  ) -> ContextualCorrectionAvailability {
    .available
  }

  func proposal(
    for request: ContextualCorrectionRequest
  ) -> ContextualCorrectionResult? {
    results[request.sentence]
  }
}
