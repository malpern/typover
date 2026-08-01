import AppKit
import Foundation
import TypoverAccessibility
import TypoverHIDTesting

private enum HarnessError: Error, CustomStringConvertible {
  case usage(String)
  case commandFailed(String)
  case invalidJSON(String)
  case unsafeFocus(String)
  case quietTimeout

  var description: String {
    switch self {
    case .usage(let message), .commandFailed(let message),
      .invalidJSON(let message), .unsafeFocus(let message):
      message
    case .quietTimeout:
      "The Mac did not reach three quiet samples before the timeout."
    }
  }
}

private struct FixtureStatus: Codable, Equatable {
  let state: String
  let runId: String?
  let eventCount: Int?
  let reportsSubmitted: Int?
  let transfersCompleted: Int?
  let lateReports: Int?
  let maximumLatenessUs: Int?
  let usbMounted: Bool?
  let wifiConnected: Bool?
  let displayHealthy: Bool?
  let error: String?
  let presentation: FixturePresentationStatus?
}

private struct FixturePresentationStatus: Codable, Equatable {
  let phase: String?
  let result: String?
  let brand: String?
  let title: String?
  let detail: String?
}

private struct HostReadinessSample: Codable, Equatable {
  let timestamp: Date
  let cpuIdlePercent: Double?
  let activeSwiftCompilers: [String]

  var isQuiet: Bool {
    cpuIdlePercent.map { $0 >= 60 } == true && activeSwiftCompilers.isEmpty
  }
}

private struct TypoverTelemetrySummary: Codable {
  let applied: Int
  let rapidTypingCoalesced: Int
  let contextChanged: Int
  let staleBoundaryInput: Int
  let baselineUnavailable: Int
  let learnedSuppression: Int
  let replacementRefused: Int
}

private struct CaseArtifact: Codable {
  let testCase: BearHIDTestCase
  let runID: String
  let startedAt: Date
  let finishedAt: Date
  let focusRemainedValid: Bool
  let baselineCaret: Int
  let finalCaret: Int?
  let baselineDocumentLength: Int
  let finalDocumentLength: Int?
  let analysis: BearHIDCaseAnalysis
  let evidenceClassification: String
  let fixtureStatus: FixtureStatus?
  let fixtureTraceJSON: String?
  let telemetry: TypoverTelemetrySummary
  let typoverLog: [String]
  let readinessSamples: [HostReadinessSample]
}

private struct MatrixArtifact: Codable {
  let schemaVersion: Int
  let runID: String
  let createdAt: Date
  let host: String
  let plan: BearHIDTestPlan
  let classification: String
  let cases: [CaseArtifact]
  let privacyNote: String
}

private struct DoctorReport: Encodable {
  let fixtureClientReady: Bool
  let fixtureReachable: Bool
  let fixtureStatus: FixtureStatus?
  let fixtureError: String?
  let typoverRunning: Bool
  let privateDiagnosticsEnabled: Bool
  let bearProbeStatus: String
  let bearFrontmost: Bool
  let caseCount: Int
  let wordsPerCase: Int
  let readyToRun: Bool
  let jigToolReady: Bool
  let jigClientReady: Bool
}

private struct ProcessResult {
  let status: Int32
  let output: String
  let error: String
}

