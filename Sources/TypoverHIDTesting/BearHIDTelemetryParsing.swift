import Foundation

public enum BearHIDTelemetryParsing {
  public static func correctionLatencyMilliseconds(
    from logLine: String
  ) -> Double? {
    guard
      let range = logLine.range(
        of: #"latencyMs=([0-9]+(?:,[0-9]{3})*(?:\.[0-9]+)?)(?=\s|$)"#,
        options: .regularExpression
      )
    else { return nil }
    let token = logLine[range]
      .dropFirst("latencyMs=".count)
      .replacingOccurrences(of: ",", with: "")
    return Double(token)
  }
}
