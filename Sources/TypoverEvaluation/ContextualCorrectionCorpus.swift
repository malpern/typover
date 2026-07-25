import Foundation

public struct ContextualCorrectionCorpus: Decodable, Sendable {
  public let schemaVersion: Int
  public let cases: [ContextualCorrectionCorpusCase]

  public init(
    schemaVersion: Int,
    cases: [ContextualCorrectionCorpusCase]
  ) {
    self.schemaVersion = schemaVersion
    self.cases = cases
  }
}

public struct ContextualCorrectionCorpusCase: Decodable, Sendable {
  public let id: String
  public let category: String
  public let sentence: String
  public let language: String?
  public let reviewStatus: CorrectionCorpusReviewStatus
  public let expectation: ContextualCorrectionExpectation

  public init(
    id: String,
    category: String,
    sentence: String,
    language: String? = nil,
    reviewStatus: CorrectionCorpusReviewStatus,
    expectation: ContextualCorrectionExpectation
  ) {
    self.id = id
    self.category = category
    self.sentence = sentence
    self.language = language
    self.reviewStatus = reviewStatus
    self.expectation = expectation
  }
}

public enum ContextualCorrectionExpectation: Equatable, Sendable {
  case correction(original: String, replacement: String)
  case unchanged
}

extension ContextualCorrectionExpectation: Decodable {
  private enum CodingKeys: String, CodingKey {
    case kind
    case original
    case replacement
  }

  private enum Kind: String, Decodable {
    case correction
    case unchanged
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .kind) {
    case .correction:
      self = try .correction(
        original: container.decode(String.self, forKey: .original),
        replacement: container.decode(String.self, forKey: .replacement)
      )
    case .unchanged:
      self = .unchanged
    }
  }
}

public enum ContextualCorrectionCorpusLoader {
  public static func loadBundled() throws -> ContextualCorrectionCorpus {
    guard
      let url = Bundle.module.url(
        forResource: "contextual-corpus-v1",
        withExtension: "json"
      )
    else {
      throw CocoaError(.fileNoSuchFile)
    }

    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(
      ContextualCorrectionCorpus.self,
      from: data
    )
  }
}
