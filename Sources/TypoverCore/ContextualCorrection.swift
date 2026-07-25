import Foundation

public enum ContextualCorrectionAvailability: Equatable, Sendable {
  case available
  case unavailable(ContextualCorrectionUnavailableReason)
}

public enum ContextualCorrectionUnavailableReason: Equatable, Sendable {
  case deviceNotEligible
  case appleIntelligenceNotEnabled
  case modelNotReady
  case unsupportedLanguage
}

public struct ContextualCorrectionRequest: Equatable, Sendable {
  public let sentence: String
  public let language: String?
  public let scope: ContextualCorrectionScope
  public let allowsSentenceRewrite: Bool

  public init(
    sentence: String,
    language: String? = nil,
    scope: ContextualCorrectionScope = .careful,
    allowsSentenceRewrite: Bool = false
  ) {
    self.sentence = sentence
    self.language = language
    self.scope = scope
    self.allowsSentenceRewrite =
      scope == .comprehensive && allowsSentenceRewrite
  }
}

public enum ContextualCorrectionKind: Equatable, Sendable {
  case carefulEdit
  case comprehensiveEdit
  case sentenceRewrite
}

public struct ContextualCorrectionCandidate: Equatable, Sendable {
  public let original: String
  public let replacement: String
  public let kind: ContextualCorrectionKind
  public let lookupDuration: Duration

  public init(
    original: String,
    replacement: String,
    kind: ContextualCorrectionKind = .carefulEdit,
    lookupDuration: Duration = .zero
  ) {
    self.original = original
    self.replacement = replacement
    self.kind = kind
    self.lookupDuration = lookupDuration
  }
}

public struct ContextualCorrectionResult: Equatable, Sendable {
  public let candidates: [ContextualCorrectionCandidate]

  public init(candidates: [ContextualCorrectionCandidate]) {
    self.candidates = candidates
  }
}

public protocol ContextualCorrectionEngine: Sendable {
  func availability(
    for language: String?
  ) async -> ContextualCorrectionAvailability

  func proposal(
    for request: ContextualCorrectionRequest
  ) async throws -> ContextualCorrectionResult?
}

public actor DisabledContextualCorrectionEngine: ContextualCorrectionEngine {
  public init() {}

  public func availability(
    for _: String?
  ) -> ContextualCorrectionAvailability {
    .unavailable(.modelNotReady)
  }

  public func proposal(
    for _: ContextualCorrectionRequest
  ) -> ContextualCorrectionResult? {
    nil
  }
}

public struct ResolvedContextualCorrection: Equatable, Sendable {
  public let range: NSRange
  public let proposal: CorrectionProposal

  public init(range: NSRange, proposal: CorrectionProposal) {
    self.range = range
    self.proposal = proposal
  }
}

public enum ContextualCorrectionResolver {
  public static let maximumTargetUTF16Length = 64
  public static let maximumRewriteUTF16Length = 600
  public static let maximumEditsPerSentence = 3
  public static let maximumLexicalEditDistance = 3

  public static func resolve(
    _ result: ContextualCorrectionResult,
    in sentence: CompletedSentence,
    language: String?
  ) -> [ResolvedContextualCorrection]? {
    guard
      !result.candidates.isEmpty,
      result.candidates.count <= maximumEditsPerSentence
    else {
      return nil
    }

    if result.candidates.contains(where: {
      $0.kind == .sentenceRewrite
    }) {
      guard
        result.candidates.count == 1,
        let candidate = result.candidates.first,
        let resolved = resolve(
          candidate,
          in: sentence,
          language: language
        )
      else {
        return nil
      }
      return [resolved]
    }

    let resolved = result.candidates.compactMap {
      resolve($0, in: sentence, language: language)
    }
    guard resolved.count == result.candidates.count else {
      return nil
    }

    let ordered = resolved.sorted {
      $0.range.location < $1.range.location
    }
    for pair in zip(ordered, ordered.dropFirst()) {
      guard NSMaxRange(pair.0.range) <= pair.1.range.location else {
        return nil
      }
    }
    return ordered
  }

