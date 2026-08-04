import AppKit
import TypoverCore

@MainActor
public final class AppleSpellCheckerEngine: CorrectionEngine {
  private let checker: any AppleSpellingChecking
  private let documentTag: Int
  private let language: String
  private let policy: AutomaticCorrectionPolicy

  public convenience init(
    language: String? = nil,
    policy: AutomaticCorrectionPolicy = AutomaticCorrectionPolicy()
  ) {
    let checker = NSSpellChecker.shared
    self.init(
      checker: checker,
      language: language ?? checker.userPreferredLanguages.first ?? "en_US",
      policy: policy
    )
  }

  init(
    checker: any AppleSpellingChecking,
    language: String,
    policy: AutomaticCorrectionPolicy
  ) {
    self.checker = checker
    self.documentTag = checker.uniqueDocumentTag()
    self.language = language
    self.policy = policy
  }

  isolated deinit {
    checker.closeDocument(withTag: documentTag)
  }

  public func proposal(for word: String) -> CorrectionProposal? {
    let range = NSRange(location: 0, length: word.utf16.count)
    let clock = ContinuousClock()
    let start = clock.now

    guard
      checker.misspelledRange(
        in: word,
        language: language,
        documentTag: documentTag
      ) == range
    else {
      return nil
    }

    let guesses = checker.guesses(
      for: range,
      in: word,
      language: language,
      documentTag: documentTag
    )
    guard
      let primary =
        checker.correction(
          for: range,
          in: word,
          language: language,
          documentTag: documentTag
        ) ?? guesses.first
    else {
      return nil
    }
    let elapsed = start.duration(to: clock.now)

    return policy.proposal(
      original: word,
      primary: primary,
      alternatives: guesses,
      source: .appleSpelling,
      language: language,
      lookupDuration: elapsed
    )
  }

  public func record(
    _ response: CorrectionUserResponse,
    for proposal: CorrectionProposal
  ) {
    checker.record(
      response,
      correction: proposal.correction.replacement,
      original: proposal.correction.original,
      language: proposal.language ?? language,
      documentTag: documentTag
    )
  }
}

@MainActor
protocol AppleSpellingChecking: AnyObject {
  func uniqueDocumentTag() -> Int

  func closeDocument(withTag tag: Int)

  func misspelledRange(
    in word: String,
    language: String,
    documentTag: Int
  ) -> NSRange

  func correction(
    for range: NSRange,
    in word: String,
    language: String,
    documentTag: Int
  ) -> String?

  func guesses(
    for range: NSRange,
    in word: String,
    language: String,
    documentTag: Int
  ) -> [String]

  func record(
    _ response: CorrectionUserResponse,
    correction: String,
    original: String,
    language: String,
    documentTag: Int
  )
}

@MainActor
extension NSSpellChecker: AppleSpellingChecking {
  func uniqueDocumentTag() -> Int {
    Self.uniqueSpellDocumentTag()
  }

  func closeDocument(withTag tag: Int) {
    closeSpellDocument(withTag: tag)
  }

  func misspelledRange(
    in word: String,
    language: String,
    documentTag: Int
  ) -> NSRange {
    checkSpelling(
      of: word,
      startingAt: 0,
      language: language,
      wrap: false,
      inSpellDocumentWithTag: documentTag,
      wordCount: nil
    )
  }

  func correction(
    for range: NSRange,
    in word: String,
    language: String,
    documentTag: Int
  ) -> String? {
    correction(
      forWordRange: range,
      in: word,
      language: language,
      inSpellDocumentWithTag: documentTag
    )
  }

  func guesses(
    for range: NSRange,
    in word: String,
    language: String,
    documentTag: Int
  ) -> [String] {
    guesses(
      forWordRange: range,
      in: word,
      language: language,
      inSpellDocumentWithTag: documentTag
    ) ?? []
  }

  func record(
    _ response: CorrectionUserResponse,
    correction: String,
    original: String,
    language: String,
    documentTag: Int
  ) {
    let appleResponse: NSSpellChecker.CorrectionResponse
    switch response {
    case .accepted:
      appleResponse = .accepted
    case .reverted:
      appleResponse = .reverted
    case .edited:
      appleResponse = .edited
    }

    record(
      appleResponse,
      toCorrection: correction,
      forWord: original,
      language: language,
      inSpellDocumentWithTag: documentTag
    )
  }
}
