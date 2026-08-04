import Foundation

public struct SentenceRewriteCorpus: Decodable, Sendable {
  public let schemaVersion: Int
  public let cases: [SentenceRewriteCorpusCase]

  public init(
    schemaVersion: Int,
    cases: [SentenceRewriteCorpusCase]
  ) {
    self.schemaVersion = schemaVersion
    self.cases = cases
  }
}

public struct SentenceRewriteCorpusCase: Decodable, Sendable {
  public let id: String
  public let category: String
  public let sentence: String
  public let language: String?
  public let reviewStatus: CorrectionCorpusReviewStatus
  public let expectation: SentenceRewriteExpectation

  public init(
    id: String,
    category: String,
    sentence: String,
    language: String? = nil,
    reviewStatus: CorrectionCorpusReviewStatus,
    expectation: SentenceRewriteExpectation
  ) {
    self.id = id
    self.category = category
    self.sentence = sentence
    self.language = language
    self.reviewStatus = reviewStatus
    self.expectation = expectation
  }
}

public enum SentenceRewriteExpectation: Equatable, Sendable {
  case rewrite(
    protectedFragments: [String],
    forbiddenFragments: [String]
  )
  case unchanged
}

extension SentenceRewriteExpectation: Decodable {
  private enum CodingKeys: String, CodingKey {
    case kind
    case protectedFragments
    case forbiddenFragments
  }

  private enum Kind: String, Decodable {
    case rewrite
    case unchanged
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .kind) {
    case .rewrite:
      self = try .rewrite(
        protectedFragments: container.decodeIfPresent(
          [String].self,
          forKey: .protectedFragments
        ) ?? [],
        forbiddenFragments: container.decodeIfPresent(
          [String].self,
          forKey: .forbiddenFragments
        ) ?? []
      )
    case .unchanged:
      self = .unchanged
    }
  }
}

public enum SentenceRewriteCorpusLoader {
  public static func loadBundled() throws -> SentenceRewriteCorpus {
    guard
      let url = Bundle.module.url(
        forResource: "sentence-rewrite-corpus-v1",
        withExtension: "json"
      )
    else {
      throw CocoaError(.fileNoSuchFile)
    }

    return try JSONDecoder().decode(
      SentenceRewriteCorpus.self,
      from: Data(contentsOf: url)
    )
  }
}