private struct CommandRunner {
  func run(
    _ executable: String,
    _ arguments: [String],
    timeout: TimeInterval? = nil
  ) throws -> ProcessResult {
    let fileManager = FileManager.default
    let captureDirectory = fileManager.temporaryDirectory.appendingPathComponent(
      "typover-hid-command-\(UUID().uuidString)",
      isDirectory: true
    )
    try fileManager.createDirectory(
      at: captureDirectory,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )
    defer { try? fileManager.removeItem(at: captureDirectory) }
    let outputURL = captureDirectory.appendingPathComponent("stdout")
    let errorURL = captureDirectory.appendingPathComponent("stderr")
    _ = fileManager.createFile(
      atPath: outputURL.path,
      contents: nil,
      attributes: [.posixPermissions: 0o600]
    )
    _ = fileManager.createFile(
      atPath: errorURL.path,
      contents: nil,
      attributes: [.posixPermissions: 0o600]
    )
    let output = try FileHandle(forWritingTo: outputURL)
    let error = try FileHandle(forWritingTo: errorURL)
    defer {
      try? output.close()
      try? error.close()
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = error
    try process.run()

    if let timeout {
      let deadline = Date().addingTimeInterval(timeout)
      while process.isRunning, Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
      }
      if process.isRunning {
        process.terminate()
        process.waitUntilExit()
        throw HarnessError.commandFailed(
          "Timed out running \(URL(fileURLWithPath: executable).lastPathComponent)."
        )
      }
    } else {
      process.waitUntilExit()
    }
    try output.synchronize()
    try error.synchronize()

    return ProcessResult(
      status: process.terminationStatus,
      output: String(
        decoding: try Data(contentsOf: outputURL),
        as: UTF8.self
      ),
      error: String(
        decoding: try Data(contentsOf: errorURL),
        as: UTF8.self
      )
    )
  }
}

private struct FixtureController {
  let clientPath: String
  let host: String
  let runner: CommandRunner

  func invoke(
    _ arguments: [String],
    timeout: TimeInterval = 15
  ) throws -> String {
    let result = try runner.run(
      clientPath,
      ["--host", host, "--timeout", String(timeout)] + arguments,
      timeout: timeout + 2
    )
    guard result.status == 0 else {
      let detail = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
      throw HarnessError.commandFailed(
        "Fixture command failed (\(arguments.first ?? "unknown")): \(detail)"
      )
    }
    return result.output
  }

  func status(timeout: TimeInterval = 5) throws -> FixtureStatus {
    let output = try invoke(["status"], timeout: timeout)
    guard let data = output.data(using: .utf8),
      let status = try? JSONDecoder().decode(FixtureStatus.self, from: data)
    else {
      throw HarnessError.invalidJSON("Fixture status returned invalid JSON.")
    }
    return status
  }

  func abort() {
    _ = try? invoke(["abort"], timeout: 3)
  }

  func presentBear(
    phase: String,
    result: String = "none",
    progress: Int = 0,
    title: String,
    detail: String,
    next: String = ""
  ) throws {
    var arguments = [
      "present",
      "--phase", phase,
      "--result", result,
      "--brand", "bear",
      "--progress", String(progress),
      "--title", title,
      "--detail", detail,
    ]
    if !next.isEmpty {
      arguments += ["--next", next]
    }
    _ = try invoke(arguments)
  }
}

private struct JigController {
  let toolPath: String
  let clientPath: String
  let runner: CommandRunner

  func ensureRunning() throws {
    let result = try runner.run(toolPath, ["open"], timeout: 120)
    guard result.status == 0 else {
      throw HarnessError.commandFailed(
        "Could not open HID Capture Jig: \(result.error.trimmingCharacters(in: .whitespacesAndNewlines))"
      )
    }
  }

  func prepare(runID: String, caseCount: Int) throws {
    _ = try invoke([
      "bear-prepare",
      "--run-id", runID,
      "--case-count", String(caseCount),
      "--message", "Focus the disposable Bear note; the Jig will stay visible without taking keyboard focus.",
    ])
  }

  func begin(
    runID: String,
    testCase: BearHIDTestCase,
    caseCount: Int,
    textURL: URL
  ) throws {
    _ = try invoke([
      "bear-begin",
      "--run-id", runID,
      "--case-index", String(testCase.ordinal),
      "--case-count", String(caseCount),
      "--interval-ms", String(testCase.intervalMilliseconds),
      "--word-count", String(testCase.words),
      "--scheduled-text", textURL.path,
      "--start-delay-ms", String(testCase.startDelayMilliseconds),
      "--bear-focused",
    ])
  }

  func update(
    phase: String,
    correctedWords: Int? = nil,
    missedWords: Int? = nil,
    message: String,
    bearFocused: Bool
  ) {
    var arguments = [
      "bear-update", "--phase", phase,
      "--message", message,
      bearFocused ? "--bear-focused" : "--no-bear-focused",
    ]
    if let correctedWords {
      arguments += ["--corrected-words", String(correctedWords)]
    }
    if let missedWords {
      arguments += ["--missed-words", String(missedWords)]
    }
    _ = try? invoke(arguments)
  }

