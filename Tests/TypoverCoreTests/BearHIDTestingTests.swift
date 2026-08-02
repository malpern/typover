import Foundation
import Testing
import TypoverHIDTesting

@Suite("Bear physical HID testing")
struct BearHIDTestingTests {
  @Test("Load profiles expose only their requested contention sources")
  func loadProfiles() {
    #expect(BearHIDLoadProfile.quiet.stressesCPU == false)
    #expect(BearHIDLoadProfile.quiet.stressesWindowServer == false)
    #expect(BearHIDLoadProfile.quiet.stressesAccessibility == false)
    #expect(BearHIDLoadProfile.cpu.stressesCPU)
    #expect(BearHIDLoadProfile.windowServer.stressesWindowServer)
    #expect(BearHIDLoadProfile.accessibility.stressesAccessibility)
    #expect(BearHIDLoadProfile.combined.stressesCPU)
    #expect(BearHIDLoadProfile.combined.stressesWindowServer)
    #expect(BearHIDLoadProfile.combined.stressesAccessibility)
  }

  @Test("Wake assertion keeps user activity alive through quiet admission")
  func wakeAssertionPlan() {
    let arguments = HostWakeAssertionPlan.caffeinateArguments(
      parentProcessIdentifier: 42
    )

    #expect(arguments == ["-dimsu", "-t", "3600", "-w", "42"])
    #expect(HostWakeAssertionPlan.maximumDurationSeconds > 5)
  }

