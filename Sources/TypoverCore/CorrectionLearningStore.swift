import Foundation
import Observation

public enum RememberedCorrectionPreference: Codable, Equatable, Sendable {
  case preferred(String)
  case suppressed
}

public enum RememberedCorrectionOrigin: String, Codable, Equatable, Sendable {
  case explicitChoice
  case implicitLocalEdit
  case changedBack
  case legacy
}

public struct RememberedCorrectionRule: Equatable, Identifiable, Sendable {
  public struct ID: Equatable, Hashable, Sendable {
    public let original: String
    public let language: String

    public init(original: String, language: String) {
      self.original = original
      self.language = language
    }
  }

  public let id: ID
  public let original: String
  public let language: String?
  public let preference: RememberedCorrectionPreference
  public let origin: RememberedCorrectionOrigin
  public let updatedAt: Date

  public init(
    original: String,
    language: String?,
    preference: RememberedCorrectionPreference,
    origin: RememberedCorrectionOrigin,
    updatedAt: Date
  ) {
    self.original = original
    self.language = language
    self.preference = preference
    self.origin = origin
    self.updatedAt = updatedAt
    self.id = ID(
      original: original,
      language: language ?? ""
    )
  }
}

public enum CorrectionOutcome: String, Codable, CaseIterable, Sendable {
  case kept
  case reverted
  case alternativeChosen
  case manuallyEdited
}

public struct CorrectionStatistics: Equatable, Sendable {
  public let correctionsApplied: Int
  public let kept: Int
  public let reverted: Int
  public let alternativesChosen: Int
  public let manuallyEdited: Int
  public let overriddenCorrections: Int
  public let unresolvedCorrections: Int

  public init(
    correctionsApplied: Int,
    kept: Int,
    reverted: Int,
    alternativesChosen: Int,
    manuallyEdited: Int,
    overriddenCorrections: Int,
    unresolvedCorrections: Int
  ) {
    self.correctionsApplied = correctionsApplied
    self.kept = kept
    self.reverted = reverted
    self.alternativesChosen = alternativesChosen
    self.manuallyEdited = manuallyEdited
    self.overriddenCorrections = overriddenCorrections
    self.unresolvedCorrections = unresolvedCorrections
  }

  public var overrideRate: Double {
    guard correctionsApplied > 0 else {
      return 0
    }
    return Double(overriddenCorrections) / Double(correctionsApplied)
  }
}

public struct CorrectionSourceStatistics: Equatable, Identifiable, Sendable {
  public var id: CorrectionSource {
    source
  }

  public let source: CorrectionSource
  public let correctionsApplied: Int
  public let overriddenCorrections: Int
  public let medianLookupMilliseconds: Double
  public let p95LookupMilliseconds: Double

  public init(
    source: CorrectionSource,
    correctionsApplied: Int,
    overriddenCorrections: Int,
    medianLookupMilliseconds: Double,
    p95LookupMilliseconds: Double
  ) {
    self.source = source
    self.correctionsApplied = correctionsApplied
    self.overriddenCorrections = overriddenCorrections
    self.medianLookupMilliseconds = medianLookupMilliseconds
    self.p95LookupMilliseconds = p95LookupMilliseconds
  }

  public var overrideRate: Double {
    guard correctionsApplied > 0 else {
      return 0
    }
    return Double(overriddenCorrections) / Double(correctionsApplied)
  }
}

@MainActor
@Observable
public final class CorrectionLearningStore {
  private struct PreferenceKey: Codable, Equatable, Hashable {
    let original: String
    let language: String
  }

  private struct PreferenceEntry: Codable, Equatable {
    let key: PreferenceKey
    var preference: RememberedCorrectionPreference
    var origin: RememberedCorrectionOrigin?
    var updatedAt: Date
  }

  private struct Activity: Codable, Equatable {
    let correctionID: UUID
    let appliedAt: Date
    let source: CorrectionSource?
    let lookupMilliseconds: Double?
    var outcomes: Set<CorrectionOutcome>
  }

  private struct PersistedState: Codable, Equatable {
    var preferences: [PreferenceEntry] = []
    var activities: [Activity] = []
  }

  private let fileURL: URL
  private let fileManager: FileManager
  private var state: PersistedState

  public convenience init() {
    self.init(fileURL: Self.defaultFileURL())
  }

  public init(
    fileURL: URL,
    fileManager: FileManager = .default
  ) {
    self.fileURL = fileURL
    self.fileManager = fileManager
    let loadedState =
      (try? Self.loadState(from: fileURL)) ?? PersistedState()
    let migratedState = Self.migratingLegacyPreferences(in: loadedState)
    self.state = migratedState
    if migratedState != loadedState {
      persist()
    }
  }

  public func preference(
    for original: String,
    language: String?
  ) -> RememberedCorrectionPreference? {
    let key = preferenceKey(original: original, language: language)
    return state.preferences.first(where: { $0.key == key })?.preference
  }

