import AppKit
import ApplicationServices
import Darwin
import Foundation
import QuartzCore
import TypoverAccessibility
import TypoverHIDTesting
import TypoverOverlay

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
  let valueBeforeBoundaryCallback: Int
  let boundaryToValueMilliseconds: [Double]
  let correctionLatencyMilliseconds: [Double]
}

private struct ProcessLoadSample: Codable, Equatable {
  let cpuPercent: Double?
  let residentMemoryKiB: Int?
  let powerScore: Double?
}

private struct HostLoadSample: Codable, Equatable {
  let timestamp: Date
  let cpuIdlePercent: Double?
  let typover: ProcessLoadSample
  let bear: ProcessLoadSample
  let windowServer: ProcessLoadSample
  let targetedProcessCount: Int
  let powerRowsSeen: Int
  let powerCommandStatus: Int32?
}

private extension HostLoadSample {
  var isComplete: Bool {
    targetedProcessCount == 3
      && powerRowsSeen == 3
      && powerCommandStatus == 0
      && cpuIdlePercent != nil
      && [typover, bear, windowServer].allSatisfy {
        $0.cpuPercent != nil
          && $0.residentMemoryKiB != nil
          && $0.powerScore != nil
      }
  }
}

private struct CaseArtifact: Codable {
  let testCase: BearHIDTestCase
  let runID: String
  let startedAt: Date
  let finishedAt: Date
  let focusRemainedValid: Bool
  let focusLossBundleIdentifier: String?
  let baselineCaret: Int
  let finalCaret: Int?
  let baselineDocumentLength: Int
  let finalDocumentLength: Int?
  let analysis: BearHIDCaseAnalysis
  let evidenceClassification: String
  let fixtureStatus: FixtureStatus?
  let fixtureTraceJSON: String?
  let telemetry: TypoverTelemetrySummary
  let overlayRetention: BearHIDOverlayRetentionEvidence
  let typoverLog: [String]
  let readinessSamples: [HostReadinessSample]
  let loadSamples: [HostLoadSample]
  let loadEvidenceComplete: Bool
  let postFixtureObservationMilliseconds: Double
  let convergedAfterMilliseconds: Double?
}

private struct MatrixArtifact: Codable {
  let schemaVersion: Int
  let runID: String
  let createdAt: Date
  let host: String
  let plan: BearHIDTestPlan
  let loadProfile: BearHIDLoadProfile
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

private struct SnapshotReport: Encodable {
  let status: String
  let leadingRange: AccessibilityTextRange?
  let leadingText: String?
  let trailingText: String?
  let caretLocation: Int?
  let documentLength: Int?
}

private struct BearCLIContent: Decodable {
  let content: String
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

private enum TypoverCorrectionOverlayCounter {
  static func visibleCount() -> Int? {
    guard AXIsProcessTrusted(),
      let application = NSRunningApplication.runningApplications(
        withBundleIdentifier: "com.malpern.typover"
      ).first
    else {
      return nil
    }
    let applicationElement = AXUIElementCreateApplication(
      application.processIdentifier
    )
    AXUIElementSetMessagingTimeout(applicationElement, 2)
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        applicationElement,
        kAXWindowsAttribute as CFString,
        &value
      ) == .success,
      let values = value as? [Any]
    else {
      return nil
    }
    return values.reduce(into: 0) { count, candidate in
      guard CFGetTypeID(candidate as CFTypeRef) == AXUIElementGetTypeID()
      else {
        return
      }
      let window = unsafeDowncast(candidate as AnyObject, to: AXUIElement.self)
      var identifierValue: CFTypeRef?
      guard
        AXUIElementCopyAttributeValue(
          window,
          kAXIdentifierAttribute as CFString,
          &identifierValue
        ) == .success,
        identifierValue as? String == "typover.bear.correction-overlay"
      else {
        return
      }
      count += 1
    }
  }
}

private final class AwakeSession {
  private var process: Process?