  @Test("Host load sampling uses a macOS-compatible top interval")
  func hostLoadSamplingPlan() {
    let arguments = HostLoadSamplingPlan.topArguments(
      processIdentifiers: ["42", "84"]
    )

    #expect(arguments == [
      "-l", "2", "-s", "1",
      "-stats", "pid,cpu,mem,power,command",
      "-pid", "42", "-pid", "84",
    ])
  }

  @Test("Host load sampling parses macOS 27 CPU and PID power rows")
  func hostLoadSamplingParsers() {
    let output = """
      CPU usage: 10.0% user, 5.0% sys, 85.0% idle
      PID  %CPU MEM  POWER COMMAND
      760  0.0  68M  0.0   Typover
      CPU usage: 20.0% user, 5.0% sys, 75.0% idle
      PID  %CPU MEM  POWER COMMAND
      453  44.2 514M 44.9  WindowServer
      760  2.1  68M  2.1   Typover
      737  1.0  135M 1.0   Bear
      """

    #expect(HostLoadSamplingPlan.cpuIdlePercent(from: output) == 75)
    #expect(
      HostLoadSamplingPlan.powerScoresByProcessIdentifier(from: output) == [
        "453": 44.9,
        "760": 2.1,
        "737": 1.0,
      ]
    )
  }

  @Test("Overlay retention is exact only from an empty baseline")
  func overlayRetentionEvidence() {
    let exact = BearHIDOverlayRetentionEvidence(
      baselineVisibleCorrections: 0,
      finalVisibleCorrections: 20,
      correctedWords: 20,
      maximumTrackedCorrections: 24
    )
    #expect(exact.expectedVisibleCorrectionsFromEmptyBaseline == 20)
    #expect(exact.fullyRetainedFromEmptyBaseline == true)

    let capped = BearHIDOverlayRetentionEvidence(
      baselineVisibleCorrections: 0,
      finalVisibleCorrections: 24,
      correctedWords: 30,
      maximumTrackedCorrections: 24
    )
    #expect(capped.fullyRetainedFromEmptyBaseline == true)

    let priorCorrections = BearHIDOverlayRetentionEvidence(
      baselineVisibleCorrections: 4,
      finalVisibleCorrections: 24,
      correctedWords: 20,
      maximumTrackedCorrections: 24
    )
    #expect(priorCorrections.fullyRetainedFromEmptyBaseline == nil)

    let missing = BearHIDOverlayRetentionEvidence(
      baselineVisibleCorrections: 0,
      finalVisibleCorrections: 19,
      correctedWords: 20,
      maximumTrackedCorrections: 24
    )
    #expect(missing.fullyRetainedFromEmptyBaseline == false)
  }

  @Test("Correction latency accepts historical grouped and stable numeric logs")
  func correctionLatencyParsing() {
    #expect(
      BearHIDTelemetryParsing.correctionLatencyMilliseconds(
        from: "Automatic correction applied latencyMs=4,774.841"
      ) == 4_774.841
    )
    #expect(
      BearHIDTelemetryParsing.correctionLatencyMilliseconds(
        from: "Automatic correction applied latencyMs=431.781"
      ) == 431.781
    )
    #expect(
      BearHIDTelemetryParsing.correctionLatencyMilliseconds(
        from: "Automatic correction applied latencyMs=none"
      ) == nil
    )
    #expect(
      BearHIDTelemetryParsing.correctionLatencyMilliseconds(
        from: "Automatic correction applied latencyMs=4,77.841"
      ) == nil
    )
    #expect(
      BearHIDTelemetryParsing.boundaryToValueMilliseconds(
        from: "Bear completion boundary reached AX value change arrivalMs=18.625"
      ) == 18.625
    )
    #expect(
      BearHIDTelemetryParsing.boundaryToValueMilliseconds(
        from: "Automatic correction applied latencyMs=431.781"
      ) == nil
    )
  }

  @Test("Default matrix spans realistic through burst typing")
  func defaultMatrix() throws {
    let plan = try BearHIDTestPlan()

    #expect(plan.intervalsMilliseconds == [160, 100, 60, 40])
    #expect(plan.cases.count == 4)
    #expect(plan.cases.allSatisfy { $0.words == 20 })
    #expect(plan.cases.allSatisfy { $0.typedText.utf16.count == 81 })
    #expect(
      plan.cases.allSatisfy { $0.maximumConvergenceMilliseconds == 10_000 }
    )
  }

  @Test("Explicit Bear note focus targets the terminal CLI byte offset")
  func explicitBearNoteFocus() throws {
    let noteID = "01234567-89AB-CDEF-0123-456789ABCDEF"
    let content = "# Týpover test\n"

    #expect(BearHIDNoteFocusPlan.isValid(noteID: noteID))
    #expect(BearHIDNoteFocusPlan.terminalByteOffset(for: content) == 16)
    #expect(
      BearHIDNoteFocusPlan.openArguments(
        noteID: noteID,
        content: content
      ) == [
        "app", "open", noteID,
        "--selection-offset", "16",
        "--selection-length", "0",
      ]
    )
  }

  @Test("Explicit Bear note focus refuses invalid IDs and handles empty notes")
  func invalidBearNoteFocus() {
    #expect(!BearHIDNoteFocusPlan.isValid(noteID: "current-note"))
    #expect(
      BearHIDNoteFocusPlan.openArguments(
        noteID: "current-note",
        content: ""
      ) == nil
    )
    #expect(BearHIDNoteFocusPlan.terminalByteOffset(for: "") == 0)
    #expect(BearHIDNoteFocusPlan.terminalByteOffset(for: "body") == 4)
    #expect(BearHIDNoteFocusPlan.terminalByteOffset(for: "body\n") == 5)
  }

  @Test("Punctuation scenario cycles through completion boundaries")
  func punctuationScenario() throws {
    let testCase = try #require(
      BearHIDTestPlan(
        scenario: .punctuation,
        intervalsMilliseconds: [100],
        wordsPerCase: 5
      ).cases.first
    )

    #expect(testCase.typedText == "teh. teh? teh! teh; teh: \n")
    #expect(testCase.fullyCorrectedText == "the. the? the! the; the: \n")

    let analysis = BearHIDCaseAnalysis(
      testCase: testCase,
      actualText: "the. teh? the! teh; the: \n"
    )
    #expect(analysis.classification == .safeMissesObserved)
    #expect(analysis.correctedWords == 3)
    #expect(analysis.missedWords == 2)
    #expect(analysis.unexpectedChunks == 0)
  }

  @Test("Plan refuses timing the fixture cannot deliver")
  func invalidTiming() {
    #expect(throws: BearHIDTestPlanError.invalidIntervals) {
      try BearHIDTestPlan(intervalsMilliseconds: [3])
    }
    #expect(throws: BearHIDTestPlanError.invalidHoldDuration) {
      try BearHIDTestPlan(
        intervalsMilliseconds: [12],
        holdMilliseconds: 12
      )
    }
    #expect(throws: BearHIDTestPlanError.invalidConvergenceDelay) {
      try BearHIDTestPlan(
        settleMilliseconds: 1_500,
        maximumConvergenceMilliseconds: 1_499
      )
    }
  }

  @Test("Fixture arguments use one continuous text burst")
  func fixtureContract() throws {
    let testCase = try #require(BearHIDTestPlan().cases.first)
    let arguments = testCase.fixtureArguments(
      command: "compile-text",
      runID: "case-1",
      filePath: "/tmp/input.txt"
    )

    #expect(arguments.contains("--repeat"))
    #expect(arguments[arguments.firstIndex(of: "--repeat")! + 1] == "1")
    #expect(arguments[arguments.firstIndex(of: "--cycle-gap-ms")! + 1] == "0")
    #expect(arguments[arguments.firstIndex(of: "--interval-ms")! + 1] == "160")
  }

  @Test("Compiler guard matches executable names, not shell command text")
  func compilerProcessDetection() {
    let processList = """
        101 /bin/zsh
        102 /usr/bin/ssh
        103 /usr/bin/swift-frontend
        104 /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-driver
        105 /usr/bin/swiftc
      """

    let matches = SwiftCompilerProcessDetector.compilerProcesses(
      in: processList
    )

    #expect(matches.count == 3)
    #expect(matches.contains("103 /usr/bin/swift-frontend"))
    #expect(matches.contains(where: { $0.hasSuffix("/swift-driver") }))
    #expect(matches.contains("105 /usr/bin/swiftc"))
  }

  @Test("Analysis distinguishes corrections from safe misses")
  func correctionAnalysis() throws {
    let testCase = try #require(
      BearHIDTestPlan(intervalsMilliseconds: [80], wordsPerCase: 4).cases.first
    )
    let analysis = BearHIDCaseAnalysis(
      testCase: testCase,
      actualText: "the teh the teh \n"
    )

    #expect(analysis.classification == .safeMissesObserved)
    #expect(analysis.correctedWords == 2)
    #expect(analysis.missedWords == 2)
    #expect(analysis.unexpectedChunks == 0)
  }

  @Test("A completely corrected burst passes")
  func correctedBurst() throws {
    let testCase = try #require(
      BearHIDTestPlan(intervalsMilliseconds: [100], wordsPerCase: 3).cases.first
    )
    let analysis = BearHIDCaseAnalysis(
      testCase: testCase,
      actualText: testCase.fullyCorrectedText
    )

    #expect(analysis.classification == .passed)
    #expect(analysis.correctedWords == 3)
    #expect(analysis.missedWords == 0)
  }

  @Test("Unexpected edits invalidate correction evidence")
  func unexpectedText() throws {
    let testCase = try #require(
      BearHIDTestPlan(intervalsMilliseconds: [80], wordsPerCase: 2).cases.first
    )

    #expect(
      BearHIDCaseAnalysis(
        testCase: testCase,
        actualText: "the xxx \n"
      ).classification == .unexpectedText
    )
    #expect(
      BearHIDCaseAnalysis(
        testCase: testCase,
        actualText: "the teh "
      ).classification == .invalidEvidence
    )
  }

  @Test("Evidence extraction is UTF-16 exact and bounded")
  func insertedEvidence() {
    #expect(
      BearHIDTextEvidence.insertedText(
        baselineCaret: 5,
        finalCaret: 13,
        finalLeadingText: "olderthe teh "
      ) == "the teh "
    )
    #expect(
      BearHIDTextEvidence.insertedText(
        baselineCaret: 0,
        finalCaret: 300,
        finalLeadingText: String(repeating: "a", count: 300)
      ) == nil
    )
    #expect(
      BearHIDTextEvidence.insertedText(
        baselineCaret: 10,
        finalCaret: 9,
        finalLeadingText: "text"
      ) == nil
    )
    #expect(
      BearHIDTextEvidence.insertedText(
        baselineCaret: 90,
        finalCaret: 10,
        finalLeadingText: "\u{FFFC}the teh \n",
        expectedLength: 9
      ) == "the teh \n"
    )
    #expect(
      BearHIDTextEvidence.insertedText(
        baselineCaret: 90,
        finalCaret: 10,
        finalLeadingText: "Xthe teh \n",
        expectedLength: 9
      ) == nil
    )
  }
}
