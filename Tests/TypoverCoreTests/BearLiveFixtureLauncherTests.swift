import Foundation
import Testing

@Suite("Bear live fixture launcher")
struct BearLiveFixtureLauncherTests {
  @Test("The exact disposable note is opened by stable identity")
  func opensExactFixtureByID() throws {
    let runner = StubBearCLICommandRunner(
      results: [
        result(
          json:
            """
            [
              {"id":"wrong","title":"Typover Bear Phase 2"},
              {"id":"fixture-id","title":"Typover fixture"}
            ]
            """
        ),
        BearCLICommandResult(status: 0),
      ]
    )
    let launcher = BearLiveFixtureLauncher(
      title: "Typover fixture",
      executableURL: URL(fileURLWithPath: "/test/bearcli"),
      runner: runner
    )

    #expect(try launcher.openStableNote() == "fixture-id")
    #expect(
      runner.calls.map(\.arguments) == [
        [
          "search", "@title \"Typover fixture\"",
          "--format", "json", "--fields", "id,title",
        ],
        ["open", "fixture-id", "--edit"],
      ]
    )
  }

  @Test("A fuzzy title result cannot stand in for the fixture")
  func refusesFuzzyTitleMatch() {
    let runner = StubBearCLICommandRunner(
      results: [
        result(
          json: "[{\"id\":\"nearby\",\"title\":\"Typover fixture old\"}]"
        )
      ]
    )
    let launcher = launcher(runner: runner)

    #expect(throws: BearLiveFixtureLauncherError.fixtureMissing) {
      try launcher.openStableNote()
    }
    #expect(runner.calls.count == 1)
  }

  @Test("Duplicate exact fixtures fail closed")
  func refusesAmbiguousFixtures() {
    let runner = StubBearCLICommandRunner(
      results: [
        result(
          json:
            """
            [
              {"id":"one","title":"Typover fixture"},
              {"id":"two","title":"Typover fixture"}
            ]
            """
        )
      ]
    )
    let launcher = launcher(runner: runner)

    #expect(
      throws: BearLiveFixtureLauncherError.fixtureAmbiguous(count: 2)
    ) {
      try launcher.openStableNote()
    }
    #expect(runner.calls.count == 1)
  }

  @Test("Malformed and failed searches remain distinct")
  func reportsSearchFailures() {
    let failedRunner = StubBearCLICommandRunner(
      results: [BearCLICommandResult(status: 7)]
    )
    #expect(
      throws: BearLiveFixtureLauncherError.searchFailed(status: 7)
    ) {
      try launcher(runner: failedRunner).openStableNote()
    }

    let malformedRunner = StubBearCLICommandRunner(
      results: [
        BearCLICommandResult(
          status: 0,
          standardOutput: Data("not-json".utf8)
        )
      ]
    )
    #expect(throws: BearLiveFixtureLauncherError.invalidSearchResponse) {
      try launcher(runner: malformedRunner).openStableNote()
    }
  }

  @Test("A failed direct open is reported")
  func reportsOpenFailure() {
    let runner = StubBearCLICommandRunner(
      results: [
        result(
          json: "[{\"id\":\"fixture-id\",\"title\":\"Typover fixture\"}]"
        ),
        BearCLICommandResult(status: 9),
      ]
    )

    #expect(
      throws: BearLiveFixtureLauncherError.openFailed(status: 9)
    ) {
      try launcher(runner: runner).openStableNote()
    }
  }

  private func launcher(
    runner: StubBearCLICommandRunner
  ) -> BearLiveFixtureLauncher {
    BearLiveFixtureLauncher(
      title: "Typover fixture",
      executableURL: URL(fileURLWithPath: "/test/bearcli"),
      runner: runner
    )
  }

  private func result(json: String) -> BearCLICommandResult {
    BearCLICommandResult(
      status: 0,
      standardOutput: Data(json.utf8)
    )
  }
}

private final class StubBearCLICommandRunner: BearCLICommandRunning {
  struct Call: Equatable {
    let executableURL: URL
    let arguments: [String]
  }

  private var results: [BearCLICommandResult]
  private(set) var calls: [Call] = []

  init(results: [BearCLICommandResult]) {
    self.results = results
  }

  func run(
    executableURL: URL,
    arguments: [String]
  ) throws -> BearCLICommandResult {
    calls.append(Call(executableURL: executableURL, arguments: arguments))
    return results.removeFirst()
  }
}