  func start() throws {
    guard process == nil else { return }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
    // `caffeinate -u` defaults to a five-second UserIsActive assertion when
    // no timeout is supplied. The quiet-admission samples take longer than
    // that, so a policy-driven screen lock could still interrupt the run.
    // Keep every assertion alive for at most one hour, while `-w` releases
    // them sooner as soon as this harness exits.
    process.arguments = HostWakeAssertionPlan.caffeinateArguments(
      parentProcessIdentifier: ProcessInfo.processInfo.processIdentifier
    )
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    self.process = process
  }

  func stop() {
    if process?.isRunning == true {
      process?.terminate()
    }
    process = nil
  }
}

private final class LockedLoadState: @unchecked Sendable {
  private let lock = NSLock()
  private var stopped = false
  private var storedSamples: [HostLoadSample] = []

  func requestStop() {
    lock.withLock { stopped = true }
  }

  var shouldStop: Bool {
    lock.withLock { stopped }
  }

  func append(_ sample: HostLoadSample) {
    lock.withLock { storedSamples.append(sample) }
  }

  var samples: [HostLoadSample] {
    lock.withLock { storedSamples }
  }
}

private final class HostLoadSampler: @unchecked Sendable {
  private let state = LockedLoadState()
  private var thread: Thread?

  func start() {
    guard thread == nil else { return }
    let state = state
    let worker = Thread {
      while !state.shouldStop {
        autoreleasepool {
          state.append(Self.readSample())
        }
        for _ in 0 ..< 10 where !state.shouldStop {
          Thread.sleep(forTimeInterval: 0.1)
        }
      }
    }
    worker.name = "Typover HID resource sampler"
    thread = worker
    worker.start()
  }

  func stop() -> [HostLoadSample] {
    state.requestStop()
    let deadline = Date().addingTimeInterval(6)
    while thread?.isExecuting == true, Date() < deadline {
      Thread.sleep(forTimeInterval: 0.02)
    }
    thread = nil
    return state.samples
  }

  private static func readSample() -> HostLoadSample {
    let runner = CommandRunner()
    let processList = try? runner.run(
      "/bin/ps",
      ["-axo", "pid=,pcpu=,rss=,comm="],
      timeout: 3
    )
    var processSamples = parseProcessSamples(processList?.output ?? "")
    let processIdentifiersByName = parseProcessIdentifiers(
      processList?.output ?? ""
    )
    let processIdentifiers = processIdentifiersByName.values.sorted()
    let topArguments = HostLoadSamplingPlan.topArguments(
      processIdentifiers: processIdentifiers
    )
    let top = try? runner.run(
      "/usr/bin/top",
      topArguments,
      timeout: 5
    )
    let idle = top.flatMap {
      HostLoadSamplingPlan.cpuIdlePercent(from: $0.output)
    }
    let powerScoresByProcessIdentifier =
      HostLoadSamplingPlan.powerScoresByProcessIdentifier(
        from: top?.output ?? ""
      )
    for (name, processIdentifier) in processIdentifiersByName {
      guard let powerScore = powerScoresByProcessIdentifier[processIdentifier]
      else { continue }
      let existing = processSamples[name] ?? emptyProcessSample
      processSamples[name] = ProcessLoadSample(
        cpuPercent: existing.cpuPercent,
        residentMemoryKiB: existing.residentMemoryKiB,
        powerScore: powerScore
      )
    }
    return HostLoadSample(
      timestamp: Date(),
      cpuIdlePercent: idle,
      typover: processSamples["Typover"] ?? emptyProcessSample,
      bear: processSamples["Bear"] ?? emptyProcessSample,
      windowServer: processSamples["WindowServer"] ?? emptyProcessSample,
      targetedProcessCount: processIdentifiers.count,
      powerRowsSeen: powerScoresByProcessIdentifier.count,
      powerCommandStatus: top?.status
    )
  }

  private static func parseProcessIdentifiers(
    _ processList: String
  ) -> [String: String] {
    var result: [String: String] = [:]
    for line in processList.split(separator: "\n") {
      let fields = line.split(
        maxSplits: 3,
        omittingEmptySubsequences: true,
        whereSeparator: { $0.isWhitespace }
      )
      guard fields.count == 4 else { continue }
      let name = URL(fileURLWithPath: String(fields[3])).lastPathComponent
      guard ["Typover", "Bear", "WindowServer"].contains(name) else {
        continue
      }
      result[name] = String(fields[0])
    }
    return result
  }

