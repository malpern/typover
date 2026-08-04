import Foundation

public struct CompletedSentence: Equatable, Sendable {
  public let range: NSRange
  public let text: String

  public init(range: NSRange, text: String) {
    self.range = range
    self.text = text
  }
}

public enum CompletedSentenceDetector {
  public static let maximumUTF16Length = 400

  private static let sentenceTerminators = CharacterSet(
    charactersIn: ".!?…"
  )

  public static func immediatelyBeforeCaret(
    in text: String,
    caretUTF16Offset: Int
  ) -> CompletedSentence? {
    let text = text as NSString
    guard
      caretUTF16Offset > 0,
      caretUTF16Offset <= text.length
    else {
      return nil
    }

    let terminatorRange = text.rangeOfComposedCharacterSequence(
      at: caretUTF16Offset - 1
    )
    let terminator = text.substring(with: terminatorRange)
    guard isSentenceTerminator(terminator) else {
      return nil
    }

    var sentenceStart = terminatorRange.location
    while sentenceStart > 0 {
      let characterRange = text.rangeOfComposedCharacterSequence(
        at: sentenceStart - 1
      )
      let character = text.substring(with: characterRange)
      if isSentenceTerminator(character) {
        break
      }
      sentenceStart = characterRange.location
    }

    while sentenceStart < terminatorRange.location {
      let characterRange = text.rangeOfComposedCharacterSequence(
        at: sentenceStart
      )
      let character = text.substring(with: characterRange)
      guard isLeadingSeparator(character) else {
        break
      }
      sentenceStart = NSMaxRange(characterRange)
    }

    let sentenceRange = NSRange(
      location: sentenceStart,
      length: caretUTF16Offset - sentenceStart
    )
    guard
      sentenceRange.length > 1,
      sentenceRange.length <= maximumUTF16Length
    else {
      return nil
    }

    return CompletedSentence(
      range: sentenceRange,
      text: text.substring(with: sentenceRange)
    )
  }

  /// Resolves a completed sentence from a bounded document fragment while
  /// refusing a sentence whose beginning may have been truncated. The
  /// returned range uses document coordinates.
  public static func immediatelyBeforeCaret(
    inBoundedText text: String,
    documentRange: NSRange,
    caretDocumentOffset: Int
  ) -> CompletedSentence? {
    let textLength = text.utf16.count
    guard
      documentRange.location >= 0,
      documentRange.length == textLength,
      documentRange.location <= Int.max - documentRange.length
    else {
      return nil
    }
    let documentEnd = documentRange.location + documentRange.length
    guard
      caretDocumentOffset >= documentRange.location,
      caretDocumentOffset <= documentEnd,
      let localSentence = immediatelyBeforeCaret(
        in: text,
        caretUTF16Offset: caretDocumentOffset - documentRange.location
      )
    else {
      return nil
    }

    if documentRange.location > 0,
      !hasVerifiedSentenceBoundary(
        before: localSentence.range.location,
        in: text
      )
    {
      return nil
    }

    return CompletedSentence(
      range: NSRange(
        location: documentRange.location + localSentence.range.location,
        length: localSentence.range.length
      ),
      text: localSentence.text
    )
  }

  public static func isSentenceTerminator(_ text: String) -> Bool {
    !text.isEmpty
      && text.unicodeScalars.allSatisfy { scalar in
        sentenceTerminators.contains(scalar)
      }
  }

  private static func isLeadingSeparator(_ text: String) -> Bool {
    text.unicodeScalars.allSatisfy { scalar in
      CharacterSet.whitespacesAndNewlines.contains(scalar)
        || scalar == "\""
        || scalar == "“"
        || scalar == "”"
    }
  }

  private static func hasVerifiedSentenceBoundary(
    before sentenceLocation: Int,
    in text: String
  ) -> Bool {
    let text = text as NSString
    var location = sentenceLocation
    while location > 0 {
      let characterRange = text.rangeOfComposedCharacterSequence(
        at: location - 1
      )
      let character = text.substring(with: characterRange)
      if !isLeadingSeparator(character) {
        return isSentenceTerminator(character)
      }
      location = characterRange.location
    }
    return false
  }
}
