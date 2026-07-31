import Foundation

public struct BearHIDTestPlan: Codable, Equatable, Sendable {
  public let intervalsMilliseconds: [Int]
  public let wordsPerCase: Int
  public let holdMilliseconds: Int
  public let startDelayMilliseconds: Int
  public let settleMilliseconds: Int

  public init(
    intervalsMilliseconds: [Int] = [160, 100, 60, 40],
    wordsPerCase: Int = 20,
    holdMilliseconds: Int = 12,
    startDelayMilliseconds: Int = 1_500,
    settleMilliseconds: Int = 1_500
  ) throws {
    guard !intervalsMilliseconds.isEmpty,
      intervalsMilliseconds.allSatisfy({ $0 >= 4 }),
      Set(intervalsMilliseconds).count == intervalsMilliseconds.count
    else {
      throw BearHIDTestPlanError.invalidIntervals
    }
    guard (1 ... 50).contains(wordsPerCase) else {
      throw BearHIDTestPlanError.invalidWordCount
    }
    guard holdMilliseconds >= 2,
      intervalsMilliseconds.allSatisfy({ holdMilliseconds < $0 })
    else {
      throw BearHIDTestPlanError.invalidHoldDuration
    }
    guard (100 ... 60_000).contains(startDelayMilliseconds) else {
      throw BearHIDTestPlanError.invalidStartDelay
    }
    guard (250 ... 10_000).contains(settleMilliseconds) else {
      throw BearHIDTestPlanError.invalidSettleDelay
    }

    self.intervalsMilliseconds = intervalsMilliseconds
    self.wordsPerCase = wordsPerCase
    self.holdMilliseconds = holdMilliseconds
    self.startDelayMilliseconds = startDelayMilliseconds
    self.settleMilliseconds = settleMilliseconds
  }

  public var cases: [BearHIDTestCase] {
    intervalsMilliseconds.enumerated().map { index, interval in
      BearHIDTestCase(
        ordinal: index + 1,
        intervalMilliseconds: interval,
        words: wordsPerCase,
        holdMilliseconds: holdMilliseconds,
        startDelayMilliseconds: startDelayMilliseconds,
        settleMilliseconds: settleMilliseconds
      )
    }
  }
}

public enum BearHIDTestPlanError: Error, Equatable, Sendable {
  case invalidIntervals
  case invalidWordCount
  case invalidHoldDuration
  case invalidStartDelay
  case invalidSettleDelay
}

public struct BearHIDTestCase: Codable, Equatable, Sendable {
  public let ordinal: Int
  public let intervalMilliseconds: Int
  public let words: Int
  public let holdMilliseconds: Int
  public let startDelayMilliseconds: Int
  public let settleMilliseconds: Int

  public var typedText: String {
    String(repeating: "teh ", count: words) + "\n"
  }

  public var fullyCorrectedText: String {
    String(repeating: "the ", count: words) + "\n"
  }

  public var expectedUTF16Length: Int {
    typedText.utf16.count
  }

  public var executionMilliseconds: Int {
    expectedUTF16Length * intervalMilliseconds + startDelayMilliseconds
      + settleMilliseconds
  }

  public func fixtureArguments(
    command: String,
    runID: String,
    filePath: String? = nil
  ) -> [String] {
    switch command {
    case "compile-text":
      guard let filePath else { return [] }
      return [
        "compile-text", "--run-id", runID,
        "--text", filePath,
        "--interval-ms", String(intervalMilliseconds),
        "--hold-ms", String(holdMilliseconds),
        "--repeat", "1",
        "--cycle-gap-ms", "0",
        "--output", filePath + ".kphid",
      ]
    case "load-script":
      guard let filePath else { return [] }
      return ["load-script", filePath + ".kphid"]
    case "arm":
      return ["arm", runID]
    case "start":
      return [
        "start", runID, "--delay-ms", String(startDelayMilliseconds),
      ]
    default:
      return []
    }
  }
}

public enum BearHIDCaseClassification: String, Codable, Equatable, Sendable {
  case passed
  case safeMissesObserved = "safe-misses-observed"
  case unexpectedText = "unexpected-text"
  case invalidEvidence = "invalid-evidence"
}

public struct BearHIDCaseAnalysis: Codable, Equatable, Sendable {
  public let classification: BearHIDCaseClassification
  public let expectedWords: Int
  public let correctedWords: Int
  public let missedWords: Int
  public let unexpectedChunks: Int
  public let hadExpectedTrailingNewline: Bool
  public let actualText: String

  public init(testCase: BearHIDTestCase, actualText: String?) {
    guard let actualText,
      actualText.utf16.count == testCase.expectedUTF16Length
    else {
      classification = .invalidEvidence
      expectedWords = testCase.words
      correctedWords = 0
      missedWords = 0
      unexpectedChunks = 0
      hadExpectedTrailingNewline = false
      self.actualText = actualText ?? ""
      return
    }

    let body = String(actualText.dropLast())
    var correctedWords = 0
    var missedWords = 0
    var unexpectedChunks = 0
    let units = Array(body.utf16)
    for offset in stride(from: 0, to: units.count, by: 4) {
      let end = min(offset + 4, units.count)
      let chunk = String(decoding: units[offset ..< end], as: UTF16.self)
      switch chunk {
      case "the ": correctedWords += 1
      case "teh ": missedWords += 1
      default: unexpectedChunks += 1
      }
    }
    let trailingNewline = actualText.last == "\n"
    let classification: BearHIDCaseClassification
    if !trailingNewline || unexpectedChunks > 0 {
      classification = .unexpectedText
    } else if correctedWords == testCase.words {
      classification = .passed
    } else if correctedWords + missedWords == testCase.words {
      classification = .safeMissesObserved
    } else {
      classification = .unexpectedText
    }

    self.classification = classification
    expectedWords = testCase.words
    self.correctedWords = correctedWords
    self.missedWords = missedWords
    self.unexpectedChunks = unexpectedChunks
    hadExpectedTrailingNewline = trailingNewline
    self.actualText = actualText
  }
}

public enum BearHIDTextEvidence {
  public static func insertedText(
    baselineCaret: Int,
    finalCaret: Int,
    finalLeadingText: String,
    maximumLength: Int = 256
  ) -> String? {
    let insertedLength = finalCaret - baselineCaret
    guard insertedLength >= 0,
      insertedLength <= maximumLength,
      finalLeadingText.utf16.count >= insertedLength
    else {
      return nil
    }
    return String(
      decoding: Array(finalLeadingText.utf16.suffix(insertedLength)),
      as: UTF16.self
    )
  }
}