  public func applyingPreference(
    to proposal: CorrectionProposal
  ) -> CorrectionProposal? {
    let key = preferenceKey(
      original: proposal.correction.original,
      language: proposal.language
    )
    guard let entry = state.preferences.first(where: { $0.key == key }) else {
      return proposal
    }

    switch entry.preference {
    case .suppressed:
      return nil
    case .preferred(let replacement):
      guard
        entry.origin != .implicitLocalEdit
          || Self.isSafeImplicitReplacement(replacement)
      else {
        state.preferences.removeAll(where: { $0.key == key })
        persist()
        return proposal
      }
      var seen = Set([proposal.correction.original, replacement])
      let alternatives =
        ([proposal.correction.replacement] + proposal.alternatives)
        .filter { seen.insert($0).inserted }

      return CorrectionProposal(
        correction: Correction(
          id: proposal.correction.id,
          original: proposal.correction.original,
          replacement: replacement,
          createdAt: proposal.correction.createdAt
        ),
        alternatives: alternatives,
        source: .rememberedPreference,
        language: proposal.language,
        lookupDuration: proposal.lookupDuration
      )
    }
  }

  public func recordApplied(_ proposal: CorrectionProposal) {
    guard
      !state.activities.contains(where: {
        $0.correctionID == proposal.correction.id
      })
    else {
      return
    }

    state.activities.append(
      Activity(
        correctionID: proposal.correction.id,
        appliedAt: proposal.correction.createdAt,
        source: proposal.source,
        lookupMilliseconds: Self.milliseconds(
          proposal.lookupDuration
        ),
        outcomes: []
      )
    )
    persist()
  }

  public func recordKept(_ proposal: CorrectionProposal) {
    record(.kept, for: proposal.correction.id)
  }

  public func recordOutcome(
    _ outcome: CorrectionOutcome,
    for proposal: CorrectionProposal
  ) {
    record(outcome, for: proposal.correction.id)
  }

  public func recordReverted(_ proposal: CorrectionProposal) {
    setPreference(
      .suppressed,
      origin: .changedBack,
      for: proposal.correction.original,
      language: proposal.language
    )
    record(.reverted, for: proposal.correction.id)
  }

  public func recordPreferred(
    _ replacement: String,
    for proposal: CorrectionProposal,
    outcome: CorrectionOutcome? = nil
  ) {
    setPreference(
      .preferred(replacement),
      origin: .explicitChoice,
      for: proposal.correction.original,
      language: proposal.language
    )
    if let outcome {
      record(outcome, for: proposal.correction.id)
    }
  }

  public func recordManualEdit(
    _ replacement: String?,
    for proposal: CorrectionProposal
  ) {
    if let replacement, !replacement.isEmpty {
      if replacement == proposal.correction.original {
        setPreference(
          .suppressed,
          origin: .implicitLocalEdit,
          for: proposal.correction.original,
          language: proposal.language
        )
      } else if Self.isSafeImplicitReplacement(replacement) {
        setPreference(
          .preferred(replacement),
          origin: .implicitLocalEdit,
          for: proposal.correction.original,
          language: proposal.language
        )
      }
    }
    record(.manuallyEdited, for: proposal.correction.id)
  }

  public func removePreference(
    for original: String,
    language: String?
  ) {
    let key = preferenceKey(original: original, language: language)
    let originalCount = state.preferences.count
    state.preferences.removeAll(where: { $0.key == key })
    if state.preferences.count != originalCount {
      persist()
    }
  }

  public var rememberedRules: [RememberedCorrectionRule] {
    state.preferences
      .map { entry in
        RememberedCorrectionRule(
          original: entry.key.original,
          language: entry.key.language.isEmpty ? nil : entry.key.language,
          preference: entry.preference,
          origin: entry.origin ?? .legacy,
          updatedAt: entry.updatedAt
        )
      }
      .sorted { left, right in
        if left.updatedAt != right.updatedAt {
          return left.updatedAt > right.updatedAt
        }
        if left.original != right.original {
          return left.original.localizedStandardCompare(right.original)
            == .orderedAscending
        }
        return (left.language ?? "") < (right.language ?? "")
      }
  }

  public func removeRule(_ id: RememberedCorrectionRule.ID) {
    removePreference(
      for: id.original,
      language: id.language.isEmpty ? nil : id.language
    )
  }

  public func resetPreferences() {
    guard !state.preferences.isEmpty else {
      return
    }
    state.preferences.removeAll()
    persist()
  }

  public func resetStatistics() {
    guard !state.activities.isEmpty else {
      return
    }
    state.activities.removeAll()
    persist()
  }

  public func resetAllLearning() {
    guard
      !state.preferences.isEmpty
        || !state.activities.isEmpty
    else {
      return
    }
    state = PersistedState()
    persist()
  }