  private func invoke(_ arguments: [String]) throws -> String {
    let result = try runner.run(clientPath, arguments, timeout: 8)
    guard result.status == 0 else {
      throw HarnessError.commandFailed(
        "HID Capture Jig command failed: \(result.error.trimmingCharacters(in: .whitespacesAndNewlines))"
      )
    }
    guard let data = result.output.data(using: .utf8),
      let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      response["ok"] as? Bool == true
    else {
      throw HarnessError.invalidJSON("HID Capture Jig returned an invalid response.")
    }
    return result.output
  }
}

private struct Options {
  var command = ""
  var fixtureClient = ProcessInfo.processInfo.environment[
    "TYPOVER_HID_FIXTURE_CLIENT"
  ] ?? "/Users/malpern/local-code/keypath-pico-hid-fixture/Scripts/lab/pico-hid-fixture-client"
  var fixtureHost = ProcessInfo.processInfo.environment[
    "KEYPATH_FIXTURE_HOST"
  ] ?? "keypath-hid-fixture.local"
  var jigTool = ProcessInfo.processInfo.environment[
    "TYPOVER_HID_JIG_TOOL"
  ] ?? "/Users/malpern/local-code/keypath-pico-hid-fixture/Scripts/lab/hid-capture-jig-tool"
  var jigClient = ProcessInfo.processInfo.environment[
    "TYPOVER_HID_JIG_CLIENT"
  ] ?? "/Users/malpern/local-code/keypath-pico-hid-fixture/Scripts/lab/hid-capture-jig-client"
  var intervals = [160, 100, 60, 40]
  var words = 20
  var quietTimeoutSeconds = 600
  var exclusiveDesktopConfirmed = false
  var outputDirectory: String?

  static func parse(_ arguments: [String]) throws -> Options {
    guard let command = arguments.first,
      ["plan", "doctor", "run"].contains(command)
    else {
      throw HarnessError.usage(usage)
    }
    var options = Options()
    options.command = command
    var index = 1
    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "--exclusive-desktop-confirmed":
        options.exclusiveDesktopConfirmed = true
        index += 1
      case "--fixture-client", "--fixture-host", "--jig-tool", "--jig-client",
        "--intervals", "--words", "--quiet-timeout-seconds", "--output-directory":
        guard index + 1 < arguments.count else {
          throw HarnessError.usage("Missing value for \(argument).")
        }
        let value = arguments[index + 1]
        switch argument {
        case "--fixture-client": options.fixtureClient = value
        case "--fixture-host": options.fixtureHost = value
        case "--jig-tool": options.jigTool = value
        case "--jig-client": options.jigClient = value
        case "--intervals":
          let values = value.split(separator: ",").compactMap { Int($0) }
          guard values.count == value.split(separator: ",").count else {
            throw HarnessError.usage("Intervals must be comma-separated integers.")
          }
          options.intervals = values
        case "--words":
          guard let words = Int(value) else {
            throw HarnessError.usage("Words must be an integer.")
          }
          options.words = words
        case "--quiet-timeout-seconds":
          guard let timeout = Int(value), timeout >= 0 else {
            throw HarnessError.usage("Quiet timeout must be non-negative.")
          }
          options.quietTimeoutSeconds = timeout
        case "--output-directory": options.outputDirectory = value
        default: break
        }
        index += 2
      default:
        throw HarnessError.usage("Unknown argument: \(argument)\n\n\(usage)")
      }
    }
    return options
  }

  static let usage = """
    Usage: typover-hid-harness <plan|doctor|run> [options]

      plan      Print the deterministic test matrix; no board or UI needed.
      doctor    Check Typover, Bear, Accessibility, and fixture readiness.
      run       Wait for a quiet Mac, then type the matrix into focused Bear.

    Run requires --exclusive-desktop-confirmed because the ESP32 is a real
    keyboard and can only type into the active desktop.
    """
}

