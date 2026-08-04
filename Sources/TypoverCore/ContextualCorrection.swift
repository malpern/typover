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
  public let source: CorrectionSource

  public init(
    original: String,
    replacement: String,
    kind: ContextualCorrectionKind = .carefulEdit,
    lookupDuration: Duration = .zero,
    source: CorrectionSource = .appleIntelligence
  ) {
    self.original = original
    self.replacement = replacement
    self.kind = kind
    self.lookupDuration = lookupDuration
    self.source = source
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
      candidate.kind != .comprehensiveEdit
        || (isSafeComprehensiveEdit(
          original: candidate.original,
          replacement: candidate.replacement,
          language: language
        ) && isSafeComprehensiveContext(sentence.text)),
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
        || changesBritishCollectiveAgreement(
          original: candidate.original,
          replacement: candidate.replacement,
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
        source: editSource(for: candidate.source),
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

  private static func isSafeComprehensiveEdit(
    original: String,
    replacement: String,
    language: String?
  ) -> Bool {
    let forbiddenCharacters = CharacterSet(
      charactersIn: "()[]{}`"
    )
    guard
      original.rangeOfCharacter(from: forbiddenCharacters) == nil,
      replacement.rangeOfCharacter(from: forbiddenCharacters) == nil,
      !original.contains("://"),
      !replacement.contains("://")
    else {
      return false
    }

    let locale = language.map(Locale.init(identifier:)) ?? .current
    return (words(in: original) + words(in: replacement)).allSatisfy {
      isOrdinaryCasePattern($0, locale: locale)
    }
  }

  private static func isSafeComprehensiveContext(_ sentence: String) -> Bool {
    let quoteCharacters = CharacterSet(
      charactersIn: "\"“”„‟«»"
    )
    guard sentence.rangeOfCharacter(from: quoteCharacters) == nil else {
      return false
    }

    let normalized = sentence.lowercased()
    let promptLikePhrases = [
      "ignore previous instructions",
      "ignore the instructions",
      "rewrite this sentence",
      "replace every word",
      "system prompt",
    ]
    return !promptLikePhrases.contains(where: normalized.contains)
  }

  private static func isOrdinaryCasePattern(
    _ word: String,
    locale: Locale
  ) -> Bool {
    let lowercase = word.lowercased(with: locale)
    let uppercase = word.uppercased(with: locale)
    guard lowercase != uppercase else { return true }
    if word == lowercase || word == uppercase {
      return true
    }
    guard let first = lowercase.first else { return true }
    return word == String(first).uppercased(with: locale) + lowercase.dropFirst()
  }

  private static func resolveSentenceRewrite(
    _ candidate: ContextualCorrectionCandidate,
    in sentence: CompletedSentence,
    language: String?
  ) -> ResolvedContextualCorrection? {
    guard
      candidate.original == sentence.text,
      candidate.replacement != sentence.text,
      isEligibleForSentenceRewrite(sentence.text),
      addressesConcreteRewriteSignal(
        from: sentence.text,
        in: candidate.replacement
      ),
      preservesRewriteToneMarkers(
        from: sentence.text,
        in: candidate.replacement
      ),
      preservesPrecisionTokens(
        from: sentence.text,
        in: candidate.replacement
      ),
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
        source: rewriteSource(for: candidate.source),
        language: language,
        lookupDuration: candidate.lookupDuration
      )
    )
  }

  private static func editSource(
    for source: CorrectionSource
  ) -> CorrectionSource {
    switch source {
    case .appleIntelligenceRewrite:
      .appleIntelligence
    case .openAIRewrite:
      .openAI
    case .anthropicRewrite:
      .anthropic
    default:
      source
    }
  }

  private static func rewriteSource(
    for source: CorrectionSource
  ) -> CorrectionSource {
    switch source {
    case .appleIntelligence, .appleIntelligenceRewrite:
      .appleIntelligenceRewrite
    case .openAI, .openAIRewrite:
      .openAIRewrite
    case .anthropic, .anthropicRewrite:
      .anthropicRewrite
    default:
      source
    }
  }

  public static func isEligibleForSentenceRewrite(
    _ sentence: String
  ) -> Bool {
    let quoteCharacters = CharacterSet(
      charactersIn: "\"“”„‟«»"
    )
    guard
      sentence.rangeOfCharacter(from: quoteCharacters) == nil,
      !sentence.contains("—"),
      !sentence.contains("://"),
      !sentence.contains("()")
    else {
      return false
    }

    let normalized = sentence.lowercased()
    let protectedPhrases = [
      "ignore previous instructions",
      "ignore the instructions",
      "rewrite this sentence",
      "system prompt",
    ]
    guard
      !protectedPhrases.contains(where: normalized.contains),
      !normalized.contains("n't"),
      !normalized.contains("n’t")
    else {
      return false
    }

    let protectedWords: Set<String> = [
      "if", "unless", "not", "never", "may", "might", "could", "should",
    ]
    return protectedWords.isDisjoint(with: Set(words(in: normalized)))
      && hasConcreteRewriteSignal(normalized)
  }

  private static func hasConcreteRewriteSignal(_ sentence: String) -> Bool {
    if rewriteClaritySignals.contains(where: sentence.contains) {
      return true
    }
    return repeatedRewriteWords(in: sentence).isEmpty == false
  }

  private static let rewriteClaritySignals = [
    "due to the fact",
    "later point in time",
    "at this point in time",
    "currently waiting",
    "respond back",
    "conducted an analysis",
    "in order to",
    "is one that",
    "make updates",
    "made a decision",
    "wanted to reach out",
    "let you know that",
    "despite the fact",
    "in the amount of",
    "within a period of",
    "please be advised",
    "the reason ",
    "decision was made",
    "what you need to do",
    "after that",
    "utilize",
    "for the purpose of",
    "can then proceed",
    "in length",
    "in duration",
  ]

  private static func repeatedRewriteWords(
    in sentence: String
  ) -> [String: Int] {
    let ignoredWords: Set<String> = [
      "about", "after", "again", "before", "their", "there", "these",
      "those", "which", "would",
    ]
    var counts: [String: Int] = [:]
    for word in words(in: sentence)
    where word.count >= 4 && !ignoredWords.contains(word) {
      counts[word, default: 0] += 1
    }
    return counts.filter { $0.value >= 2 }
  }

  private static func addressesConcreteRewriteSignal(
    from original: String,
    in replacement: String
  ) -> Bool {
    let normalizedOriginal = original.lowercased()
    let normalizedReplacement = replacement.lowercased()
    let originalSignals = rewriteClaritySignals.filter(
      normalizedOriginal.contains
    )
    if !originalSignals.isEmpty {
      return originalSignals.allSatisfy {
        !normalizedReplacement.contains($0)
      }
    }

    let originalRepeatedWords = repeatedRewriteWords(
      in: normalizedOriginal
    )
    let replacementCounts = Dictionary(
      grouping: words(in: normalizedReplacement),
      by: { $0 }
    ).mapValues(\.count)
    return originalRepeatedWords.contains { word, count in
      replacementCounts[word, default: 0] < count
    }
  }

  private static func preservesRewriteToneMarkers(
    from original: String,
    in replacement: String
  ) -> Bool {
    let normalizedOriginal = original.lowercased()
    let normalizedReplacement = replacement.lowercased()
    let originalWords = words(in: normalizedOriginal)
    let replacementWords = words(in: normalizedReplacement)

    if originalWords.first == "please",
      !replacementWords.contains("please")
    {
      return false
    }
    if originalWords.first == "i",
      !replacementWords.contains("i")
    {
      return false
    }
    if normalizedOriginal.contains("you can"),
      !normalizedReplacement.contains("you can")
    {
      return false
    }
    return true
  }

  private static func preservesPrecisionTokens(
    from original: String,
    in replacement: String
  ) -> Bool {
    precisionTokens(in: original).allSatisfy {
      replacement.contains($0)
    }
  }

  private static func precisionTokens(in text: String) -> [String] {
    let boundaryCharacters = CharacterSet(
      charactersIn: ".,;:!?()[]{}\"“”"
    )
    return text.components(separatedBy: .whitespacesAndNewlines)
      .map { $0.trimmingCharacters(in: boundaryCharacters) }
      .filter { token in
        token.contains(where: \.isNumber)
          || token.hasPrefix("$")
          || token.hasPrefix("#")
      }
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

    if let previousWord = words(in: prefix).last {
      let normalizedPrevious = previousWord.lowercased(with: locale)
      let normalizedFirst = replacementFirst.lowercased(with: locale)
      if normalizedPrevious == normalizedFirst
        || (normalizedPrevious.hasSuffix("ing")
          && normalizedFirst.hasSuffix("ing"))
      {
        return true
      }
    }
    if let nextWord = words(in: suffix).first,
      nextWord.lowercased(with: locale)
        == replacementLast.lowercased(with: locale)
    {
      return true
    }
    return false
  }

  private static func changesBritishCollectiveAgreement(
    original: String,
    replacement: String,
    in sentence: NSString,
    replacing range: NSRange,
    language: String?
  ) -> Bool {
    guard
      language?.lowercased().hasPrefix("en_gb") == true,
      original.lowercased() == "are",
      replacement.lowercased() == "is"
    else {
      return false
    }

    let prefix = sentence.substring(
      with: NSRange(location: 0, length: range.location)
    )
    guard let previousWord = words(in: prefix).last?.lowercased() else {
      return false
    }
    let collectiveNouns: Set<String> = [
      "committee", "family", "government", "staff", "team",
    ]
    return collectiveNouns.contains(previousWord)
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
