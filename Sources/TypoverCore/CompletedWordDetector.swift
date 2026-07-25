import Foundation

public struct CompletedWord: Equatable, Sendable {
  public let range: NSRange
  public let text: String

  public init(range: NSRange, text: String) {
    self.range = range
    self.text = text
  }
}

public enum CompletedWordDetector {
  private static let punctuationBoundaries = CharacterSet(
    charactersIn: ".,!?;:…"
  )

  public static func immediatelyBeforeCaret(
    in text: String,
    caretUTF16Offset: Int
  ) -> CompletedWord? {
    let text = text as NSString
    guard
      caretUTF16Offset > 0,
      caretUTF16Offset <= text.length
    else {
      return nil
    }

    let boundaryRange = text.rangeOfComposedCharacterSequence(
      at: caretUTF16Offset - 1
    )
    let boundary = text.substring(with: boundaryRange)
    guard isCompletionBoundary(boundary) else {
      return nil
    }

    var wordStart = boundaryRange.location
    while wordStart > 0 {
      let characterRange = text.rangeOfComposedCharacterSequence(
        at: wordStart - 1
      )
      let character = text.substring(with: characterRange)
      guard isWordCharacter(character) else {
        break
      }
      wordStart = characterRange.location
    }

    let wordRange = NSRange(
      location: wordStart,
      length: boundaryRange.location - wordStart
    )
    guard wordRange.length > 0 else {
      return nil
    }

    let word = text.substring(with: wordRange)
    guard hasValidApostrophes(word) else {
      return nil
    }
    return CompletedWord(range: wordRange, text: word)
  }

  private static func isCompletionBoundary(_ character: String) -> Bool {
    character.unicodeScalars.allSatisfy { scalar in
      CharacterSet.whitespacesAndNewlines.contains(scalar)
        || punctuationBoundaries.contains(scalar)
    }
  }

  private static func isWordCharacter(_ character: String) -> Bool {
    if character == "'" || character == "’" {
      return true
    }

    var containsLetter = false
    for scalar in character.unicodeScalars {
      if CharacterSet.letters.contains(scalar) {
        containsLetter = true
      } else if !CharacterSet.nonBaseCharacters.contains(scalar) {
        return false
      }
    }
    return containsLetter
  }

  private static func hasValidApostrophes(_ word: String) -> Bool {
    let characters = Array(word)
    guard
      characters.first.map({ !isApostrophe($0) }) == true,
      characters.last.map({ !isApostrophe($0) }) == true
    else {
      return false
    }

    return characters.indices.allSatisfy { index in
      guard isApostrophe(characters[index]) else {
        return true
      }

      let previousIndex = characters.index(before: index)
      let nextIndex = characters.index(after: index)
      return isLetter(characters[previousIndex])
        && isLetter(characters[nextIndex])
    }
  }

  private static func isLetter(_ character: Character) -> Bool {
    character.unicodeScalars.contains(where: CharacterSet.letters.contains)
  }

  private static func isApostrophe(_ character: Character) -> Bool {
    character == "'" || character == "’"
  }
}
