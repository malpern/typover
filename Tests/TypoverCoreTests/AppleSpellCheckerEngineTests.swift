import Foundation
import Testing

@testable import TypoverAppleSpell
@testable import TypoverCore

@MainActor
struct AppleSpellCheckerEngineTests {
  @Test("Apple spelling results become a local correction proposal")
  func createsProposal() {
    let checker = FakeAppleSpellingChecker(
      misspelledRange: NSRange(location: 0, length: 3),
      correction: "the",
      guesses: ["the", "ten"]
    )
    let engine = AppleSpellCheckerEngine(
      checker: checker,
      language: "en_US",
      policy: AutomaticCorrectionPolicy()
    )

    let proposal = engine.proposal(for: "teh")

    #expect(proposal?.correction.original == "teh")
    #expect(proposal?.correction.replacement == "the")
    #expect(proposal?.alternatives == ["ten"])
    #expect(proposal?.source == .appleSpelling)
    #expect(proposal?.language == "en_US")
  }

  @Test("A word Apple does not mark as misspelled is left alone")
  func leavesCorrectWordAlone() {
    let checker = FakeAppleSpellingChecker(
      misspelledRange: NSRange(location: NSNotFound, length: 0),
      correction: "the",
      guesses: []
    )
    let engine = AppleSpellCheckerEngine(
      checker: checker,
      language: "en_US",
      policy: AutomaticCorrectionPolicy()
    )

    #expect(engine.proposal(for: "the") == nil)
  }

  @Test("The first ranked guess is used when Apple has no automatic correction")
  func fallsBackToFirstGuess() {
    let checker = FakeAppleSpellingChecker(
      misspelledRange: NSRange(location: 0, length: 3),
      correction: nil,
      guesses: ["the", "ten"]
    )
    let engine = AppleSpellCheckerEngine(
      checker: checker,
      language: "en_US",
      policy: AutomaticCorrectionPolicy()
    )

    let proposal = engine.proposal(for: "teh")

    #expect(proposal?.correction.replacement == "the")
    #expect(proposal?.alternatives == ["ten"])
  }

  @Test("User responses are returned to the Apple spelling system")
  func recordsResponse() throws {
    let checker = FakeAppleSpellingChecker(
      misspelledRange: NSRange(location: 0, length: 3),
      correction: "the",
      guesses: []
    )
    let engine = AppleSpellCheckerEngine(
      checker: checker,
      language: "en_US",
      policy: AutomaticCorrectionPolicy()
    )
    let proposal = try #require(engine.proposal(for: "teh"))

    engine.record(.reverted, for: proposal)

    #expect(checker.responses == [.reverted])
  }
}

@MainActor
private final class FakeAppleSpellingChecker: AppleSpellingChecking {
  let misspelledRangeResult: NSRange
  let correctionResult: String?
  let guessesResult: [String]
  var responses: [CorrectionUserResponse] = []

  init(
    misspelledRange: NSRange,
    correction: String?,
    guesses: [String]
  ) {
    self.misspelledRangeResult = misspelledRange
    self.correctionResult = correction
    self.guessesResult = guesses
  }

  func uniqueDocumentTag() -> Int {
    42
  }

  func closeDocument(withTag tag: Int) {}

  func misspelledRange(
    in word: String,
    language: String,
    documentTag: Int
  ) -> NSRange {
    misspelledRangeResult
  }

  func correction(
    for range: NSRange,
    in word: String,
    language: String,
    documentTag: Int
  ) -> String? {
    correctionResult
  }

  func guesses(
    for range: NSRange,
    in word: String,
    language: String,
    documentTag: Int
  ) -> [String] {
    guessesResult
  }

  func record(
    _ response: CorrectionUserResponse,
    correction: String,
    original: String,
    language: String,
    documentTag: Int
  ) {
    responses.append(response)
  }
}
