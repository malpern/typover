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

  public init(sentence: String, language: String? = nil) {
    self.sentence = sentence
    self.language = language
  }
}

public struct ContextualCorrectionCandidate: Equatable, Sendable {
  public let original: String
  public let replacement: String
  public let lookupDuration: Duration

  public init(
    original: String,
    replacement: String,
    lookupDuration: Duration = .zero
  ) {
    self.original = original
    self.replacement = replacement
    self.lookupDuration = lookupDuration
  }
}

public protocol ContextualCorrectionEngine: Sendable {
  func availability(
    for language: String?
  ) async -> ContextualCorrectionAvailability

  func proposal(
    for request: ContextualCorrectionRequest
  ) async throws -> ContextualCorrectionCandidate?
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
  ) -> ContextualCorrectionCandidate? {
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

  public static func resolve(
    _ candidate: ContextualCorrectionCandidate,
    in sentence: CompletedSentence,
    language: String?
  ) -> ResolvedContextualCorrection? {
    guard
      isSafeTarget(candidate.original),
      isSafeReplacement(candidate.replacement),
      candidate.original != candidate.replacement
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
}