  private static let emptyProcessSample = ProcessLoadSample(
    cpuPercent: nil,
    residentMemoryKiB: nil,
    powerScore: nil
  )

  private static func parseProcessSamples(
    _ processList: String
  ) -> [String: ProcessLoadSample] {
    var result: [String: ProcessLoadSample] = [:]
    for line in processList.split(separator: "\n") {
      let fields = line.split(
        maxSplits: 3,
        omittingEmptySubsequences: true,
        whereSeparator: { $0.isWhitespace }
      )
      guard fields.count == 4 else { continue }
      let name = URL(fileURLWithPath: String(fields[3])).lastPathComponent
      guard ["Typover", "Bear", "WindowServer"].contains(name) else {
        continue
      }
      result[name] = ProcessLoadSample(
        cpuPercent: Double(fields[1]),
        residentMemoryKiB: Int(fields[2]),
        powerScore: nil
      )
    }
    return result
  }
}

private final class AccessibilityLoadWorker: @unchecked Sendable {
  private let state = LockedLoadState()
  private var thread: Thread?

  func start() {
    guard thread == nil else { return }
    let state = state
    let worker = Thread {
      let reader = BearTypingContextReader(leadingLimit: 32, trailingLimit: 8)
      while !state.shouldStop {
        autoreleasepool { _ = reader.read() }
        Thread.sleep(forTimeInterval: 0.01)
      }
    }
    worker.name = "Typover HID AX contention"
    thread = worker
    worker.start()
  }

  func stop() {
    state.requestStop()
    let deadline = Date().addingTimeInterval(2)
    while thread?.isExecuting == true, Date() < deadline {
      Thread.sleep(forTimeInterval: 0.01)
    }
    thread = nil
  }
}

@MainActor
private final class ControlledLoadSession {
  let profile: BearHIDLoadProfile
  private var cpuProcesses: [Process] = []
  private var panels: [NSPanel] = []
  private var accessibilityWorker: AccessibilityLoadWorker?

  init(profile: BearHIDLoadProfile) {
    self.profile = profile
  }

  func start() throws {
    if profile.stressesCPU {
      try startCPULoad()
    }
    if profile.stressesWindowServer {
      startWindowServerLoad()
    }
    if profile.stressesAccessibility {
      let worker = AccessibilityLoadWorker()
      accessibilityWorker = worker
      worker.start()
    }
  }

  func stop() {
    accessibilityWorker?.stop()
    accessibilityWorker = nil
    for panel in panels {
      panel.contentView?.layer?.removeAllAnimations()
      panel.orderOut(nil)
    }
    panels.removeAll()
    for process in cpuProcesses where process.isRunning {
      process.terminate()
    }
    let deadline = Date().addingTimeInterval(1)
    while cpuProcesses.contains(where: \.isRunning), Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    for process in cpuProcesses where process.isRunning {
      kill(process.processIdentifier, SIGKILL)
    }
    cpuProcesses.removeAll()
  }

  private func startCPULoad() throws {
    let processorCount = ProcessInfo.processInfo.activeProcessorCount
    let workers = max(1, processorCount / 2)
    for _ in 0 ..< workers {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/nice")
      process.arguments = [
        "-n", "10", "/bin/sh", "-c", "while :; do :; done",
      ]
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      try process.run()
      cpuProcesses.append(process)
    }
  }

