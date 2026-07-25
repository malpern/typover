import Foundation

public struct AutomaticCorrectionPolicy: Sendable {
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
    guard
      isEligibleLowercaseWord(original),
      isEligibleLowercaseWord(primary),
      original != primary,
      optimalStringAlignmentDistance(from: original, to: primary) == 1
    else {
      return nil
    }

    var seen = Set([original, primary])
    let filteredAlternatives = alternatives.compactMap { candidate -> String? in
      guard
        isEligibleLowercaseWord(candidate),
        seen.insert(candidate).inserted
      else {
        return nil
      }
      return candidate
    }
    .prefix(maximumAlternatives)

    return CorrectionProposal(
      correction: Correction(
        original: original,
        replacement: primary
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

  private func isEligibleLowercaseWord(_ word: String) -> Bool {
    guard
      (minimumWordLength...maximumWordLength).contains(word.count),
      word.unicodeScalars.allSatisfy({ scalar in
        scalar.isASCII && CharacterSet.lowercaseLetters.contains(scalar)
      })
    else {
      return false
    }
    return true
  }
}