@main
@MainActor
private enum TypoverBearHIDHarness {
  static func main() {
    do {
      let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
      let plan = try BearHIDTestPlan(
        intervalsMilliseconds: options.intervals,
        wordsPerCase: options.words
      )
      switch options.command {
      case "plan":
        try printJSON(plan)
      case "doctor":
        try doctor(options: options, plan: plan)
      case "run":
        try run(options: options, plan: plan)
      default:
        throw HarnessError.usage(Options.usage)
      }
    } catch {
      FileHandle.standardError.write(Data("typover-hid-harness: \(error)\n".utf8))
      exit(2)
    }
  }

  private static func doctor(options: Options, plan: BearHIDTestPlan) throws {
    let fileManager = FileManager.default
    let clientReady = fileManager.isExecutableFile(atPath: options.fixtureClient)
    let jigToolReady = fileManager.isExecutableFile(atPath: options.jigTool)
    let jigClientReady = fileManager.isExecutableFile(atPath: options.jigClient)
    let typoverRunning = !NSRunningApplication.runningApplications(
      withBundleIdentifier: "com.malpern.typover"
    ).isEmpty
    let privateDiagnostics = UserDefaults.standard.persistentDomain(
      forName: "com.malpern.typover"
    )?["bear-private-diagnostics-enabled"] as? Bool ?? false
    let probe = BearAccessibilityProbe().run()
    let bearFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
      == BearAccessibilityProbe.bearBundleIdentifier
    var fixtureStatus: FixtureStatus?
    var fixtureError: String?
    if clientReady {
      do {
        fixtureStatus = try FixtureController(
          clientPath: options.fixtureClient,
          host: options.fixtureHost,
          runner: CommandRunner()
        ).status(timeout: 3)
      } catch {
        fixtureError = String(describing: error)
      }
    }
    try printJSON(
      DoctorReport(
        fixtureClientReady: clientReady,
        fixtureReachable: fixtureStatus != nil,
        fixtureStatus: fixtureStatus,
        fixtureError: fixtureError,
        typoverRunning: typoverRunning,
        privateDiagnosticsEnabled: privateDiagnostics,
        bearProbeStatus: probe.status.rawValue,
        bearFrontmost: bearFrontmost,
        caseCount: plan.cases.count,
        wordsPerCase: plan.wordsPerCase,
        readyToRun: clientReady && fixtureStatus?.usbMounted == true
          && jigToolReady && jigClientReady && typoverRunning
          && privateDiagnostics && probe.status == .ready && bearFrontmost,
        jigToolReady: jigToolReady,
        jigClientReady: jigClientReady
      )
    )
  }

