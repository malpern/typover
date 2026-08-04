import Foundation
import Observation

public enum ContextualCorrectionScope: String, Codable, CaseIterable, Equatable,
  Sendable
{
  case careful
  case comprehensive
}

public enum ContextualCorrectionModel: String, Codable, CaseIterable, Equatable,
  Sendable
{
  case apple
  case openAI = "openai"
  case anthropic
}

@MainActor
@Observable
public final class CorrectionBehaviorSettings {
  private enum Key {
    static let contextualScope = "contextual-correction-scope"
    static let allowsSentenceRewrites = "allows-sentence-rewrites"
    static let contextualModel = "contextual-correction-model"
    static let bearAutomaticCorrectionEnabled =
      "bear-automatic-correction-enabled"
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

  public var contextualModel: ContextualCorrectionModel {
    didSet {
      defaults.set(contextualModel.rawValue, forKey: Key.contextualModel)
    }
  }

  public var bearAutomaticCorrectionEnabled: Bool {
    didSet {
      defaults.set(
        bearAutomaticCorrectionEnabled,
        forKey: Key.bearAutomaticCorrectionEnabled
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
    self.contextualModel =
      defaults.string(forKey: Key.contextualModel)
      .flatMap(ContextualCorrectionModel.init(rawValue:))
      ?? .apple
    self.bearAutomaticCorrectionEnabled = defaults.bool(
      forKey: Key.bearAutomaticCorrectionEnabled
    )
  }
}
