import Foundation
import Observation

public enum ContextualCorrectionScope: String, Codable, CaseIterable, Equatable,
  Sendable
{
  case careful
  case comprehensive
}

@MainActor
@Observable
public final class CorrectionBehaviorSettings {
  private enum Key {
    static let contextualScope = "contextual-correction-scope"
    static let allowsSentenceRewrites = "allows-sentence-rewrites"
  }

  private let defaults: UserDefaults

  public var contextualScope: ContextualCorrectionScope {
    didSet {
      defaults.set(contextualScope.rawValue, forKey: Key.contextualScope)
    }
  }

  public var allowsSentenceRewrites: Bool {
    didSet {
      defaults.set(
        allowsSentenceRewrites,
        forKey: Key.allowsSentenceRewrites
      )
    }
  }

  public convenience init() {
    self.init(defaults: .standard)
  }

  public init(defaults: UserDefaults) {
    self.defaults = defaults
    self.contextualScope =
      defaults.string(forKey: Key.contextualScope)
      .flatMap(ContextualCorrectionScope.init(rawValue:))
      ?? .careful
    self.allowsSentenceRewrites = defaults.bool(
      forKey: Key.allowsSentenceRewrites
    )
  }
}
