import Foundation

public struct CorrectionCorpus: Decodable, Sendable {
  public let schemaVersion: Int
  public let baseline: CorrectionCorpusBaseline
  public let cases: [CorrectionCorpusCase]

  public init(
    schemaVersion: Int,
    baseline: CorrectionCorpusBaseline,
    cases: [CorrectionCorpusCase]
  ) {
    self.schemaVersion = schemaVersion
    self.baseline = baseline
    self.cases = cases
  }
}

public struct CorrectionCorpusBaseline: Decodable, Sendable {
  public let platform: String
  public let defaultLanguage: String
  public let notes: String

  public init(
    platform: String,
    defaultLanguage: String,
    notes: String
  ) {
    self.platform = platform
    self.defaultLanguage = defaultLanguage
    self.notes = notes
  }
}

public struct CorrectionCorpusCase: Decodable, Sendable {
  public let id: String
  public let category: String
  public let word: String
  public let language: String?
  public let reviewStatus: CorrectionCorpusReviewStatus
  public let expectation: CorrectionCorpusExpectation

  public init(
    id: String,
    category: String,
    word: String,
    language: String? = nil,
    reviewStatus: CorrectionCorpusReviewStatus,
    expectation: CorrectionCorpusExpectation
  ) {
    self.id = id
    self.category = category
    self.word = word
    self.language = language
    self.reviewStatus = reviewStatus
    self.expectation = expectation
  }
}

public enum CorrectionCorpusReviewStatus: String, Codable, Sendable {
  case approved
  case provisional
}

public enum CorrectionCorpusExpectation: Equatable, Sendable {
  case correction(String)
  case unchanged
}

extension CorrectionCorpusExpectation: Decodable {
  private enum CodingKeys: String, CodingKey {
    case kind
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
        container.decode(String.self, forKey: .replacement)
      )
    case .unchanged:
      self = .unchanged
    }
  }
}

public enum CorrectionCorpusLoader {
  public static func loadBundled() throws -> CorrectionCorpus {
    guard
      let url = Bundle.module.url(
        forResource: "correction-corpus-v1",
        withExtension: "json"
      )
    else {
      throw CocoaError(.fileNoSuchFile)
    }

    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(CorrectionCorpus.self, from: data)
  }
}
