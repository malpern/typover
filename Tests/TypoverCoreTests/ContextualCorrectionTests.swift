import Foundation
import Testing
import TypoverCore

struct ContextualCorrectionTests {
  @Test("Sentence rewriting requires comprehensive scope")
  func rewritePermissionRequiresComprehensiveScope() {
    let careful = ContextualCorrectionRequest(
      sentence: "This is a sentence.",
      scope: .careful,
      allowsSentenceRewrite: true
    )
    let comprehensive = ContextualCorrectionRequest(
      sentence: "This is a sentence.",
      scope: .comprehensive,
      allowsSentenceRewrite: true
    )

    #expect(!careful.allowsSentenceRewrite)
    #expect(comprehensive.allowsSentenceRewrite)
  }

  @Test("The detector returns only the bounded sentence at the caret")
  func detectsCompletedSentence() {
    let text = "Earlier sentence.  Their going home."
    let sentence = CompletedSentenceDetector.immediatelyBeforeCaret(
      in: text,
      caretUTF16Offset: text.utf16.count
    )

    #expect(sentence?.text == "Their going home.")
    #expect(
      sentence?.range
        == (text as NSString).range(of: "Their going home.")
    )
  }

  @Test("The detector requires sentence punctuation at the caret")
  func requiresSentenceBoundary() {
    #expect(
      CompletedSentenceDetector.immediatelyBeforeCaret(
        in: "Their going home ",
        caretUTF16Offset: "Their going home ".utf16.count
      ) == nil
    )
  }

  @Test("The detector refuses an oversized sentence")
  func refusesOversizedSentence() {
    let text =
      String(
        repeating: "word ",
        count: CompletedSentenceDetector.maximumUTF16Length
      ) + "."

    #expect(
      CompletedSentenceDetector.immediatelyBeforeCaret(
        in: text,
        caretUTF16Offset: text.utf16.count
      ) == nil
    )
  }

  @Test("A unique exact model target resolves to its document range")
  func resolvesUniqueExactTarget() throws {
    let sentence = CompletedSentence(
      range: NSRange(location: 100, length: 17),
      text: "Their going home."
    )
    let resolved = try #require(
      ContextualCorrectionResolver.resolve(
        ContextualCorrectionCandidate(
          original: "Their",
          replacement: "They're"
        ),
        in: sentence,
        language: "en_US"
      )
    )

    #expect(resolved.range == NSRange(location: 100, length: 5))
    #expect(resolved.proposal.correction.original == "Their")
    #expect(resolved.proposal.correction.replacement == "They're")
    #expect(resolved.proposal.source == .appleIntelligence)
  }

  @Test("An ambiguous model target is rejected")
  func rejectsAmbiguousTarget() {
    let sentence = CompletedSentence(
      range: NSRange(location: 0, length: 17),
      text: "there then there."
    )

    #expect(
      ContextualCorrectionResolver.resolve(
        ContextualCorrectionCandidate(
          original: "there",
          replacement: "their"
        ),
        in: sentence,
        language: "en_US"
      ) == nil
    )
  }

  @Test("A target absent from captured text is rejected")
  func rejectsInventedTarget() {
    let sentence = CompletedSentence(
      range: NSRange(location: 0, length: 17),
      text: "Their going home."
    )

    #expect(
      ContextualCorrectionResolver.resolve(
        ContextualCorrectionCandidate(
          original: "They are",
          replacement: "They're"
        ),
        in: sentence,
        language: "en_US"
      ) == nil
    )
  }

  @Test("A full-sentence correction reduces to one exact replacement")
  func reducesFullSentenceCorrection() {
    let difference = MinimalTextReplacement.difference(
      from: "We should of left earlier.",
      to: "We should have left earlier."
    )

    #expect(
      difference
        == MinimalTextReplacement(
          original: "of",
          replacement: "have"
        )
    )
  }

  @Test("Sentence differences expand partial changes to whole words")
  func expandsPartialDifferenceToWholeWords() {
    #expect(
      MinimalTextReplacement.difference(
        from: "I left the keys over they're.",
        to: "I left the keys over there."
      )
        == MinimalTextReplacement(
          original: "they're",
          replacement: "there"
        )
    )
    #expect(
      MinimalTextReplacement.difference(
        from: "Its going to rain.",
        to: "It's going to rain."
      )
        == MinimalTextReplacement(
          original: "Its",
          replacement: "It's"
        )
    )
    #expect(
      MinimalTextReplacement.difference(
        from: "She excepted the invitation.",
        to: "She accepted the invitation."
      )
        == MinimalTextReplacement(
          original: "excepted",
          replacement: "accepted"
        )
    )
  }

  @Test("A broad sentence target is rejected")
  func rejectsBroadSentenceTarget() {
    let sentence = CompletedSentence(
      range: NSRange(location: 0, length: 17),
      text: "Their going home."
    )

    #expect(
      ContextualCorrectionResolver.resolve(
        ContextualCorrectionCandidate(
          original: "Their going home.",
          replacement: "They're going home."
        ),
        in: sentence,
        language: "en_US"
      ) == nil
    )
  }

  @Test("An unrelated replacement is rejected even when its target is exact")
  func rejectsUnrelatedReplacement() {
    let sentence = CompletedSentence(
      range: NSRange(location: 0, length: 30),
      text: "Everyone is coming accept Mia."
    )

    #expect(
      ContextualCorrectionResolver.resolve(
        ContextualCorrectionCandidate(
          original: "accept",
          replacement: "to"
        ),
        in: sentence,
        language: "en_US"
      ) == nil
    )
  }

  @Test("The reviewed should-of repair remains eligible")
  func allowsReviewedPhraseRepair() {
    let sentence = CompletedSentence(
      range: NSRange(location: 0, length: 26),
      text: "We should of left earlier."
    )

    #expect(
      ContextualCorrectionResolver.resolve(
        ContextualCorrectionCandidate(
          original: "of",
          replacement: "have"
        ),
        in: sentence,
        language: "en_US"
      ) != nil
    )
  }

  @Test("Several nonoverlapping comprehensive edits resolve together")
  func resolvesSeveralComprehensiveEdits() throws {
    let sentence = CompletedSentence(
      range: NSRange(location: 20, length: 30),
      text: "Their going because its late."
    )
    let result = ContextualCorrectionResult(
      candidates: [
        ContextualCorrectionCandidate(
          original: "Their",
          replacement: "They're",
          kind: .comprehensiveEdit
        ),
        ContextualCorrectionCandidate(
          original: "its",
          replacement: "it's",
          kind: .comprehensiveEdit
        ),
      ]
    )

    let resolved = try #require(
      ContextualCorrectionResolver.resolve(
        result,
        in: sentence,
        language: "en_US"
      )
    )

    #expect(resolved.count == 2)
    #expect(resolved.map(\.range.location) == [20, 40])
  }

  @Test("Overlapping contextual edits reject the complete result")
  func rejectsOverlappingEdits() {
    let sentence = CompletedSentence(
      range: NSRange(location: 0, length: 25),
      text: "We should of left early."
    )
    let result = ContextualCorrectionResult(
      candidates: [
        ContextualCorrectionCandidate(
          original: "should of",
          replacement: "should have",
          kind: .comprehensiveEdit
        ),
        ContextualCorrectionCandidate(
          original: "of",
          replacement: "have",
          kind: .comprehensiveEdit
        ),
      ]
    )

    #expect(
      ContextualCorrectionResolver.resolve(
        result,
        in: sentence,
        language: "en_US"
      ) == nil
    )
  }

  @Test("An explicitly marked complete sentence rewrite resolves")
  func resolvesSentenceRewrite() throws {
    let original = "We go store now."
    let replacement = "We are going to the store now."
    let sentence = CompletedSentence(
      range: NSRange(location: 80, length: original.utf16.count),
      text: original
    )
    let result = ContextualCorrectionResult(
      candidates: [
        ContextualCorrectionCandidate(
          original: original,
          replacement: replacement,
          kind: .sentenceRewrite
        )
      ]
    )

    let resolved = try #require(
      ContextualCorrectionResolver.resolve(
        result,
        in: sentence,
        language: "en_US"
      )?.first
    )

    #expect(resolved.range == sentence.range)
    #expect(resolved.proposal.source == .appleIntelligenceRewrite)
    #expect(resolved.proposal.correction.original == original)
    #expect(resolved.proposal.correction.replacement == replacement)
  }

  @Test("A sentence rewrite must remain a complete punctuated sentence")
  func rejectsIncompleteSentenceRewrite() {
    let original = "We go store now."
    let sentence = CompletedSentence(
      range: NSRange(location: 0, length: original.utf16.count),
      text: original
    )

    #expect(
      ContextualCorrectionResolver.resolve(
        ContextualCorrectionResult(
          candidates: [
            ContextualCorrectionCandidate(
              original: original,
              replacement: "We are going to the store now",
              kind: .sentenceRewrite
            )
          ]
        ),
        in: sentence,
        language: "en_US"
      ) == nil
    )
  }

  @Test("A comprehensive edit cannot duplicate its neighboring word")
  func rejectsAdjacentDuplicate() {
    let sentence = CompletedSentence(
      range: NSRange(location: 0, length: 31),
      text: "Their going to arrive tomorrow."
    )

    #expect(
      ContextualCorrectionResolver.resolve(
        ContextualCorrectionCandidate(
          original: "going",
          replacement: "going to",
          kind: .comprehensiveEdit
        ),
        in: sentence,
        language: "en_US"
      ) == nil
    )
  }
}
