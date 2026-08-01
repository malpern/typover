import Foundation
import Testing

@testable import TypoverCore

struct CompletedWordDetectorTests {
  @Test("The completed word is resolved relative to an earlier caret")
  func resolvesWordBeforeEarlierCaret() throws {
    let text = "Start of document. teh untouched text after the caret."
    let completedRange = (text as NSString).range(of: "teh ")
    let caret = NSMaxRange(completedRange)

    let completedWord = try #require(
      CompletedWordDetector.immediatelyBeforeCaret(
        in: text,
        caretUTF16Offset: caret
      )
    )

    #expect(completedWord.text == "teh")
    #expect(completedWord.range == (text as NSString).range(of: "teh"))
  }

  @Test("Sentence punctuation completes a word")
  func detectsPunctuationBoundary() {
    let text = "Finish teh,"

    let completedWord = CompletedWordDetector.immediatelyBeforeCaret(
      in: text,
      caretUTF16Offset: (text as NSString).length
    )

    #expect(completedWord?.text == "teh")
  }

  @Test("Unicode letters and composed accents remain in the word")
  func detectsAccentedWord() {
    let text = "A café "

    let completedWord = CompletedWordDetector.immediatelyBeforeCaret(
      in: text,
      caretUTF16Offset: (text as NSString).length
    )

    #expect(completedWord?.text == "café")
  }

  @Test("Internal straight and curly apostrophes remain in the word")
  func detectsApostrophes() {
    let straight = "don't "
    let curly = "don’t "

    #expect(
      CompletedWordDetector.immediatelyBeforeCaret(
        in: straight,
        caretUTF16Offset: (straight as NSString).length
      )?.text == "don't"
    )
    #expect(
      CompletedWordDetector.immediatelyBeforeCaret(
        in: curly,
        caretUTF16Offset: (curly as NSString).length
      )?.text == "don’t"
    )
  }

  @Test("A word without a completion boundary is left alone")
  func requiresCompletionBoundary() {
    let text = "teh"

    #expect(
      CompletedWordDetector.immediatelyBeforeCaret(
        in: text,
        caretUTF16Offset: (text as NSString).length
      ) == nil
    )
  }

  @Test("Malformed edge apostrophes do not form a completed word")
  func rejectsEdgeApostrophes() {
    let text = "'word' "

    #expect(
      CompletedWordDetector.immediatelyBeforeCaret(
        in: text,
        caretUTF16Offset: (text as NSString).length
      ) == nil
    )
  }

  @Test("UTF-16 ranges remain correct after multi-unit characters")
  func preservesUTF16Range() throws {
    let text = "😀 intro teh rest"
    let completedRange = (text as NSString).range(of: "teh ")
    let completedWord = try #require(
      CompletedWordDetector.immediatelyBeforeCaret(
        in: text,
        caretUTF16Offset: NSMaxRange(completedRange)
      )
    )

    #expect(completedWord.range == (text as NSString).range(of: "teh"))
  }

  @Test("A bounded scan returns every completed word in UTF-16 order")
  func scansCompletedWordsInRange() {
    let text = "existing 😀 teh café, final"
    let scanStart = (text as NSString).range(of: "teh").location
    let words = CompletedWordDetector.completedWords(
      in: text,
      utf16Range: NSRange(
        location: scanStart,
        length: (text as NSString).length - scanStart
      )
    )

    #expect(words.map(\.text) == ["teh", "café"])
    #expect(words.map(\.range) == [
      (text as NSString).range(of: "teh"),
      (text as NSString).range(of: "café"),
    ])
  }

  @Test("A bounded scan never reaches backward into pre-existing text")
  func boundedScanExcludesEarlierWord() {
    let text = "teh keep teh "
    let secondTypo = (text as NSString).range(
      of: "teh",
      options: .backwards
    )

    #expect(
      CompletedWordDetector.completedWords(
        in: text,
        utf16Range: NSRange(
          location: secondTypo.location,
          length: (text as NSString).length - secondTypo.location
        )
      ).map(\.range) == [secondTypo]
    )
  }
}
