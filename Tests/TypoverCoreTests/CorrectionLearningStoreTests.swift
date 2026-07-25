import Foundation
import Testing

@testable import TypoverCore

@MainActor
struct CorrectionLearningStoreTests {
  @Test("A chosen alternative is preferred for the same typo and language")
  func remembersPreferredReplacement() throws {
    let fixture = makeFixture()
    defer { fixture.remove() }
    let store = CorrectionLearningStore(fileURL: fixture.fileURL)
    let proposal = makeProposal(original: "teh", replacement: "the")

    store.recordApplied(proposal)
    store.recordPreferred(
      "ten",
      for: proposal,
      outcome: .alternativeChosen
    )

    let nextProposal = try #require(
      store.applyingPreference(
        to: makeProposal(original: "teh", replacement: "the")
      )
    )
    #expect(nextProposal.correction.replacement == "ten")
    #expect(nextProposal.alternatives.first == "the")
    #expect(nextProposal.source == .rememberedPreference)
  }

  @Test("Change Back suppresses that exact typo and language")
  func remembersSuppression() {
    let fixture = makeFixture()
    defer { fixture.remove() }
    let store = CorrectionLearningStore(fileURL: fixture.fileURL)
    let proposal = makeProposal(original: "teh", replacement: "the")

    store.recordApplied(proposal)
    store.recordReverted(proposal)

    #expect(store.applyingPreference(to: proposal) == nil)
    #expect(
      store.applyingPreference(
        to: makeProposal(
          original: "teh",
          replacement: "the",
          language: "fr"
        )
      ) != nil
    )
  }

  @Test("A manual edit becomes the next preferred replacement")
  func remembersManualEdit() throws {
    let fixture = makeFixture()
    defer { fixture.remove() }
    let store = CorrectionLearningStore(fileURL: fixture.fileURL)
    let proposal = makeProposal(original: "teh", replacement: "the")

    store.recordApplied(proposal)
    store.recordManualEdit("tech", for: proposal)

    let nextProposal = try #require(
      store.applyingPreference(
        to: makeProposal(original: "teh", replacement: "the")
      )
    )
    #expect(nextProposal.correction.replacement == "tech")
  }

  @Test("Statistics count unique corrected words and override outcomes")
  func calculatesStatistics() {
    let fixture = makeFixture()
    defer { fixture.remove() }
    let store = CorrectionLearningStore(fileURL: fixture.fileURL)
    let alternative = makeProposal(original: "teh", replacement: "the")
    let reverted = makeProposal(original: "wrod", replacement: "word")
    let unresolved = makeProposal(original: "speling", replacement: "spelling")

    store.recordApplied(alternative)
    store.recordApplied(reverted)
    store.recordApplied(unresolved)
    store.recordPreferred(
      "ten",
      for: alternative,
      outcome: .alternativeChosen
    )
    store.recordKept(alternative)
    store.recordReverted(reverted)

    let statistics = store.statistics()
    #expect(statistics.correctionsApplied == 3)
    #expect(statistics.kept == 1)
    #expect(statistics.reverted == 1)
    #expect(statistics.alternativesChosen == 1)
    #expect(statistics.manuallyEdited == 0)
    #expect(statistics.overriddenCorrections == 2)
    #expect(statistics.unresolvedCorrections == 1)
    #expect(statistics.overrideRate == 2.0 / 3.0)
  }

  @Test("Preferences and statistics survive a store relaunch")
  func persistsLearning() throws {
    let fixture = makeFixture()
    defer { fixture.remove() }
    let proposal = makeProposal(original: "teh", replacement: "the")

    let firstStore = CorrectionLearningStore(fileURL: fixture.fileURL)
    firstStore.recordApplied(proposal)
    firstStore.recordPreferred(
      "ten",
      for: proposal,
      outcome: .alternativeChosen
    )

    let relaunchedStore = CorrectionLearningStore(fileURL: fixture.fileURL)
    let remembered = try #require(
      relaunchedStore.applyingPreference(
        to: makeProposal(original: "teh", replacement: "the")
      )
    )

    #expect(remembered.correction.replacement == "ten")
    #expect(relaunchedStore.statistics().correctionsApplied == 1)
    #expect(relaunchedStore.statistics().overriddenCorrections == 1)
  }

  @Test("Removing a preference restores the engine proposal")
  func removesPreference() throws {
    let fixture = makeFixture()
    defer { fixture.remove() }
    let store = CorrectionLearningStore(fileURL: fixture.fileURL)
    let proposal = makeProposal(original: "teh", replacement: "the")
    store.recordPreferred("ten", for: proposal)

    store.removePreference(for: "teh", language: "en_US")

    let restored = try #require(store.applyingPreference(to: proposal))
    #expect(restored.correction.replacement == "the")
    #expect(restored.source == .appleSpelling)
  }

  @Test("Remembered rules expose stable identifiers and newest-first order")
  func listsRememberedRules() throws {
    let fixture = makeFixture()
    defer { fixture.remove() }
    let store = CorrectionLearningStore(fileURL: fixture.fileURL)
    let first = makeProposal(original: "teh", replacement: "the")
    let second = makeProposal(original: "wrod", replacement: "word")

    store.recordPreferred("the", for: first)
    store.recordReverted(second)

    let rules = store.rememberedRules
    #expect(rules.count == 2)
    #expect(rules[0].original == "wrod")
    #expect(rules[0].preference == .suppressed)
    #expect(rules[1].id.original == "teh")
    #expect(rules[1].id.language == "en_US")
    #expect(rules[1].preference == .preferred("the"))
  }

  @Test("A remembered rule can be removed by its stable identifier")
  func removesRuleByID() throws {
    let fixture = makeFixture()
    defer { fixture.remove() }
    let store = CorrectionLearningStore(fileURL: fixture.fileURL)
    let proposal = makeProposal(original: "teh", replacement: "the")
    store.recordPreferred("the", for: proposal)
    let rule = try #require(store.rememberedRules.first)

    store.removeRule(rule.id)

    #expect(store.rememberedRules.isEmpty)
    #expect(store.preference(for: "teh", language: "en_US") == nil)
  }

  @Test("Statistics and preferences can be reset independently")
  func resetsStoredDataIndependently() {
    let fixture = makeFixture()
    defer { fixture.remove() }
    let store = CorrectionLearningStore(fileURL: fixture.fileURL)
    let proposal = makeProposal(original: "teh", replacement: "the")
    store.recordApplied(proposal)
    store.recordPreferred("the", for: proposal)

    store.resetStatistics()

    #expect(store.statistics().correctionsApplied == 0)
    #expect(store.rememberedRules.count == 1)

    store.resetPreferences()

    #expect(store.statistics().correctionsApplied == 0)
    #expect(store.rememberedRules.isEmpty)
  }

  @Test("Reset all learning clears statistics and remembered rules")
  func resetsAllLearning() {
    let fixture = makeFixture()
    defer { fixture.remove() }
    let store = CorrectionLearningStore(fileURL: fixture.fileURL)
    let proposal = makeProposal(original: "teh", replacement: "the")
    store.recordApplied(proposal)
    store.recordPreferred("the", for: proposal)

    store.resetAllLearning()

    #expect(store.statistics().correctionsApplied == 0)
    #expect(store.rememberedRules.isEmpty)
  }

  private func makeProposal(
    original: String,
    replacement: String,
    language: String = "en_US"
  ) -> CorrectionProposal {
    CorrectionProposal(
      correction: Correction(
        original: original,
        replacement: replacement
      ),
      alternatives: [],
      source: .appleSpelling,
      language: language,
      lookupDuration: .zero
    )
  }

  private func makeFixture() -> StoreFixture {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    return StoreFixture(
      directory: directory,
      fileURL: directory.appendingPathComponent("learning.json")
    )
  }
}

private struct StoreFixture {
  let directory: URL
  let fileURL: URL

  func remove() {
    try? FileManager.default.removeItem(at: directory)
  }
}
