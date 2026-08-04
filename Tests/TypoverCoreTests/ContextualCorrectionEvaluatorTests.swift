import Foundation
import Testing
import TypoverCore
import TypoverEvaluation

struct ContextualCorrectionEvaluatorTests {
  @Test("The bundled contextual corpus is reviewed and balanced")
  func loadsBundledCorpus() throws {
    let corpus = try ContextualCorrectionCorpusLoader.loadBundled()

    #expect(corpus.schemaVersion == 1)
    #expect(corpus.cases.count == 48)
    #expect(
      corpus.cases.allSatisfy {
        $0.reviewStatus == .approved
      }
    )
    #expect(
      corpus.cases.count(where: {
        $0.expectation == .unchanged
      }) == 24
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

  @Test("The evaluator counts every applied comprehensive edit")
  func classifiesMultipleAppliedEdits() async {
    let corpus = ContextualCorrectionCorpus(
      schemaVersion: 1,
      cases: [
        testCase(
          id: "extra-edit",
          sentence: "This sentence are bad.",
          expectation: .correction(
            original: "are",
            replacement: "is"
          )
        ),
        testCase(
          id: "multi-false-positive",
          sentence: "This sentence is fine.",
          expectation: .unchanged
        ),
      ]
    )
    let engine = EvaluatorStubEngine(
      results: [
        "This sentence are bad.": ContextualCorrectionResult(
          candidates: [
            comprehensiveCandidate(original: "are", replacement: "is"),
            comprehensiveCandidate(original: "bad", replacement: "poor"),
          ]
        ),
        "This sentence is fine.": ContextualCorrectionResult(
          candidates: [
            comprehensiveCandidate(original: "fine", replacement: "good")
          ]
        ),
      ]
    )

    let report = await ContextualCorrectionEvaluator(
      engine: engine,
      scope: .comprehensive
    ).evaluate(corpus)

    #expect(report.passedCount == 0)
    #expect(report.falsePositiveCount == 1)
    #expect(report.wrongCorrectionCount == 1)
  }

  private func comprehensiveCandidate(
    original: String,
    replacement: String
  ) -> ContextualCorrectionCandidate {
    ContextualCorrectionCandidate(
      original: original,
      replacement: replacement,
      kind: .comprehensiveEdit
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
  let results: [String: ContextualCorrectionResult]

  init(candidates: [String: ContextualCorrectionCandidate]) {
    self.results = candidates.mapValues {
      ContextualCorrectionResult(candidates: [$0])
    }
  }

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