  private func startWindowServerLoad() {
    guard let screen = NSScreen.main else { return }
    let frame = screen.visibleFrame
    for index in 0 ..< 24 {
      let size = 28.0
      let x = frame.minX + 8 + Double(index % 12) * (size + 5)
      let y = index < 12 ? frame.minY + 8 : frame.maxY - size - 8
      let panel = NSPanel(
        contentRect: NSRect(x: x, y: y, width: size, height: size),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
      )
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.alphaValue = 0.22
      panel.ignoresMouseEvents = true
      panel.hidesOnDeactivate = false
      panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
      panel.level = .floating
      let view = NSView(frame: panel.contentView?.bounds ?? .zero)
      view.wantsLayer = true
      view.layer?.backgroundColor = NSColor.systemOrange.cgColor
      view.layer?.cornerRadius = 8
      view.setAccessibilityElement(false)
      panel.contentView = view

      let rotation = CABasicAnimation(keyPath: "transform.rotation")
      rotation.fromValue = 0
      rotation.toValue = Double.pi * 2
      rotation.duration = 0.3 + Double(index % 5) * 0.04
      rotation.repeatCount = .infinity
      view.layer?.add(rotation, forKey: "rotation")

      let pulse = CABasicAnimation(keyPath: "opacity")
      pulse.fromValue = 0.2
      pulse.toValue = 1.0
      pulse.duration = 0.18 + Double(index % 4) * 0.03
      pulse.autoreverses = true
      pulse.repeatCount = .infinity
      view.layer?.add(pulse, forKey: "pulse")
      panel.orderFrontRegardless()
      panels.append(panel)
    }
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
      "--message",
      "Focus the disposable Bear note; the Jig will stay visible without taking keyboard focus.",
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
  var fixtureClient =
    ProcessInfo.processInfo.environment[
      "TYPOVER_HID_FIXTURE_CLIENT"
    ] ?? "/Users/malpern/local-code/keypath-pico-hid-fixture/Scripts/lab/pico-hid-fixture-client"
  var fixtureHost =
    ProcessInfo.processInfo.environment[
      "KEYPATH_FIXTURE_HOST"
    ] ?? "keypath-hid-fixture.local"
  var jigTool =
    ProcessInfo.processInfo.environment[
      "TYPOVER_HID_JIG_TOOL"
    ] ?? "/Users/malpern/local-code/keypath-pico-hid-fixture/Scripts/lab/hid-capture-jig-tool"
  var jigClient =
    ProcessInfo.processInfo.environment[
      "TYPOVER_HID_JIG_CLIENT"
    ] ?? "/Users/malpern/local-code/keypath-pico-hid-fixture/Scripts/lab/hid-capture-jig-client"
  var bearCLI =
    ProcessInfo.processInfo.environment[
      "TYPOVER_BEAR_CLI"
    ] ?? "/Applications/Bear.app/Contents/MacOS/bearcli"
  var bearNoteID: String?
  var intervals = [160, 100, 60, 40]
  var words = 20
  var quietTimeoutSeconds = 600
  var loadProfile = BearHIDLoadProfile.quiet
  var scenario = BearHIDTestScenario.repeatedWords
  var exclusiveDesktopConfirmed = false
  var outputDirectory: String?

  static func parse(_ arguments: [String]) throws -> Options {
    guard let command = arguments.first,
      ["plan", "snapshot", "doctor", "run"].contains(command)
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
        "--bear-cli", "--bear-note-id",
        "--intervals", "--words", "--quiet-timeout-seconds", "--output-directory",
        "--load-profile", "--scenario":
        guard index + 1 < arguments.count else {
          throw HarnessError.usage("Missing value for \(argument).")
        }
        let value = arguments[index + 1]
        switch argument {
        case "--fixture-client": options.fixtureClient = value
        case "--fixture-host": options.fixtureHost = value
        case "--jig-tool": options.jigTool = value
        case "--jig-client": options.jigClient = value
        case "--bear-cli": options.bearCLI = value
        case "--bear-note-id": options.bearNoteID = value
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
        case "--load-profile":
          guard let profile = BearHIDLoadProfile(rawValue: value) else {
            throw HarnessError.usage(
              "Load profile must be quiet, cpu, window-server, accessibility, or combined."
            )
          }
          options.loadProfile = profile
        case "--scenario":
          guard let scenario = BearHIDTestScenario(rawValue: value) else {
            throw HarnessError.usage(
              "Scenario must be repeated-words or punctuation."
            )
          }
          options.scenario = scenario
        default: break
        }
        index += 2
      default:
        throw HarnessError.usage("Unknown argument: \(argument)\n\n\(usage)")
      }
    }
    if let noteID = options.bearNoteID,
      !BearHIDNoteFocusPlan.isValid(noteID: noteID)
    {
      throw HarnessError.usage("Bear note ID must be a UUID.")
    }
    return options
  }

