import Foundation

public struct AutomaticCorrectionPolicy: Sendable {
  private enum CaseStyle {
    case lowercase
    case capitalized
    case uppercase
    case unchanged
  }

  public let minimumWordLength: Int
  public let maximumWordLength: Int
  public let maximumAlternatives: Int

  public init(
    minimumWordLength: Int = 3,
    maximumWordLength: Int = 24,
    maximumAlternatives: Int = 4
  ) {
    self.minimumWordLength = minimumWordLength
    self.maximumWordLength = maximumWordLength
    self.maximumAlternatives = maximumAlternatives
  }

  public func proposal(
    original: String,
    primary: String,
    alternatives: [String],
    source: CorrectionSource,
    language: String?,
    lookupDuration: Duration
  ) -> CorrectionProposal? {
    let locale = language.map(Locale.init(identifier:)) ?? .current
    guard
      isEligibleWord(original),
      isEligibleWord(primary),
      let caseStyle = caseStyle(of: original, locale: locale)
    else {
      return nil
    }

    let replacement = applying(
      caseStyle,
      to: primary,
      locale: locale
    )
    guard
      isEligibleWord(replacement),
      original != replacement,
      optimalStringAlignmentDistance(from: original, to: replacement) == 1
    else {
      return nil
    }

    var seen = Set([original, replacement])
    let filteredAlternatives = alternatives.compactMap { candidate -> String? in
      let normalizedCandidate = applying(
        caseStyle,
        to: candidate,
        locale: locale
      )
      guard
        isEligibleWord(candidate),
        isEligibleWord(normalizedCandidate),
        seen.insert(normalizedCandidate).inserted
      else {
        return nil
      }
      return normalizedCandidate
    }
    .prefix(maximumAlternatives)

    return CorrectionProposal(
      correction: Correction(
        original: original,
        replacement: replacement
      ),
      alternatives: Array(filteredAlternatives),
      source: source,
      language: language,
      lookupDuration: lookupDuration
    )
  }

  public func optimalStringAlignmentDistance(
    from source: String,
    to target: String
  ) -> Int {
    let sourceCharacters = Array(source)
    let targetCharacters = Array(target)

    if sourceCharacters.isEmpty {
      return targetCharacters.count
    }
    if targetCharacters.isEmpty {
      return sourceCharacters.count
    }

    var distances = Array(
      repeating: Array(
        repeating: 0,
        count: targetCharacters.count + 1
      ),
      count: sourceCharacters.count + 1
    )

    for sourceIndex in 0...sourceCharacters.count {
      distances[sourceIndex][0] = sourceIndex
    }
    for targetIndex in 0...targetCharacters.count {
      distances[0][targetIndex] = targetIndex
    }

    for sourceIndex in 1...sourceCharacters.count {
      for targetIndex in 1...targetCharacters.count {
        let substitutionCost =
          sourceCharacters[sourceIndex - 1] == targetCharacters[targetIndex - 1]
          ? 0
          : 1

        distances[sourceIndex][targetIndex] = min(
          distances[sourceIndex - 1][targetIndex] + 1,
          distances[sourceIndex][targetIndex - 1] + 1,
          distances[sourceIndex - 1][targetIndex - 1] + substitutionCost
        )

        if sourceIndex > 1,
          targetIndex > 1,
          sourceCharacters[sourceIndex - 1] == targetCharacters[targetIndex - 2],
          sourceCharacters[sourceIndex - 2] == targetCharacters[targetIndex - 1]
        {
          distances[sourceIndex][targetIndex] = min(
            distances[sourceIndex][targetIndex],
            distances[sourceIndex - 2][targetIndex - 2] + 1
          )
        }
      }
    }

    return distances[sourceCharacters.count][targetCharacters.count]
  }

  private func isEligibleWord(_ word: String) -> Bool {
    let characters = Array(word)
    guard
      (minimumWordLength...maximumWordLength).contains(word.count),
      characters.contains(where: isLetter),
      characters.allSatisfy(isWordCharacter),
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

  private func isWordCharacter(_ character: Character) -> Bool {
    if isApostrophe(character) {
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

  private func isLetter(_ character: Character) -> Bool {
    character.unicodeScalars.contains(where: CharacterSet.letters.contains)
  }

  private func isApostrophe(_ character: Character) -> Bool {
    character == "'" || character == "’"
  }

  private func caseStyle(
    of word: String,
    locale: Locale
  ) -> CaseStyle? {
    let lowercase = word.lowercased(with: locale)
    let uppercase = word.uppercased(with: locale)

    if lowercase == uppercase {
      return .unchanged
    }
    if word == lowercase {
      return .lowercase
    }
    if word == uppercase {
      return .uppercase
    }
    if word == capitalizingFirstLetter(in: lowercase, locale: locale) {
      return .capitalized
    }
    return nil
  }

  private func applying(
    _ style: CaseStyle,
    to word: String,
    locale: Locale
  ) -> String {
    switch style {
    case .lowercase:
      return word.lowercased(with: locale)
    case .capitalized:
      return capitalizingFirstLetter(
        in: word.lowercased(with: locale),
        locale: locale
      )
    case .uppercase:
      return word.uppercased(with: locale)
    case .unchanged:
      return word
    }
  }

  private func capitalizingFirstLetter(
    in word: String,
    locale: Locale
  ) -> String {
    guard let letterIndex = word.firstIndex(where: isLetter) else {
      return word
    }

    var result = word
    let nextIndex = result.index(after: letterIndex)
    let capitalizedLetter = String(result[letterIndex]).uppercased(with: locale)
    result.replaceSubrange(
      letterIndex..<nextIndex,
      with: capitalizedLetter
    )
    return result
  }
}
