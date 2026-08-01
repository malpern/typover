import Foundation

public enum HostLoadSamplingPlan {
  public static let sampleDelaySeconds = 1

  public static func topArguments(
    processIdentifiers: [String]
  ) -> [String] {
    var arguments = [
      "-l", "2",
      "-s", String(sampleDelaySeconds),
      "-stats", "pid,cpu,mem,power,command",
    ]
    for processIdentifier in processIdentifiers {
      arguments += ["-pid", processIdentifier]
    }
    return arguments
  }

  public static func cpuIdlePercent(from topOutput: String) -> Double? {
    guard
      let line = topOutput.split(separator: "\n").last(where: {
        $0.contains("CPU usage:")
      }),
      let range = line.range(
        of: #"([0-9.]+)% idle"#,
        options: .regularExpression
      )
    else {
      return nil
    }
    return Double(line[range].dropLast("% idle".count))
  }

  public static func powerScores(
    from topOutput: String,
    processNames: Set<String>
  ) -> [String: Double] {
    var result: [String: Double] = [:]
    for line in topOutput.split(separator: "\n") {
      let fields = line.split(
        maxSplits: 4,
        omittingEmptySubsequences: true,
        whereSeparator: { $0.isWhitespace }
      )
      guard fields.count == 5 else { continue }
      let name = String(fields[4])
      guard processNames.contains(name),
        let power = Double(fields[3])
      else {
        continue
      }
      result[name] = power
    }
    return result
  }
}
