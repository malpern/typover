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

  @Test("Capitalization is preserved for capitalized and uppercase words")
  func preservesSupportedCapitalization() {
    #expect(
      makeProposal(original: "Teh", primary: "the")?.correction.replacement
        == "The"
    )
    #expect(
      makeProposal(original: "TEH", primary: "the")?.correction.replacement
        == "THE"
    )
  }

  @Test("Unicode accents are eligible word characters")
  func acceptsAccentedReplacement() {
    let proposal = makeProposal(original: "cafe", primary: "café")

    #expect(proposal?.correction.replacement == "café")
  }

  @Test("An internal apostrophe can be a one-edit correction")
  func acceptsInternalApostrophe() {
    let proposal = makeProposal(original: "dont", primary: "don't")

    #expect(proposal?.correction.replacement == "don't")
  }

  @Test("Multiple edits are not eligible")
  func rejectsMultipleEdits() {
    #expect(makeProposal(original: "cta", primary: "cats") == nil)
  }

  @Test("Mixed-case words and malformed apostrophes remain protected")
  func rejectsProtectedWordForms() {
    #expect(makeProposal(original: "iPone", primary: "iPhone") == nil)
    #expect(makeProposal(original: "'dont", primary: "don't") == nil)
    #expect(makeProposal(original: "dont'", primary: "don't") == nil)
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

  @Test("Alternatives use the original word's capitalization pattern")
  func normalizesAlternativeCapitalization() {
    let proposal = policy.proposal(
      original: "Teh",
      primary: "the",
      alternatives: ["ten", "TECH"],
      source: .appleSpelling,
      language: "en_US",
      lookupDuration: .zero
    )

    #expect(proposal?.alternatives == ["Ten", "Tech"])
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
