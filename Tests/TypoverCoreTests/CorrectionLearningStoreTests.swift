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
    #expect(store.rememberedRules.first?.origin == .implicitLocalEdit)
  }

  @Test("Implicit local edits preserve accents, apostrophes, and punctuation")
  func remembersRichLocalEdits() throws {
    let fixture = makeFixture()
    defer { fixture.remove() }
    let store = CorrectionLearningStore(fileURL: fixture.fileURL)
    let examples = [
      ("dont", "don’t"),
      ("resume", "résumé"),
      ("teh", "the,"),
    ]

    for (original, replacement) in examples {
      let proposal = makeProposal(original: original, replacement: replacement)
      store.recordApplied(proposal)
      store.recordManualEdit(replacement, for: proposal)

      let remembered = try #require(
        store.applyingPreference(
          to: makeProposal(original: original, replacement: original)
        )
      )
      #expect(remembered.correction.replacement == replacement)
    }
  }

  @Test("Typing onward into a corrected word is not learned as an edit")
  func doesNotLearnTypedOnwardWord() throws {
    let fixture = makeFixture()
    defer { fixture.remove() }
    let store = CorrectionLearningStore(fileURL: fixture.fileURL)
    let proposal = makeProposal(original: "teh", replacement: "the")

    store.recordApplied(proposal)
    // `the` was applied, the writer kept typing, and the characters joined the
    // corrected word. That is not a choice of `theteh` as the replacement.
    store.recordManualEdit("theteh", for: proposal)

    #expect(store.rememberedRules.isEmpty)
    #expect(store.statistics().manuallyEdited == 1)
    let next = try #require(store.applyingPreference(to: proposal))
    #expect(next.correction.replacement == "the")
    #expect(next.source == .appleSpelling)
  }

  @Test("An explicit choice is still free to expand beyond an inferred edit")
  func explicitChoiceIsNotBoundedLikeAnInferredEdit() throws {
    let fixture = makeFixture()
    defer { fixture.remove() }
    let store = CorrectionLearningStore(fileURL: fixture.fileURL)
    let proposal = makeProposal(original: "teh", replacement: "the")

    store.recordPreferred("theteh", for: proposal, outcome: .alternativeChosen)

    let remembered = try #require(store.applyingPreference(to: proposal))
    #expect(remembered.correction.replacement == "theteh")
  }

  @Test("An ambiguous document edit counts as an override but is not learned")
  func doesNotRememberAmbiguousDocumentEdit() throws {
    let fixture = makeFixture()
    defer { fixture.remove() }
    let store = CorrectionLearningStore(fileURL: fixture.fileURL)
    let proposal = makeProposal(original: "teh", replacement: "the")

    store.recordApplied(proposal)
    store.recordManualEdit("Start Finish remains.", for: proposal)

    #expect(store.rememberedRules.isEmpty)
    #expect(store.statistics().manuallyEdited == 1)
    #expect(store.statistics().overriddenCorrections == 1)
    let nextProposal = try #require(store.applyingPreference(to: proposal))
    #expect(nextProposal.correction.replacement == "the")
    #expect(nextProposal.source == .appleSpelling)
  }

  @Test("An explicit choice may intentionally expand to a phrase")
  func remembersExplicitPhraseChoice() throws {
    let fixture = makeFixture()
    defer { fixture.remove() }
    let store = CorrectionLearningStore(fileURL: fixture.fileURL)
    let proposal = makeProposal(original: "addr", replacement: "address")

    store.recordPreferred("123 Main Street", for: proposal)

    let remembered = try #require(store.applyingPreference(to: proposal))
    #expect(remembered.correction.replacement == "123 Main Street")
    #expect(remembered.source == .rememberedPreference)
    #expect(store.rememberedRules.first?.origin == .explicitChoice)
  }

  @Test("A manual mapping produces a correction without an engine proposal")
  func appliesManualMappingDirectly() throws {
    let fixture = makeFixture()
    defer { fixture.remove() }
    let store = CorrectionLearningStore(fileURL: fixture.fileURL)
    let mapping = try ManualCorrectionMapping(
      original: " brb ",
      replacement: " be right back ",
      language: nil
    )

    store.addManualMapping(mapping)

    let proposal = try #require(
      store.manualProposal(for: "brb", language: "en_US")
    )
    #expect(proposal.correction.replacement == "be right back")
    #expect(proposal.source == .rememberedPreference)
    #expect(proposal.language == "en_US")
    #expect(store.rememberedRules.first?.origin == .manualEntry)

    let relaunched = CorrectionLearningStore(fileURL: fixture.fileURL)
    #expect(
      relaunched.manualProposal(for: "brb", language: "fr")?
        .correction.replacement == "be right back"
    )
  }

  @Test("Manual mapping validation rejects ambiguous empty and multiline input")
  func validatesManualMappings() throws {
    #expect(throws: ManualCorrectionMapping.ValidationError.emptyOriginal) {
      try ManualCorrectionMapping(original: "  ", replacement: "text")
    }
    #expect(throws: ManualCorrectionMapping.ValidationError.emptyReplacement) {
      try ManualCorrectionMapping(original: "text", replacement: "  ")
    }
    #expect(throws: ManualCorrectionMapping.ValidationError.unchanged) {
      try ManualCorrectionMapping(original: "text", replacement: "text")
    }
    #expect(
      throws: ManualCorrectionMapping.ValidationError.unsupportedLineBreak
    ) {
      try ManualCorrectionMapping(
        original: "one\ntwo",
        replacement: "three"
      )
    }
    #expect(throws: ManualCorrectionMapping.ValidationError.originalTooLong) {
      try ManualCorrectionMapping(
        original: String(repeating: "a", count: 257),
        replacement: "text"
      )
    }
    #expect(
      throws: ManualCorrectionMapping.ValidationError.replacementTooLong
    ) {
      try ManualCorrectionMapping(
        original: "text",
        replacement: String(repeating: "a", count: 1_025)
      )
    }
  }

  @Test("A language-specific manual mapping overrides an all-language mapping")
  func resolvesManualMappingLanguageScope() throws {
    let fixture = makeFixture()
    defer { fixture.remove() }
    let store = CorrectionLearningStore(fileURL: fixture.fileURL)
    store.addManualMapping(
      try ManualCorrectionMapping(
        original: "colour",
        replacement: "color"
      )
    )
    store.addManualMapping(
      try ManualCorrectionMapping(
        original: "colour",
        replacement: "couleur",
        language: "fr"
      )
    )

    #expect(
      store.manualProposal(for: "colour", language: "en_US")?
        .correction.replacement == "color"
    )
    #expect(
      store.manualProposal(for: "colour", language: "fr")?
        .correction.replacement == "couleur"
    )
    #expect(store.rememberedRules.count == 2)
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

  @Test("Statistics separate private activity by correction source")
  func calculatesSourceStatistics() throws {
    let fixture = makeFixture()
    defer { fixture.remove() }
    let store = CorrectionLearningStore(fileURL: fixture.fileURL)
    let spelling = makeProposal(
      original: "teh",
      replacement: "the",
      source: .appleSpelling,
      lookupDuration: .milliseconds(8)
    )
    let contextual = makeProposal(
      original: "Their",
      replacement: "They're",
      source: .appleIntelligence,
      lookupDuration: .milliseconds(1_250)
    )

    store.recordApplied(spelling)
    store.recordApplied(contextual)
    store.recordReverted(contextual)

    let sources = store.statisticsBySource()
    let spellingStatistics = try #require(
      sources.first(where: { $0.source == .appleSpelling })
    )
    let contextualStatistics = try #require(
      sources.first(where: { $0.source == .appleIntelligence })
    )

    #expect(spellingStatistics.correctionsApplied == 1)
    #expect(spellingStatistics.overriddenCorrections == 0)
    #expect(spellingStatistics.medianLookupMilliseconds == 8)
    #expect(contextualStatistics.correctionsApplied == 1)
    #expect(contextualStatistics.overriddenCorrections == 1)
    #expect(contextualStatistics.overrideRate == 1)
    #expect(contextualStatistics.p95LookupMilliseconds == 1_250)
  }

  @Test("Learning files from before source statistics still load")
  func migratesLegacyActivity() throws {
    let fixture = makeFixture()
    defer { fixture.remove() }
    try FileManager.default.createDirectory(
      at: fixture.directory,
      withIntermediateDirectories: true
    )
    let legacyState = LegacyPersistedState(
      preferences: [],
      activities: [
        LegacyActivity(
          correctionID: UUID(),
          appliedAt: Date(),
          outcomes: [.kept]
        )
      ]
    )
    try JSONEncoder().encode(legacyState).write(
      to: fixture.fileURL,
      options: .atomic
    )

    let store = CorrectionLearningStore(fileURL: fixture.fileURL)

    #expect(store.statistics().correctionsApplied == 1)
    #expect(store.statistics().kept == 1)
    #expect(store.statisticsBySource().isEmpty)
  }

  @Test("An unsafe legacy preference is removed during migration")
  func removesUnsafeLegacyPreference() throws {
    let fixture = makeFixture()
    defer { fixture.remove() }
    try FileManager.default.createDirectory(
      at: fixture.directory,
      withIntermediateDirectories: true
    )
    let legacyState = LegacyPersistedState(
      preferences: [
        LegacyPreferenceEntry(
          key: LegacyPreferenceKey(original: "teh", language: "en_US"),
          preference: .preferred("Start Finish remains."),
          updatedAt: Date()
        )
      ],
      activities: []
    )
    try JSONEncoder().encode(legacyState).write(
      to: fixture.fileURL,
      options: .atomic
    )

    let store = CorrectionLearningStore(fileURL: fixture.fileURL)

    #expect(store.rememberedRules.isEmpty)
    let proposal = try #require(
      store.applyingPreference(
        to: makeProposal(original: "teh", replacement: "the")
      )
    )
    #expect(proposal.correction.replacement == "the")
    #expect(proposal.source == .appleSpelling)
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
    #expect(rules[0].origin == .changedBack)
    #expect(rules[1].id.original == "teh")
    #expect(rules[1].id.language == "en_US")
    #expect(rules[1].preference == .preferred("the"))
    #expect(rules[1].origin == .explicitChoice)
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
    language: String = "en_US",
    source: CorrectionSource = .appleSpelling,
    lookupDuration: Duration = .zero
  ) -> CorrectionProposal {
    CorrectionProposal(
      correction: Correction(
        original: original,
        replacement: replacement
      ),
      alternatives: [],
      source: source,
      language: language,
      lookupDuration: lookupDuration
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

private struct LegacyPersistedState: Codable {
  let preferences: [LegacyPreferenceEntry]
  let activities: [LegacyActivity]
}

private struct LegacyPreferenceKey: Codable {
  let original: String
  let language: String
}

private struct LegacyPreferenceEntry: Codable {
  let key: LegacyPreferenceKey
  let preference: RememberedCorrectionPreference
  let updatedAt: Date
}

private struct LegacyActivity: Codable {
  let correctionID: UUID
  let appliedAt: Date
  let outcomes: Set<CorrectionOutcome>
}

private struct StoreFixture {
  let directory: URL
  let fileURL: URL

  func remove() {
    try? FileManager.default.removeItem(at: directory)
  }
}
