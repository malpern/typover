import Foundation
import Testing

@testable import TypoverApp

@Suite("Bear private diagnostics")
struct BearPrivateDiagnosticsStoreTests {
  @Test("Content-free events discard words and bounded context")
  func contentFreeEvents() {
    #expect(
      BearPrivateDiagnosticsStore.contentFreeEvent(
        from: "outcome=deferredApplied original=\"teh\" replacement=\"the\""
      ) == "outcome=deferredApplied"
    )
    #expect(
      BearPrivateDiagnosticsStore.contentFreeEvent(
        from: "baseline snapshot={leading=\"private writing\"}"
      ) == "baseline"
    )
    #expect(
      BearPrivateDiagnosticsStore.contentFreeEvent(
        from: "input intent=completionBoundary(\" \" )"
      ) == "input=completionBoundary"
    )
  }

  @Test("Disabled diagnostics create no file")
  func disabled() async throws {
    let fixture = try PrivateDiagnosticsFixture()
    fixture.store.record("outcome=noSuggestion word=\"synthetic\"")

    #expect(await fixture.store.size() == 0)
  }

  @Test("Default diagnostic export is content-free")
  func contentFreeExport() async throws {
    let fixture = try PrivateDiagnosticsFixture()
    fixture.defaults.set(
      true,
      forKey: BearPrivateDiagnosticsConfiguration.enabledDefaultsKey
    )
    fixture.store.record("outcome=noSuggestion word=\"synthetic\"")
    try await fixture.store.export(to: fixture.exportURL)

    let exported = try String(contentsOf: fixture.exportURL, encoding: .utf8)
    #expect(exported.contains("outcome=noSuggestion"))
    #expect(!exported.contains("synthetic"))
    #expect(exported.contains("boundedWriting") == false)
  }

  @Test("Including bounded writing is a separate explicit choice")
  func boundedWritingExport() async throws {
    let fixture = try PrivateDiagnosticsFixture()
    fixture.defaults.set(
      true,
      forKey: BearPrivateDiagnosticsConfiguration.enabledDefaultsKey
    )
    fixture.defaults.set(
      true,
      forKey: BearPrivateDiagnosticsConfiguration.includesWritingDefaultsKey
    )
    fixture.store.record("outcome=noSuggestion word=\"synthetic\"")
    try await fixture.store.export(to: fixture.exportURL)

    let exported = try String(contentsOf: fixture.exportURL, encoding: .utf8)
    #expect(exported.contains("synthetic"))
    try await fixture.store.delete()
    #expect(await fixture.store.size() == 0)
  }
}

private final class PrivateDiagnosticsFixture: @unchecked Sendable {
  let defaults: UserDefaults
  let store: BearPrivateDiagnosticsStore
  let exportURL: URL
  private let directory: URL
  private let defaultsName: String

  init() throws {
    defaultsName = "BearPrivateDiagnosticsStoreTests.\(UUID().uuidString)"
    defaults = try #require(UserDefaults(suiteName: defaultsName))
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let traceURL = directory.appendingPathComponent("trace.jsonl")
    exportURL = directory.appendingPathComponent("export.jsonl")
    store = BearPrivateDiagnosticsStore(
      defaults: defaults,
      fileURL: traceURL
    )
  }

  deinit {
    defaults.removePersistentDomain(forName: defaultsName)
    try? FileManager.default.removeItem(at: directory)
  }
}