  private static func run(options: Options, plan: BearHIDTestPlan) throws {
    guard options.exclusiveDesktopConfirmed else {
      throw HarnessError.usage(
        "run requires --exclusive-desktop-confirmed; real USB input owns the active desktop."
      )
    }
    guard FileManager.default.isExecutableFile(atPath: options.fixtureClient) else {
      throw HarnessError.commandFailed(
        "Fixture client is missing or not executable: \(options.fixtureClient)"
      )
    }
    guard FileManager.default.isExecutableFile(atPath: options.jigTool),
      FileManager.default.isExecutableFile(atPath: options.jigClient)
    else {
      throw HarnessError.commandFailed(
        "The HID Capture Jig tool or client is missing."
      )
    }
    guard !NSRunningApplication.runningApplications(
      withBundleIdentifier: "com.malpern.typover"
    ).isEmpty else {
      throw HarnessError.commandFailed("Typover is not running.")
    }

    let fixture = FixtureController(
      clientPath: options.fixtureClient,
      host: options.fixtureHost,
      runner: CommandRunner()
    )
    let jig = JigController(
      toolPath: options.jigTool,
      clientPath: options.jigClient,
      runner: CommandRunner()
    )
    print("Opening the AppKit HID Jig in Typover · Bear monitor mode…")
    try jig.ensureRunning()

    let stamp = ISO8601DateFormatter().string(from: Date())
      .replacingOccurrences(of: ":", with: "-")
    let matrixRunID = "typover-hid-\(stamp)"
    try jig.prepare(runID: matrixRunID, caseCount: plan.cases.count)

    let initialStatus = try fixture.status()
    guard initialStatus.usbMounted == true else {
      throw HarnessError.commandFailed(
        "The fixture is reachable, but its USB keyboard is not mounted."
      )
    }
    try fixture.presentBear(
      phase: "next",
      title: "BEAR TYPOVER TEST",
      detail: "FOCUS THE BEAR NOTE",
      next: "4 TIMING CASES"
    )

    print("Waiting for three quiet host samples (>=60% CPU idle, no Swift compiler)…")
    let readiness = try waitForQuietHost(
      timeoutSeconds: options.quietTimeoutSeconds
    )
    print("Activating Bear and verifying the collapsed caret at the end of the test note…")
    guard activateBear() else {
      throw HarnessError.unsafeFocus(
        "Bear is not running or could not be activated for physical input."
      )
    }
    try waitForSafeBearCaret(timeoutSeconds: 120)

    let outputDirectory = URL(fileURLWithPath: options.outputDirectory ?? (
      FileManager.default.homeDirectoryForCurrentUser.path
        + "/.local/state/typover/bear-hid/\(matrixRunID)"
    ))
    try FileManager.default.createDirectory(
      at: outputDirectory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )

    var caseArtifacts: [CaseArtifact] = []
    for testCase in plan.cases {
      try requireSafeBearCaret()
      let artifact = try execute(
        testCase: testCase,
        matrixRunID: matrixRunID,
        outputDirectory: outputDirectory,
        fixture: fixture,
        jig: jig,
        caseCount: plan.cases.count,
        readiness: readiness
      )
      caseArtifacts.append(artifact)
      try writeJSON(
        artifact,
        to: outputDirectory.appendingPathComponent(
          "case-\(testCase.ordinal)-\(testCase.intervalMilliseconds)ms.json"
        )
      )
      print(
        "\(testCase.intervalMilliseconds) ms: \(artifact.analysis.correctedWords)/\(testCase.words) corrected (\(artifact.evidenceClassification))"
      )
      guard artifact.focusRemainedValid,
        artifact.evidenceClassification != "unexpected-text",
        artifact.evidenceClassification != "invalid-evidence"
      else {
        break
      }
    }

    let classification: String
    if caseArtifacts.count != plan.cases.count
      || caseArtifacts.contains(where: {
        !$0.focusRemainedValid
          || ["unexpected-text", "invalid-evidence"].contains(
            $0.evidenceClassification
          )
      })
    {
      classification = "harness-invalid"
    } else if caseArtifacts.allSatisfy({ $0.evidenceClassification == "passed" }) {
      classification = "all-corrections-observed"
    } else {
      classification = "safe-misses-observed"
    }

    let summary = MatrixArtifact(
      schemaVersion: 1,
      runID: matrixRunID,
      createdAt: Date(),
      host: options.fixtureHost,
      plan: plan,
      classification: classification,
      cases: caseArtifacts,
      privacyNote: "Contains synthetic test text and local Typover unified-log lines, which may include bounded Bear context while private diagnostics are enabled. File permissions are 0600."
    )
    let summaryURL = outputDirectory.appendingPathComponent("summary.json")
    try writeJSON(summary, to: summaryURL)
    print("Evidence: \(summaryURL.path)")
  }