  public static func resolve(
    _ candidate: ContextualCorrectionCandidate,
    in sentence: CompletedSentence,
    language: String?
  ) -> ResolvedContextualCorrection? {
    if candidate.kind == .sentenceRewrite {
      return resolveSentenceRewrite(
        candidate,
        in: sentence,
        language: language
      )
    }

    guard
      isSafeTarget(candidate.original),
      isSafeReplacement(candidate.replacement),
      candidate.original != candidate.replacement,
      candidate.kind == .comprehensiveEdit
        || isPlausiblyRelated(
          candidate.original,
          candidate.replacement,
          language: language
        )
    else {
      return nil
    }

    let sentenceText = sentence.text as NSString
    let firstRange = sentenceText.range(of: candidate.original)
    guard firstRange.location != NSNotFound else {
      return nil
    }

    let remainingLocation = NSMaxRange(firstRange)
    let remainingRange = NSRange(
      location: remainingLocation,
      length: sentenceText.length - remainingLocation
    )
    guard
      sentenceText.range(
        of: candidate.original,
        options: [],
        range: remainingRange
      ).location == NSNotFound
    else {
      return nil
    }
    if candidate.kind == .comprehensiveEdit,
      createsAdjacentDuplicate(
        candidate.replacement,
        in: sentenceText,
        replacing: firstRange,
        language: language
      )
    {
      return nil
    }

    let documentRange = NSRange(
      location: sentence.range.location + firstRange.location,
      length: firstRange.length
    )
    let correction = Correction(
      original: candidate.original,
      replacement: candidate.replacement
    )
    return ResolvedContextualCorrection(
      range: documentRange,
      proposal: CorrectionProposal(
        correction: correction,
        source: .appleIntelligence,
        language: language,
        lookupDuration: candidate.lookupDuration
      )
    )
  }

  private static func isSafeTarget(_ text: String) -> Bool {
    let utf16Length = text.utf16.count
    return utf16Length > 0
      && utf16Length <= maximumTargetUTF16Length
      && text.rangeOfCharacter(from: .newlines) == nil
      && text.rangeOfCharacter(
        from: CharacterSet(charactersIn: ".!?…")
      ) == nil
      && text.trimmingCharacters(in: .whitespaces) == text
  }

  private static func isSafeReplacement(_ text: String) -> Bool {
    let utf16Length = text.utf16.count
    return utf16Length > 0
      && utf16Length <= maximumTargetUTF16Length
      && text.rangeOfCharacter(from: .newlines) == nil
      && text.rangeOfCharacter(
        from: CharacterSet(charactersIn: ".!?…")
      ) == nil
      && text.trimmingCharacters(in: .whitespaces) == text
  }

  private static func resolveSentenceRewrite(
    _ candidate: ContextualCorrectionCandidate,
    in sentence: CompletedSentence,
    language: String?
  ) -> ResolvedContextualCorrection? {
    guard
      candidate.original == sentence.text,
      candidate.replacement != sentence.text,
      (1...maximumRewriteUTF16Length).contains(
        candidate.replacement.utf16.count
      ),
      candidate.replacement.rangeOfCharacter(from: .newlines) == nil,
      candidate.replacement.trimmingCharacters(in: .whitespaces)
        == candidate.replacement,
      let finalCharacter = candidate.replacement.last,
      CompletedSentenceDetector.isSentenceTerminator(
        String(finalCharacter)
      )
    else {
      return nil
    }

    let correction = Correction(
      original: candidate.original,
      replacement: candidate.replacement
    )
    return ResolvedContextualCorrection(
      range: sentence.range,
      proposal: CorrectionProposal(
        correction: correction,
        source: .appleIntelligenceRewrite,
        language: language,
        lookupDuration: candidate.lookupDuration
      )
    )
  }

  private static func isPlausiblyRelated(
    _ original: String,
    _ replacement: String,
    language: String?
  ) -> Bool {
    let locale = language.map(Locale.init(identifier:)) ?? .current
    let normalizedOriginal = original.lowercased(with: locale)
    let normalizedReplacement = replacement.lowercased(with: locale)
    if normalizedOriginal == "of", normalizedReplacement == "have" {
      return true
    }

    return AutomaticCorrectionPolicy().optimalStringAlignmentDistance(
      from: normalizedOriginal,
      to: normalizedReplacement
    ) <= maximumLexicalEditDistance
  }

  private static func createsAdjacentDuplicate(
    _ replacement: String,
    in sentence: NSString,
    replacing range: NSRange,
    language: String?
  ) -> Bool {
    let locale = language.map(Locale.init(identifier:)) ?? .current
    let prefix = sentence.substring(
      with: NSRange(location: 0, length: range.location)
    )
    let suffix = sentence.substring(
      with: NSRange(
        location: NSMaxRange(range),
        length: sentence.length - NSMaxRange(range)
      )
    )
    let replacementWords = words(in: replacement)
    guard
      let replacementFirst = replacementWords.first,
      let replacementLast = replacementWords.last
    else {
      return false
    }

    if let previousWord = words(in: prefix).last,
      previousWord.lowercased(with: locale)
        == replacementFirst.lowercased(with: locale)
    {
      return true
    }
    if let nextWord = words(in: suffix).first,
      nextWord.lowercased(with: locale)
        == replacementLast.lowercased(with: locale)
    {
      return true
    }
    return false
  }

  private static func words(in text: String) -> [String] {
    text.split { character in
      !character.isLetter
        && character != "'"
        && character != "’"
    }
    .map(String.init)
  }
}
