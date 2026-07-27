import Foundation
import Testing

@testable import TypoverCore

@MainActor
struct CorrectionBehaviorSettingsTests {
  @Test("Correction behavior defaults to careful without sentence rewrites")
  func defaultBehavior() throws {
    let fixture = try DefaultsFixture()
    defer { fixture.remove() }

    let settings = CorrectionBehaviorSettings(
      defaults: fixture.defaults
    )

    #expect(settings.contextualScope == .careful)
    #expect(!settings.allowsSentenceRewrites)
    #expect(settings.contextualModel == .apple)
    #expect(!settings.bearAutomaticCorrectionEnabled)
  }

  @Test("Correction scope and sentence rewrite permission persist")
  func persistsBehavior() throws {
    let fixture = try DefaultsFixture()
    defer { fixture.remove() }
    let settings = CorrectionBehaviorSettings(
      defaults: fixture.defaults
    )
    settings.contextualScope = .comprehensive
    settings.allowsSentenceRewrites = true
    settings.contextualModel = .anthropic
    settings.bearAutomaticCorrectionEnabled = true

    let relaunched = CorrectionBehaviorSettings(
      defaults: fixture.defaults
    )

    #expect(relaunched.contextualScope == .comprehensive)
    #expect(relaunched.allowsSentenceRewrites)
    #expect(relaunched.contextualModel == .anthropic)
    #expect(relaunched.bearAutomaticCorrectionEnabled)
  }
}

private struct DefaultsFixture {
  let name: String
  let defaults: UserDefaults

  init() throws {
    name = "CorrectionBehaviorSettingsTests.\(UUID().uuidString)"
    defaults = try #require(UserDefaults(suiteName: name))
  }

  func remove() {
    defaults.removePersistentDomain(forName: name)
  }
}