  private static func execute(
    testCase: BearHIDTestCase,
    matrixRunID: String,
    outputDirectory: URL,
    fixture: FixtureController,
    jig: JigController,
    caseCount: Int,
    readiness: [HostReadinessSample]
  ) throws -> CaseArtifact {
    let reader = BearTypingContextReader(leadingLimit: 256, trailingLimit: 24)
    guard case .ready(let baseline) = reader.read(),
      baseline.caretLocation == baseline.documentLength,
      baseline.trailingText.isEmpty
    else {
      throw HarnessError.unsafeFocus(
        "Bear must be frontmost with a collapsed caret at the end of the disposable test note."
      )
    }

    let shortMatrixID = matrixRunID
      .replacingOccurrences(of: "typover-hid-", with: "th-")
    let runID = String(
      "\(shortMatrixID)-i\(testCase.intervalMilliseconds)".prefix(48)
    )
    try fixture.presentBear(
      phase: "preparing",
      progress: max(0, (testCase.ordinal - 1) * 1000 / caseCount),
      title: "BEAR CASE \(testCase.ordinal) OF \(caseCount)",
      detail: "\(testCase.intervalMilliseconds) MS PER KEY"
    )
    let caseDirectory = outputDirectory.appendingPathComponent(
      "case-\(testCase.ordinal)"
    )
    try FileManager.default.createDirectory(
      at: caseDirectory,
      withIntermediateDirectories: true
    )
    let textURL = caseDirectory.appendingPathComponent("input.txt")
    try testCase.typedText.write(to: textURL, atomically: true, encoding: .utf8)
    let startedAt = Date()

    _ = try fixture.invoke(
      testCase.fixtureArguments(
        command: "compile-text",
        runID: runID,
        filePath: textURL.path
      )
    )
    _ = try fixture.invoke(
      testCase.fixtureArguments(
        command: "load-script",
        runID: runID,
        filePath: textURL.path
      )
    )
    _ = try fixture.invoke(testCase.fixtureArguments(command: "arm", runID: runID))
    try requireSafeBearCaret(expectedCaret: baseline.caretLocation)
    do {
      try jig.begin(
        runID: runID,
        testCase: testCase,
        caseCount: caseCount,
        textURL: textURL
      )
      try fixture.presentBear(
        phase: "countdown",
        progress: max(0, (testCase.ordinal - 1) * 1000 / caseCount),
        title: "BEAR READY",
        detail: "\(testCase.words) X TEH",
        next: "TYPING STARTS SOON"
      )
      try requireSafeBearCaret(expectedCaret: baseline.caretLocation)
    } catch {
      fixture.abort()
      jig.update(
        phase: "failed",
        message: "Monitor setup or Bear focus failed before HID start.",
        bearFocused: false
      )
      throw error
    }
    _ = try fixture.invoke(testCase.fixtureArguments(command: "start", runID: runID))
    try? fixture.presentBear(
      phase: "testing",
      progress: max(1, testCase.ordinal * 800 / caseCount),
      title: "TYPING IN BEAR",
      detail: "CASE \(testCase.ordinal) OF \(caseCount)"
    )

    let typingDeadline = Date().addingTimeInterval(
      Double(
        testCase.startDelayMilliseconds
          + testCase.expectedUTF16Length * testCase.intervalMilliseconds
          + 300
      ) / 1_000
    )
    var focusRemainedValid = true
    while Date() < typingDeadline {
      if NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        != BearAccessibilityProbe.bearBundleIdentifier
      {
        focusRemainedValid = false
        fixture.abort()
        jig.update(
          phase: "failed",
          message: "Bear lost focus; the fixture was aborted and no result is credited.",
          bearFocused: false
        )
        try? fixture.presentBear(
          phase: "result",
          result: "fail",
          title: "BEAR FOCUS LOST",
          detail: "RUN ABORTED SAFELY"
        )
        break
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.025))
    }

    var finalStatus: FixtureStatus?
    if focusRemainedValid {
      let deadline = Date().addingTimeInterval(5)
      repeat {
        finalStatus = try? fixture.status(timeout: 2)
        if finalStatus?.state == "complete" { break }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
      } while Date() < deadline
      jig.update(
        phase: "analyzing",
        message: "Comparing exact Bear text with Typover correction logs…",
        bearFocused: true
      )
      try? fixture.presentBear(
        phase: "observing",
        progress: max(1, testCase.ordinal * 900 / caseCount),
        title: "CHECKING BEAR",
        detail: "VERIFYING TYPOVER"
      )
      RunLoop.current.run(
        until: Date().addingTimeInterval(
          Double(testCase.settleMilliseconds) / 1_000
        )
      )
    }