  public func statistics(since startDate: Date? = nil) -> CorrectionStatistics {
    let activities = state.activities.filter { activity in
      startDate.map({ activity.appliedAt >= $0 }) ?? true
    }
    let overrideOutcomes: Set<CorrectionOutcome> = [
      .reverted,
      .alternativeChosen,
      .manuallyEdited,
    ]

    return CorrectionStatistics(
      correctionsApplied: activities.count,
      kept: activities.count(where: { $0.outcomes.contains(.kept) }),
      reverted: activities.count(where: { $0.outcomes.contains(.reverted) }),
      alternativesChosen: activities.count(where: {
        $0.outcomes.contains(.alternativeChosen)
      }),
      manuallyEdited: activities.count(where: {
        $0.outcomes.contains(.manuallyEdited)
      }),
      overriddenCorrections: activities.count(where: {
        !$0.outcomes.isDisjoint(with: overrideOutcomes)
      }),
      unresolvedCorrections: activities.count(where: { $0.outcomes.isEmpty })
    )
  }

  public func statisticsBySource(
    since startDate: Date? = nil
  ) -> [CorrectionSourceStatistics] {
    let activities = state.activities.filter { activity in
      startDate.map({ activity.appliedAt >= $0 }) ?? true
    }
    let overrideOutcomes: Set<CorrectionOutcome> = [
      .reverted,
      .alternativeChosen,
      .manuallyEdited,
    ]

    return CorrectionSource.allCases.compactMap { source in
      let matching = activities.filter { $0.source == source }
      guard !matching.isEmpty else {
        return nil
      }
      let lookupValues = matching.compactMap(\.lookupMilliseconds).sorted()
      return CorrectionSourceStatistics(
        source: source,
        correctionsApplied: matching.count,
        overriddenCorrections: matching.count(where: {
          !$0.outcomes.isDisjoint(with: overrideOutcomes)
        }),
        medianLookupMilliseconds: Self.percentile(
          0.5,
          values: lookupValues
        ),
        p95LookupMilliseconds: Self.percentile(
          0.95,
          values: lookupValues
        )
      )
    }
  }

  private static func defaultFileURL() -> URL {
    if let overridePath = ProcessInfo.processInfo.environment[
      "TYPOVER_LEARNING_STORE_PATH"
    ], !overridePath.isEmpty {
      return URL(fileURLWithPath: overridePath)
    }

    let applicationSupport =
      FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first ?? FileManager.default.temporaryDirectory
    return
      applicationSupport
      .appendingPathComponent("Typover", isDirectory: true)
      .appendingPathComponent("correction-learning.json")
  }

  private static func loadState(from fileURL: URL) throws -> PersistedState {
    let data = try Data(contentsOf: fileURL)
    return try JSONDecoder().decode(PersistedState.self, from: data)
  }

  private static func migratingLegacyPreferences(
    in state: PersistedState
  ) -> PersistedState {
    var migrated = state
    migrated.preferences = state.preferences.compactMap { entry in
      guard entry.origin == nil else {
        return entry
      }

      var migratedEntry = entry
      switch entry.preference {
      case .suppressed:
        migratedEntry.origin = .changedBack
      case .preferred(let replacement):
        guard isSafeImplicitReplacement(replacement) else {
          return nil
        }
        migratedEntry.origin = .legacy
      }
      return migratedEntry
    }
    return migrated
  }

  private static func isSafeImplicitReplacement(_ replacement: String) -> Bool {
    guard
      !replacement.isEmpty,
      replacement.utf16.count <= 64
    else {
      return false
    }

    return replacement.unicodeScalars.allSatisfy { scalar in
      !CharacterSet.whitespacesAndNewlines.contains(scalar)
        && !CharacterSet.controlCharacters.contains(scalar)
    }
  }

  private static func milliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
  }

  private static func percentile(
    _ percentile: Double,
    values: [Double]
  ) -> Double {
    guard !values.isEmpty else {
      return 0
    }
    let index = Int(
      (Double(values.count - 1) * percentile).rounded(.up)
    )
    return values[index]
  }

  private func preferenceKey(
    original: String,
    language: String?
  ) -> PreferenceKey {
    PreferenceKey(
      original: original.precomposedStringWithCanonicalMapping,
      language: language ?? ""
    )
  }

  private func setPreference(
    _ preference: RememberedCorrectionPreference,
    origin: RememberedCorrectionOrigin,
    for original: String,
    language: String?
  ) {
    let key = preferenceKey(original: original, language: language)
    if let index = state.preferences.firstIndex(where: { $0.key == key }) {
      state.preferences[index].preference = preference
      state.preferences[index].origin = origin
      state.preferences[index].updatedAt = Date()
    } else {
      state.preferences.append(
        PreferenceEntry(
          key: key,
          preference: preference,
          origin: origin,
          updatedAt: Date()
        )
      )
    }
    persist()
  }

  private func record(
    _ outcome: CorrectionOutcome,
    for correctionID: UUID
  ) {
    guard
      let index = state.activities.firstIndex(where: {
        $0.correctionID == correctionID
      })
    else {
      return
    }
    let insertion = state.activities[index].outcomes.insert(outcome)
    if insertion.inserted {
      persist()
    }
  }

  private func persist() {
    do {
      try fileManager.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let data = try JSONEncoder().encode(state)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      // Preference learning and statistics must never interrupt typing.
    }
  }
}
