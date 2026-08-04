import Foundation

public enum HostWakeAssertionPlan {
  public static let maximumDurationSeconds = 3_600

  public static func caffeinateArguments(
    parentProcessIdentifier: Int32
  ) -> [String] {
    [
      "-dimsu",
      "-t",
      String(maximumDurationSeconds),
      "-w",
      String(parentProcessIdentifier),
    ]
  }
}
