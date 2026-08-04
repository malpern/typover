import Foundation

public struct MinimalTextReplacement: Equatable, Sendable {
  public let original: String
  public let replacement: String

  public init(original: String, replacement: String) {
    self.original = original
    self.replacement = replacement
  }

  public static func difference(
    from original: String,
    to replacement: String
  ) -> MinimalTextReplacement? {
    guard original != replacement else {
      return nil
    }

    let originalCharacters = Array(original)
    let replacementCharacters = Array(replacement)
    var sharedPrefixCount = 0
    while sharedPrefixCount < originalCharacters.count,
      sharedPrefixCount < replacementCharacters.count,
      originalCharacters[sharedPrefixCount]
        == replacementCharacters[sharedPrefixCount]
    {
      sharedPrefixCount += 1
    }

    var sharedSuffixCount = 0
    while sharedSuffixCount
      < originalCharacters.count - sharedPrefixCount,
      sharedSuffixCount
        < replacementCharacters.count - sharedPrefixCount,
      originalCharacters[
        originalCharacters.count - sharedSuffixCount - 1
      ]
        == replacementCharacters[
          replacementCharacters.count - sharedSuffixCount - 1
        ]
    {
      sharedSuffixCount += 1
    }

    while sharedPrefixCount > 0,
      isWordCharacter(originalCharacters[sharedPrefixCount - 1])
    {
      sharedPrefixCount -= 1
    }

    while sharedSuffixCount > 0 {
      let originalIndex =
        originalCharacters.count - sharedSuffixCount
      let replacementIndex =
        replacementCharacters.count - sharedSuffixCount
      guard
        isWordCharacter(originalCharacters[originalIndex])
          || isWordCharacter(replacementCharacters[replacementIndex])
      else {
        break
      }
      sharedSuffixCount -= 1
    }

    let originalEnd = originalCharacters.count - sharedSuffixCount
    let replacementEnd = replacementCharacters.count - sharedSuffixCount
    return MinimalTextReplacement(
      original: String(
        originalCharacters[sharedPrefixCount..<originalEnd]
      ),
      replacement: String(
        replacementCharacters[
          sharedPrefixCount..<replacementEnd
        ]
      )
    )
  }

  private static func isWordCharacter(_ character: Character) -> Bool {
    character == "'"
      || character == "’"
      || character.unicodeScalars.allSatisfy { scalar in
        CharacterSet.alphanumerics.contains(scalar)
          || CharacterSet.nonBaseCharacters.contains(scalar)
      }
  }
}
