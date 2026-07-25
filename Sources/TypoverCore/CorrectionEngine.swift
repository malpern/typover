import Foundation

public enum CorrectionSource: String, Codable, CaseIterable, Equatable, Hashable,
  Sendable
{
  case demo
  case appleIntelligence
  case appleIntelligenceRewrite
  case appleSpelling
  case anthropic
  case anthropicRewrite
  case rememberedPreference
  case openAI
  case openAIRewrite
}

public enum CorrectionUserResponse: Equatable, Sendable {
  case accepted
  case reverted
  case edited
}

public struct CorrectionProposal: Equatable, Sendable {
  public let correction: Correction
  public let alternatives: [String]
  public let source: CorrectionSource
  public let language: String?
  public let lookupDuration: Duration

  public init(
    correction: Correction,
    alternatives: [String] = [],
    source: CorrectionSource,
    language: String? = nil,
    lookupDuration: Duration = .zero
  ) {
    self.correction = correction
    self.alternatives = alternatives
    self.source = source
    self.language = language
    self.lookupDuration = lookupDuration
  }
}

@MainActor
public protocol CorrectionEngine {
  func proposal(for word: String) -> CorrectionProposal?

  func record(
    _ response: CorrectionUserResponse,
    for proposal: CorrectionProposal
  )
}

extension CorrectionEngine {
  public func record(
    _ response: CorrectionUserResponse,
    for proposal: CorrectionProposal
  ) {}
}

@MainActor
public struct DemoCorrectionEngine: CorrectionEngine {
  public init() {}

  public func proposal(for word: String) -> CorrectionProposal? {
    guard word == "teh" else {
      return nil
    }

    return CorrectionProposal(
      correction: Correction(
        original: word,
        replacement: "the"
      ),
      source: .demo
    )
  }
}