    let finalSnapshot: BearTypingContextSnapshot?
    if case .ready(let snapshot) = reader.read() {
      finalSnapshot = snapshot
    } else {
      finalSnapshot = nil
    }
    let insertedText = finalSnapshot.flatMap {
      BearHIDTextEvidence.insertedText(
        baselineCaret: baseline.caretLocation,
        finalCaret: $0.caretLocation,
        finalLeadingText: $0.leadingText,
        expectedLength: testCase.expectedUTF16Length
      )
    }
    let analysis = BearHIDCaseAnalysis(
      testCase: testCase,
      actualText: focusRemainedValid ? insertedText : nil
    )
    let finishedAt = Date()
    let trace = try? fixture.invoke(
      ["trace-all", "--retry-seconds", "5"],
      timeout: 8
    )
    let logs = typoverLog(from: startedAt, to: finishedAt)
    let telemetry = summarize(logs: logs)
    let evidenceClassification: String
    if !focusRemainedValid || finalStatus?.state != "complete"
      || finalStatus?.runId != runID
      || telemetry.applied != analysis.correctedWords
    {
      evidenceClassification = "invalid-evidence"
    } else {
      evidenceClassification = analysis.classification.rawValue
    }
    let monitorPhase: String = switch evidenceClassification {
    case "passed": "passed"
    case "safe-misses-observed": "safeMisses"
    default: "failed"
    }
    let monitorMessage: String = switch evidenceClassification {
    case "passed":
      "All \(analysis.correctedWords) corrections matched Typover log evidence."
    case "safe-misses-observed":
      "\(analysis.correctedWords) corrected · \(analysis.missedWords) preserved safe misses."
    default:
      "Focus, fixture, text, or Typover-log evidence was incomplete."
    }
    jig.update(
      phase: monitorPhase,
      correctedWords: analysis.correctedWords,
      missedWords: analysis.missedWords,
      message: monitorMessage,
      bearFocused: focusRemainedValid
    )
    let fixtureResult = switch evidenceClassification {
    case "passed": "pass"
    case "safe-misses-observed": "inconclusive"
    default: "fail"
    }
    let fixtureTitle = switch evidenceClassification {
    case "passed": "BEAR TEST PASSED"
    case "safe-misses-observed": "BEAR NEEDS REVIEW"
    default: "BEAR TEST INVALID"
    }
    try? fixture.presentBear(
      phase: "result",
      result: fixtureResult,
      progress: evidenceClassification == "passed"
        ? 1000
        : max(1, testCase.ordinal * 900 / caseCount),
      title: fixtureTitle,
      detail: "\(analysis.correctedWords) FIXED  \(analysis.missedWords) MISSED"
    )
    if let brandedStatus = try? fixture.status(timeout: 2) {
      finalStatus = brandedStatus
    }
    return CaseArtifact(
      testCase: testCase,
      runID: runID,
      startedAt: startedAt,
      finishedAt: finishedAt,
      focusRemainedValid: focusRemainedValid,
      baselineCaret: baseline.caretLocation,
      finalCaret: finalSnapshot?.caretLocation,
      baselineDocumentLength: baseline.documentLength,
      finalDocumentLength: finalSnapshot?.documentLength,
      analysis: analysis,
      evidenceClassification: evidenceClassification,
      fixtureStatus: finalStatus,
      fixtureTraceJSON: trace,
      telemetry: telemetry,
      typoverLog: logs,
      readinessSamples: readiness
    )
  }

  private static func requireSafeBearCaret(expectedCaret: Int? = nil) throws {
    let probe = BearAccessibilityProbe().run()
    guard probe.status == .ready,
      NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        == BearAccessibilityProbe.bearBundleIdentifier,
      let selectedRange = probe.selectedRange,
      selectedRange.length == 0,
      expectedCaret.map({ $0 == selectedRange.location }) ?? true
    else {
      throw HarnessError.unsafeFocus(
        "Bear must remain frontmost with the same collapsed editor caret."
      )
    }
  }

  private static func waitForSafeBearCaret(timeoutSeconds: Int) throws {
    let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
    repeat {
      let probe = BearAccessibilityProbe().run()
      if probe.status == .ready,
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
          == BearAccessibilityProbe.bearBundleIdentifier,
        let selection = probe.selectedRange,
        let characterCount = probe.characterCount,
        selection.length == 0,
        selection.location == characterCount
      {
        return
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    } while Date() < deadline
    throw HarnessError.unsafeFocus(
      "Bear did not become frontmost with a collapsed caret at the end of its editor."
    )
  }

  private static func activateBear() -> Bool {
    guard let bear = NSRunningApplication.runningApplications(
      withBundleIdentifier: BearAccessibilityProbe.bearBundleIdentifier
    ).first else {
      return false
    }
    return bear.activate(options: [.activateAllWindows])
  }

  private static func waitForQuietHost(
    timeoutSeconds: Int
  ) throws -> [HostReadinessSample] {
    let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
    var consecutive: [HostReadinessSample] = []
    repeat {
      let sample = readinessSample()
      if sample.isQuiet {
        consecutive.append(sample)
        print(
          "Quiet sample \(consecutive.count)/3: \(sample.cpuIdlePercent.map { String(format: "%.1f%% idle", $0) } ?? "CPU unavailable")"
        )
        if consecutive.count == 3 { return consecutive }
      } else {
        consecutive.removeAll(keepingCapacity: true)
      }
      RunLoop.current.run(until: Date().addingTimeInterval(2))
    } while Date() <= deadline
    throw HarnessError.quietTimeout
  }

  private static func readinessSample() -> HostReadinessSample {
    let runner = CommandRunner()
    let top = try? runner.run(
      "/usr/bin/top",
      ["-l", "1", "-n", "0"],
      timeout: 5
    )
    let idle = top.flatMap { result -> Double? in
      guard let line = result.output.split(separator: "\n").first(where: {
        $0.contains("CPU usage:")
      }),
        let range = line.range(of: #"([0-9.]+)% idle"#, options: .regularExpression)
      else { return nil }
      return Double(line[range].dropLast("% idle".count))
    }
    let pgrep = try? runner.run(
      "/usr/bin/pgrep",
      ["-fl", "swift-frontend|swift-driver|swift-build|swift-test"],
      timeout: 2
    )
    let compilers = pgrep?.status == 0
      ? pgrep!.output.split(separator: "\n").map(String.init)
      : []
    return HostReadinessSample(
      timestamp: Date(),
      cpuIdlePercent: idle,
      activeSwiftCompilers: compilers
    )
  }

  private static func typoverLog(from start: Date, to end: Date) -> [String] {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let result = try? CommandRunner().run(
      "/usr/bin/log",
      [
        "show", "--style", "compact",
        "--start", formatter.string(from: start),
        "--end", formatter.string(from: end.addingTimeInterval(1)),
        "--predicate",
        "process == \"Typover\" AND subsystem == \"com.malpern.typover\" AND category == \"BearAutomaticCorrection\"",
      ],
      timeout: 10
    )
    return result?.output.split(separator: "\n").map(String.init) ?? []
  }

  private static func summarize(logs: [String]) -> TypoverTelemetrySummary {
    func count(_ marker: String) -> Int {
      logs.count(where: { $0.contains(marker) })
    }
    return TypoverTelemetrySummary(
      applied: count("Automatic correction applied"),
      rapidTypingCoalesced: count("outcome=rapidTypingCoalesced"),
      contextChanged: count("outcome=contextChanged"),
      staleBoundaryInput: count("outcome=staleBoundaryInput"),
      baselineUnavailable: count("outcome=baselineUnavailable"),
      learnedSuppression: count("outcome=learnedSuppression"),
      replacementRefused: count("outcome=replacementRefused")
        + count("outcome=deferredReplacementRefused")
    )
  }

  private static func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
  }

  private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value) + Data("\n".utf8)
    let temporary = url.deletingLastPathComponent().appendingPathComponent(
      ".\(url.lastPathComponent).\(ProcessInfo.processInfo.processIdentifier).tmp"
    )
    try data.write(to: temporary, options: .atomic)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: temporary.path
    )
    if FileManager.default.fileExists(atPath: url.path) {
      _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    } else {
      try FileManager.default.moveItem(at: temporary, to: url)
    }
  }

}
