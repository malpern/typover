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

public enum CorrectionMarkVisibility: String, Codable, CaseIterable, Equatable,
  Sendable
{
  case briefAndContextual = "brief-and-contextual"
  case alwaysVisible = "always-visible"
}

/// The shared quiet-mark timing used by every Typover writing surface.
public enum CorrectionMarkTiming {
  public static let visibleMilliseconds = 1_500
  public static let fadeMilliseconds = 120

  public static let visibleTimeInterval =
    TimeInterval(visibleMilliseconds) / 1_000
  public static let fadeTimeInterval =
    TimeInterval(fadeMilliseconds) / 1_000
}

@MainActor
@Observable
public final class CorrectionBehaviorSettings {
  private enum Key {
    static let contextualScope = "contextual-correction-scope"
    static let allowsSentenceRewrites = "allows-sentence-rewrites"
    static let contextualModel = "contextual-correction-model"
    static let correctionMarkVisibility = "correction-mark-visibility"
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

  public var correctionMarkVisibility: CorrectionMarkVisibility {
    didSet {
      defaults.set(
        correctionMarkVisibility.rawValue,
        forKey: Key.correctionMarkVisibility
      )
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
    self.correctionMarkVisibility =
      defaults.string(forKey: Key.correctionMarkVisibility)
      .flatMap(CorrectionMarkVisibility.init(rawValue:))
      ?? .briefAndContextual
    self.bearAutomaticCorrectionEnabled = defaults.bool(
      forKey: Key.bearAutomaticCorrectionEnabled
    )
  }
}
