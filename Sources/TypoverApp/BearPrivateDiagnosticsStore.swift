import Foundation

enum BearPrivateDiagnosticsConfiguration {
  static let enabledDefaultsKey = "bear-private-diagnostics-enabled"
  static let includesWritingDefaultsKey =
    "bear-private-diagnostics-includes-writing"
  static let retentionHours = 24
  static let maximumBytes = 1_048_576
}

private struct BearPrivateDiagnosticRecord: Codable, Sendable {
  let timestamp: Date
  let event: String
  let boundedWriting: String?
}

final class BearPrivateDiagnosticsStore: @unchecked Sendable {
  static let shared = BearPrivateDiagnosticsStore()

  private let defaults: UserDefaults
  private let fileURL: URL
  private let queue = DispatchQueue(
    label: "com.malpern.typover.bear-private-diagnostics",
    qos: .utility
  )
  private var lastMaintenance = Date.distantPast

  convenience init() {
    let directory = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
      .appendingPathComponent("Typover", isDirectory: true)
      .appendingPathComponent("Diagnostics", isDirectory: true)
    self.init(
      defaults: .standard,
      fileURL: directory.appendingPathComponent("bear-private-trace.jsonl")
    )
  }

  init(defaults: UserDefaults, fileURL: URL) {
    self.defaults = defaults
    self.fileURL = fileURL
  }

  func record(_ message: String) {
    guard defaults.bool(
      forKey: BearPrivateDiagnosticsConfiguration.enabledDefaultsKey
    ) else {
      return
    }
    let includesWriting = defaults.bool(
      forKey: BearPrivateDiagnosticsConfiguration.includesWritingDefaultsKey
    )
    let record = BearPrivateDiagnosticRecord(
      timestamp: Date(),
      event: Self.contentFreeEvent(from: message),
      boundedWriting: includesWriting ? message : nil
    )
    queue.async { [self] in
      try? append(record)
    }
  }

  func export(to destination: URL) async throws {
    try await withCheckedThrowingContinuation { continuation in
      queue.async { [self] in
        do {
          try maintain(force: true)
          if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            try data.write(to: destination, options: .atomic)
          } else {
            try Data().write(to: destination, options: .atomic)
          }
          try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: destination.path
          )
          continuation.resume()
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  func delete() async throws {
    try await withCheckedThrowingContinuation { continuation in
      queue.async { [self] in
        do {
          if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
          }
          continuation.resume()
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  func size() async -> Int {
    await withCheckedContinuation { continuation in
      queue.async { [self] in
        let attributes = try? FileManager.default.attributesOfItem(
          atPath: fileURL.path
        )
        continuation.resume(
          returning: attributes?[.size] as? Int ?? 0
        )
      }
    }
  }

  /// Numeric fields that describe a correction's shape rather than its text.
  /// They are safe to keep in the content-free trace and are the difference
  /// between diagnosing a corrupt mapping in one run and chasing the host for
  /// a day.
  private static let contentFreeMetrics = ["editDistance=", "lengthDelta="]

  static func contentFreeEvent(from message: String) -> String {
    if let outcome = token(after: "outcome=", in: message) {
      let metrics = contentFreeMetrics.compactMap { prefix -> String? in
        guard let value = token(after: prefix, in: message) else {
          return nil
        }
        return "\(prefix)\(value)"
      }
      return (["outcome=\(outcome)"] + metrics).joined(separator: " ")
    }
    if let event = token(after: "accessibility event=", in: message) {
      return "accessibility=\(event)"
    }
    if let intent = token(after: "input intent=", in: message) {
      return intent.hasPrefix("completionBoundary")
        ? "input=completionBoundary"
        : "input=\(intent)"
    }
    if message.hasPrefix("baseline") {
      return "baseline"
    }
    if message.hasPrefix("evaluation") {
      return "evaluation"
    }
    return "diagnostic"
  }

  private static func token(after prefix: String, in message: String) -> String? {
    guard let range = message.range(of: prefix) else { return nil }
    let suffix = message[range.upperBound...]
    return suffix.prefix { !$0.isWhitespace && $0 != "(" }.description
  }

  private func append(_ record: BearPrivateDiagnosticRecord) throws {
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let line = try encoder.encode(record) + Data("\n".utf8)
    if !FileManager.default.fileExists(atPath: fileURL.path) {
      try line.write(to: fileURL, options: .atomic)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: fileURL.path
      )
    } else {
      let handle = try FileHandle(forWritingTo: fileURL)
      try handle.seekToEnd()
      try handle.write(contentsOf: line)
      try handle.close()
    }
    try maintain(force: false)
  }

  private func maintain(force: Bool) throws {
    let attributes = try? FileManager.default.attributesOfItem(
      atPath: fileURL.path
    )
    let size = attributes?[.size] as? Int ?? 0
    let now = Date()
    guard force || size > BearPrivateDiagnosticsConfiguration.maximumBytes
      || now.timeIntervalSince(lastMaintenance) >= 3_600
    else {
      return
    }
    lastMaintenance = now
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

    let data = try Data(contentsOf: fileURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let cutoff = now.addingTimeInterval(
      -Double(BearPrivateDiagnosticsConfiguration.retentionHours * 3_600)
    )
    var retained = data.split(separator: 0x0A).compactMap { line -> Data? in
      guard
        let record = try? decoder.decode(
          BearPrivateDiagnosticRecord.self,
          from: Data(line)
        ),
        record.timestamp >= cutoff
      else { return nil }
      return Data(line) + Data("\n".utf8)
    }
    var retainedBytes = retained.reduce(0) { $0 + $1.count }
    while retainedBytes > BearPrivateDiagnosticsConfiguration.maximumBytes,
      let first = retained.first
    {
      retainedBytes -= first.count
      retained.removeFirst()
    }
    let trimmed = retained.reduce(into: Data()) { result, line in
      result.append(line)
    }
    try trimmed.write(to: fileURL, options: .atomic)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: fileURL.path
    )
  }
}
