import Foundation

struct BearCLICommandResult: Equatable {
  let status: Int32
  let standardOutput: Data

  init(status: Int32, standardOutput: Data = Data()) {
    self.status = status
    self.standardOutput = standardOutput
  }
}

protocol BearCLICommandRunning {
  func run(
    executableURL: URL,
    arguments: [String]
  ) throws -> BearCLICommandResult
}

struct ProcessBearCLICommandRunner: BearCLICommandRunning {
  func run(
    executableURL: URL,
    arguments: [String]
  ) throws -> BearCLICommandResult {
    let process = Process()
    let standardOutput = Pipe()
    process.executableURL = executableURL
    process.arguments = arguments
    process.standardOutput = standardOutput
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    return BearCLICommandResult(
      status: process.terminationStatus,
      standardOutput: standardOutput.fileHandleForReading.readDataToEndOfFile()
    )
  }
}

enum BearLiveFixtureLauncherError: Error, Equatable {
  case searchFailed(status: Int32)
  case invalidSearchResponse
  case fixtureMissing
  case fixtureAmbiguous(count: Int)
  case openFailed(status: Int32)
}

struct BearLiveFixtureLauncher {
  static let defaultTitle = "Typover Bear Phase 2 — 2026-07-25"
  static let defaultExecutableURL = URL(
    fileURLWithPath: "/Applications/Bear.app/Contents/MacOS/bearcli"
  )

  private let title: String
  private let executableURL: URL
  private let runner: any BearCLICommandRunning

  init(
    title: String = ProcessInfo.processInfo.environment[
      "TYPOVER_LIVE_BEAR_FIXTURE_TITLE"
    ] ?? BearLiveFixtureLauncher.defaultTitle,
    executableURL: URL = ProcessInfo.processInfo.environment[
      "TYPOVER_BEARCLI_PATH"
    ].map(URL.init(fileURLWithPath:))
      ?? BearLiveFixtureLauncher.defaultExecutableURL,
    runner: any BearCLICommandRunning = ProcessBearCLICommandRunner()
  ) {
    self.title = title
    self.executableURL = executableURL
    self.runner = runner
  }

  @discardableResult
  func openStableNote() throws -> String {
    let search = try runner.run(
      executableURL: executableURL,
      arguments: [
        "search",
        "@title \"\(title)\"",
        "--format", "json",
        "--fields", "id,title",
      ]
    )
    guard search.status == 0 else {
      throw BearLiveFixtureLauncherError.searchFailed(status: search.status)
    }
    guard
      let notes = try? JSONDecoder().decode(
        [BearLiveFixtureNote].self,
        from: search.standardOutput
      )
    else {
      throw BearLiveFixtureLauncherError.invalidSearchResponse
    }

    let exactMatches = notes.filter { $0.title == title }
    guard !exactMatches.isEmpty else {
      throw BearLiveFixtureLauncherError.fixtureMissing
    }
    guard exactMatches.count == 1, let note = exactMatches.first else {
      throw BearLiveFixtureLauncherError.fixtureAmbiguous(
        count: exactMatches.count
      )
    }

    let open = try runner.run(
      executableURL: executableURL,
      arguments: ["open", note.id, "--edit"]
    )
    guard open.status == 0 else {
      throw BearLiveFixtureLauncherError.openFailed(status: open.status)
    }
    return note.id
  }
}

private struct BearLiveFixtureNote: Decodable {
  let id: String
  let title: String
}
