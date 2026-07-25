import Foundation
import Testing
import TypoverCore
import TypoverEvaluation

struct ContextualCorrectionEvaluatorTests {
  @Test("The bundled contextual corpus is reviewed and balanced")
  func loadsBundledCorpus() throws {
    let corpus = try ContextualCorrectionCorpusLoader.loadBundled()

    #expect(corpus.schemaVersion == 1)
    #expect(corpus.cases.count == 16)
    #expect(
      corpus.cases.allSatisfy {
        $0.reviewStatus == .approved
      }
    )
    #expect(
      corpus.cases.count(where: {
        $0.expectation == .unchanged
      }) == 8
    )
  }

  @Test("The evaluator classifies contextual outcomes")
  func classifiesOutcomes() async {
    let corpus = ContextualCorrectionCorpus(
      schemaVersion: 1,
      cases: [
        testCase(
          id: "correct",
          sentence: "Their going.",
          expectation: .correction(
            original: "Their",
            replacement: "They're"
          )
        ),
        testCase(
          id: "unchanged",
          sentence: "Their project.",
          expectation: .unchanged
        ),
        testCase(
          id: "false-positive",
          sentence: "There it is.",
          expectation: .unchanged
        ),
        testCase(
          id: "missed",
          sentence: "I can here it.",
          expectation: .correction(
            original: "here",
            replacement: "hear"
          )
        ),
      ]
    )
    let engine = EvaluatorStubEngine(
      candidates: [
        "Their going.": ContextualCorrectionCandidate(
          original: "Their",
          replacement: "They're",
          lookupDuration: .milliseconds(10)
        ),
        "There it is.": ContextualCorrectionCandidate(
          original: "There",
          replacement: "Their",
          lookupDuration: .milliseconds(20)
        ),
      ]
    )

    let report = await ContextualCorrectionEvaluator(
      engine: engine
    ).evaluate(corpus)

    #expect(report.passedCount == 2)
    #expect(report.falsePositiveCount == 1)
    #expect(report.missedCorrectionCount == 1)
    #expect(report.wrongCorrectionCount == 0)
    #expect(report.errorCount == 0)
    #expect(report.medianLookupMilliseconds >= 0)
    #expect(
      report.p95LookupMilliseconds
        >= report.medianLookupMilliseconds
    )
  }

  private func testCase(
    id: String,
    sentence: String,
    expectation: ContextualCorrectionExpectation
  ) -> ContextualCorrectionCorpusCase {
    ContextualCorrectionCorpusCase(
      id: id,
      category: "test",
      sentence: sentence,
      language: "en_US",
      reviewStatus: .approved,
      expectation: expectation
    )
  }
}

private actor EvaluatorStubEngine: ContextualCorrectionEngine {
  let candidates: [String: ContextualCorrectionCandidate]

  init(candidates: [String: ContextualCorrectionCandidate]) {
    self.candidates = candidates
  }

  func availability(
    for _: String?
  ) -> ContextualCorrectionAvailability {
    .available
  }

  func proposal(
    for request: ContextualCorrectionRequest
  ) -> ContextualCorrectionCandidate? {
    candidates[request.sentence]
  }
}
