import Foundation

public enum SwiftCompilerProcessDetector {
  private static let executableNames: Set<String> = [
    "swift-build",
    "swift-driver",
    "swift-frontend",
    "swift-test",
    "swiftc",
  ]

  public static func compilerProcesses(in processList: String) -> [String] {
    processList.split(separator: "\n").compactMap { rawLine in
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      let fields = line.split(
        maxSplits: 1,
        whereSeparator: { $0.isWhitespace }
      )
      guard fields.count == 2 else { return nil }

      let executable = String(fields[1])
      let executableName = URL(fileURLWithPath: executable).lastPathComponent
      guard executableNames.contains(executableName) else { return nil }
      return line
    }
  }
}