  static let usage = """
    Usage: typover-hid-harness <plan|snapshot|doctor|run> [options]

      plan      Print the deterministic test matrix; no board or UI needed.
      snapshot  Read bounded text around Bear's focused caret; no board needed.
      doctor    Check Typover, Bear, Accessibility, and fixture readiness.
      run       Wait for a quiet Mac, then type the matrix into focused Bear.

    Load profiles: quiet (default), cpu, window-server, accessibility, combined.
    Every contention run first requires the same three-sample quiet baseline.

    Scenarios: repeated-words (default) or punctuation.

    Run requires --exclusive-desktop-confirmed and --bear-note-id <UUID>.
    The explicit disposable note prevents physical input from reaching a
    different Bear note after the nonactivating Jig opens.
  """
}

private extension SnapshotReport {
  static func empty(status: String) -> SnapshotReport {
    SnapshotReport(
      status: status,
      leadingRange: nil,
      leadingText: nil,
      trailingText: nil,
      caretLocation: nil,
      documentLength: nil
    )
  }
}

@main
@MainActor
private enum TypoverBearHIDHarness {
  static func main() {
    do {
      let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
      let plan = try BearHIDTestPlan(
        scenario: options.scenario,
        intervalsMilliseconds: options.intervals,
        wordsPerCase: options.words
      )
      switch options.command {
      case "plan":
        try printJSON(plan)
      case "snapshot":
        try snapshot()
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

  private static func snapshot() throws {
    let report: SnapshotReport = switch BearTypingContextReader(
      leadingLimit: 256,
      trailingLimit: 64
    ).read() {
    case .ready(let value):
      SnapshotReport(
        status: "ready",
        leadingRange: value.leadingRange,
        leadingText: value.leadingText,
        trailingText: value.trailingText,
        caretLocation: value.caretLocation,
        documentLength: value.documentLength
      )
    case .accessibilityPermissionRequired:
      SnapshotReport.empty(status: "accessibilityPermissionRequired")
    case .bearNotRunning:
      SnapshotReport.empty(status: "bearNotRunning")
    case .bearNotFrontmost:
      SnapshotReport.empty(status: "bearNotFrontmost")
    case .focusedEditorUnavailable:
      SnapshotReport.empty(status: "focusedEditorUnavailable")
    case .selectionActive:
      SnapshotReport.empty(status: "selectionActive")
    case .contextUnavailable:
      SnapshotReport.empty(status: "contextUnavailable")
    }
    try printJSON(report)
  }

  private static func doctor(options: Options, plan: BearHIDTestPlan) throws {
    let fileManager = FileManager.default
    let clientReady = fileManager.isExecutableFile(atPath: options.fixtureClient)
    let jigToolReady = fileManager.isExecutableFile(atPath: options.jigTool)
    let jigClientReady = fileManager.isExecutableFile(atPath: options.jigClient)
    let typoverRunning = !NSRunningApplication.runningApplications(
      withBundleIdentifier: "com.malpern.typover"
    ).isEmpty
    let privateDiagnostics =
      UserDefaults.standard.persistentDomain(
        forName: "com.malpern.typover"
      )?["bear-private-diagnostics-enabled"] as? Bool ?? false
    let probe = BearAccessibilityProbe().run()
    let bearFrontmost =
      NSWorkspace.shared.frontmostApplication?.bundleIdentifier
      == BearAccessibilityProbe.bearBundleIdentifier
    var fixtureStatus: FixtureStatus?
    var fixtureError: String?
    if clientReady {
      do {
        let fixtureHost = resolvedFixtureHost(
          options.fixtureHost,
          runner: CommandRunner()
        )
        fixtureStatus = try FixtureController(
          clientPath: options.fixtureClient,
          host: fixtureHost,
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
          && probe.status == .ready && bearFrontmost,
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
    guard FileManager.default.isExecutableFile(atPath: options.bearCLI) else {
      throw HarnessError.commandFailed(
        "Bear CLI is missing or not executable: \(options.bearCLI)"
      )
    }
    guard let bearNoteID = options.bearNoteID else {
      throw HarnessError.usage(
        "run requires --bear-note-id <UUID>; physical input may target only an explicit disposable note."
      )
    }
    guard FileManager.default.isExecutableFile(atPath: options.jigTool),
      FileManager.default.isExecutableFile(atPath: options.jigClient)
    else {
      throw HarnessError.commandFailed(
        "The HID Capture Jig tool or client is missing."
      )
    }
    guard
      !NSRunningApplication.runningApplications(
        withBundleIdentifier: "com.malpern.typover"
      ).isEmpty
    else {
      throw HarnessError.commandFailed("Typover is not running.")
    }

    let awakeSession = AwakeSession()
    try awakeSession.start()
    defer { awakeSession.stop() }

    let fixtureHost = resolvedFixtureHost(
      options.fixtureHost,
      runner: CommandRunner()
    )
    if fixtureHost != options.fixtureHost {
      print("Resolved fixture \(options.fixtureHost) to \(fixtureHost).")
    }
    let fixture = FixtureController(
      clientPath: options.fixtureClient,
      host: fixtureHost,
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
      next: "\(plan.cases.count) TIMING CASES"
    )

    print("Waiting for three quiet host samples (>=60% CPU idle, no Swift compiler)…")
    let readiness = try waitForQuietHost(
      timeoutSeconds: options.quietTimeoutSeconds
    )
    print("Opening the explicit Bear test note and verifying its terminal caret…")
    try focusBearNote(noteID: bearNoteID, cliPath: options.bearCLI)
    try waitForSafeBearCaret(timeoutSeconds: 120)

    let loadSession = ControlledLoadSession(profile: options.loadProfile)
    if options.loadProfile != .quiet {
      print("Starting controlled \(options.loadProfile.rawValue) contention…")
    }
    try loadSession.start()
    defer { loadSession.stop() }
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    try requireSafeBearCaret()

    let outputDirectory = URL(
      fileURLWithPath: options.outputDirectory
        ?? (FileManager.default.homeDirectoryForCurrentUser.path
          + "/.local/state/typover/bear-hid/\(matrixRunID)"))
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
        readiness: readiness,
        requiresLoadEvidence: options.loadProfile != .quiet
      )
      caseArtifacts.append(artifact)
      try writeJSON(
        artifact,
        to: outputDirectory.appendingPathComponent(
          "case-\(testCase.ordinal)-\(testCase.intervalMilliseconds)ms.json"
        )
      )
      print(
        "\(testCase.intervalMilliseconds) ms: \(artifact.analysis.correctedWords)/\(testCase.words) corrected (\(artifact.evidenceClassification); \(artifact.overlayRetention.conciseDescription))"
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
      schemaVersion: 5,
      runID: matrixRunID,
      createdAt: Date(),
      host: fixture.host,
      plan: plan,
      loadProfile: options.loadProfile,
      classification: classification,
      cases: caseArtifacts,
      privacyNote:
        "Contains only synthetic test text, content-free Typover unified-log events, and process/resource samples. File permissions are 0600. Typover's optional bounded-writing trace is stored separately and is never copied into this artifact."
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
    readiness: [HostReadinessSample],
    requiresLoadEvidence: Bool
  ) throws -> CaseArtifact {
    let loadSampler = HostLoadSampler()
    loadSampler.start()
    var samplerStopped = false
    defer {
      if !samplerStopped {
        _ = loadSampler.stop()
      }
    }
    let reader = BearTypingContextReader(leadingLimit: 256, trailingLimit: 24)
    guard case .ready(let baseline) = reader.read(),
      baseline.caretLocation == baseline.documentLength,
      baseline.trailingText.isEmpty
    else {
      throw HarnessError.unsafeFocus(
        "Bear must be frontmost with a collapsed caret at the end of the disposable test note."
      )
    }
    let baselineVisibleCorrectionCount =
      TypoverCorrectionOverlayCounter.visibleCount()

    let shortMatrixID =
      matrixRunID
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
    var focusLossBundleIdentifier: String?
    while Date() < typingDeadline {
      let frontmostBundleIdentifier =
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
      if frontmostBundleIdentifier != BearAccessibilityProbe.bearBundleIdentifier
      {
        focusRemainedValid = false
        focusLossBundleIdentifier = frontmostBundleIdentifier ?? "unavailable"
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
      // The ESP32 status endpoint can take a little over five seconds after a
      // display-heavy run. Preserve the fixture proof instead of invalidating
      // an otherwise complete trace at the former two-second request limit.
      let deadline = Date().addingTimeInterval(12)
      repeat {
        finalStatus = try? fixture.status(timeout: 8)
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
    }

    let observationStartedAt = Date()
    let minimumObservationDeadline = observationStartedAt.addingTimeInterval(
      Double(testCase.settleMilliseconds) / 1_000
    )
    let convergenceDeadline = observationStartedAt.addingTimeInterval(
      Double(testCase.maximumConvergenceMilliseconds) / 1_000
    )
    var finalSnapshot: BearTypingContextSnapshot?
    var convergedAt: Date?
    while focusRemainedValid, Date() < convergenceDeadline {
      let frontmostBundleIdentifier =
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
      guard
        frontmostBundleIdentifier
          == BearAccessibilityProbe.bearBundleIdentifier
      else {
        focusRemainedValid = false
        focusLossBundleIdentifier = frontmostBundleIdentifier ?? "unavailable"
        break
      }
      if case .ready(let snapshot) = reader.read() {
        finalSnapshot = snapshot
        let candidate = BearHIDTextEvidence.insertedText(
          baselineCaret: baseline.caretLocation,
          finalCaret: snapshot.caretLocation,
          finalLeadingText: snapshot.leadingText,
          expectedLength: testCase.expectedUTF16Length
        )
        if candidate == testCase.fullyCorrectedText {
          if convergedAt == nil {
            convergedAt = Date()
          }
          if Date() >= minimumObservationDeadline {
            break
          }
        } else {
          convergedAt = nil
        }
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    if finalSnapshot == nil, case .ready(let snapshot) = reader.read() {
      finalSnapshot = snapshot
    }
    let observationFinishedAt = Date()
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
    let overlayRetention = BearHIDOverlayRetentionEvidence(
      baselineVisibleCorrections: baselineVisibleCorrectionCount,
      finalVisibleCorrections: TypoverCorrectionOverlayCounter.visibleCount(),
      correctedWords: analysis.correctedWords,
      maximumTrackedCorrections:
        BearAnnotationOverlayCollectionController
          .defaultMaximumTrackedCorrections
    )
    let loadSamples = loadSampler.stop()
    samplerStopped = true
    let loadEvidenceComplete = !requiresLoadEvidence
      || (!loadSamples.isEmpty && loadSamples.allSatisfy(\.isComplete))
    let evidenceClassification: String
    if !focusRemainedValid || finalStatus?.state != "complete"
      || finalStatus?.runId != runID
      || telemetry.applied != analysis.correctedWords
      || !loadEvidenceComplete
    {
      evidenceClassification = "invalid-evidence"
    } else {
      evidenceClassification = analysis.classification.rawValue
    }
    let monitorPhase: String =
      switch evidenceClassification {
      case "passed": "passed"
      case "safe-misses-observed": "safeMisses"
      default: "failed"
      }
    let monitorMessage: String =
      switch evidenceClassification {
      case "passed":
        "All \(analysis.correctedWords) corrections matched Typover log evidence · \(overlayRetention.conciseDescription)."
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
    let fixtureResult =
      switch evidenceClassification {
      case "passed": "pass"
      case "safe-misses-observed": "inconclusive"
      default: "fail"
      }
    let fixtureTitle =
      switch evidenceClassification {
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
      focusLossBundleIdentifier: focusLossBundleIdentifier,
      baselineCaret: baseline.caretLocation,
      finalCaret: finalSnapshot?.caretLocation,
      baselineDocumentLength: baseline.documentLength,
      finalDocumentLength: finalSnapshot?.documentLength,
      analysis: analysis,
      evidenceClassification: evidenceClassification,
      fixtureStatus: finalStatus,
      fixtureTraceJSON: trace,
      telemetry: telemetry,
      overlayRetention: overlayRetention,
      typoverLog: logs,
      readinessSamples: readiness,
      loadSamples: loadSamples,
      loadEvidenceComplete: loadEvidenceComplete,
      postFixtureObservationMilliseconds:
        observationStartedAt.distance(to: observationFinishedAt) * 1_000,
      convergedAfterMilliseconds: convergedAt.map {
        observationStartedAt.distance(to: $0) * 1_000
      }
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

  private static func focusBearNote(
    noteID: String,
    cliPath: String
  ) throws {
    let runner = CommandRunner()
    let contentResult = try runner.run(
      cliPath,
      ["cat", noteID, "--format", "json"],
      timeout: 10
    )
    guard contentResult.status == 0,
      let data = contentResult.output.data(using: .utf8),
      let note = try? JSONDecoder().decode(BearCLIContent.self, from: data),
      let arguments = BearHIDNoteFocusPlan.openArguments(
        noteID: noteID,
        content: note.content
      )
    else {
      throw HarnessError.commandFailed(
        "Bear CLI could not read the explicit disposable test note."
      )
    }
    let openResult = try runner.run(cliPath, arguments, timeout: 10)
    guard openResult.status == 0 else {
      throw HarnessError.commandFailed(
        "Bear CLI could not open the explicit disposable test note: "
          + openResult.error.trimmingCharacters(in: .whitespacesAndNewlines)
      )
    }
    guard
      let bear = NSRunningApplication.runningApplications(
        withBundleIdentifier: BearAccessibilityProbe.bearBundleIdentifier
      ).first
    else {
      throw HarnessError.unsafeFocus(
        "Bear is not running after its CLI opened the disposable test note."
      )
    }
    // The CLI targets the exact note and terminal UTF-8 offset. App activation
    // remains advisory; the bounded AX check that follows proves that Bear is
    // frontmost with a collapsed caret at the document end before HID starts.
    _ = bear.activate(options: [.activateAllWindows])
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
      guard
        let line = result.output.split(separator: "\n").first(where: {
          $0.contains("CPU usage:")
        }),
        let range = line.range(of: #"([0-9.]+)% idle"#, options: .regularExpression)
      else { return nil }
      return Double(line[range].dropLast("% idle".count))
    }
    let processList = try? runner.run(
      "/bin/ps",
      ["-axo", "pid=,comm="],
      timeout: 2
    )
    let compilers =
      processList?.status == 0
      ? SwiftCompilerProcessDetector.compilerProcesses(
        in: processList!.output
      )
      : []
    return HostReadinessSample(
      timestamp: Date(),
      cpuIdlePercent: idle,
      activeSwiftCompilers: compilers
    )
  }

  private static func resolvedFixtureHost(
    _ host: String,
    runner: CommandRunner
  ) -> String {
    guard host.hasSuffix(".local") else { return host }
    guard
      let result = try? runner.run(
        "/usr/bin/dscacheutil",
        ["-q", "host", "-a", "name", host],
        timeout: 8
      ),
      result.status == 0,
      let line = result.output.split(separator: "\n").first(where: {
        $0.trimmingCharacters(in: .whitespaces).hasPrefix("ip_address:")
      }),
      let address = line.split(separator: ":", maxSplits: 1).last?
        .trimmingCharacters(in: .whitespaces),
      !address.isEmpty
    else {
      return host
    }
    return address
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
        + count("outcome=deferredReplacementRefused"),
      valueBeforeBoundaryCallback: count(
        "Bear value change preceded completion-boundary callback"
      ),
      boundaryToValueMilliseconds: logs.compactMap {
        BearHIDTelemetryParsing.boundaryToValueMilliseconds(from: $0)
      },
      correctionLatencyMilliseconds: logs.compactMap { line in
        guard line.contains("Automatic correction applied") else {
          return nil
        }
        return BearHIDTelemetryParsing.correctionLatencyMilliseconds(from: line)
      }
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
