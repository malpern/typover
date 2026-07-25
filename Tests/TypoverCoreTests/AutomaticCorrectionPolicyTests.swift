import Foundation
import Testing

@testable import TypoverCore

struct AutomaticCorrectionPolicyTests {
  private let policy = AutomaticCorrectionPolicy()

  @Test("A single adjacent transposition is eligible")
  func acceptsAdjacentTransposition() {
    let proposal = makeProposal(original: "teh", primary: "the")

    #expect(proposal?.correction.replacement == "the")
  }

  @Test("A single insertion is eligible")
  func acceptsSingleInsertion() {
    let proposal = makeProposal(original: "speling", primary: "spelling")

    #expect(proposal?.correction.replacement == "spelling")
  }

  @Test("Multiple edits are not eligible")
  func rejectsMultipleEdits() {
    #expect(makeProposal(original: "cta", primary: "cats") == nil)
  }

  @Test("The initial policy is deliberately limited to lowercase ASCII words")
  func rejectsWordsOutsideInitialScope() {
    #expect(makeProposal(original: "Teh", primary: "The") == nil)
    #expect(makeProposal(original: "cafe", primary: "café") == nil)
    #expect(makeProposal(original: "a", primary: "I") == nil)
  }

  @Test("Alternatives are normalized, deduplicated, and bounded")
  func filtersAlternatives() {
    let policy = AutomaticCorrectionPolicy(maximumAlternatives: 2)
    let proposal = policy.proposal(
      original: "teh",
      primary: "the",
      alternatives: ["the", "ten", "ten", "tech", "Teh"],
      source: .appleSpelling,
      language: "en_US",
      lookupDuration: .zero
    )

    #expect(proposal?.alternatives == ["ten", "tech"])
  }

  @Test("The edit-distance helper handles insertion, substitution, and transposition")
  func calculatesEditDistance() {
    #expect(policy.optimalStringAlignmentDistance(from: "teh", to: "the") == 1)
    #expect(policy.optimalStringAlignmentDistance(from: "cat", to: "cut") == 1)
    #expect(policy.optimalStringAlignmentDistance(from: "cat", to: "cats") == 1)
    #expect(policy.optimalStringAlignmentDistance(from: "cat", to: "dog") == 3)
  }

  private func makeProposal(
    original: String,
    primary: String
  ) -> CorrectionProposal? {
    policy.proposal(
      original: original,
      primary: primary,
      alternatives: [],
      source: .appleSpelling,
      language: "en_US",
      lookupDuration: .zero
    )
  }
}
