import Foundation

public enum BearHIDTelemetryParsing {
  public static func correctionLatencyMilliseconds(
    from logLine: String
  ) -> Double? {
    milliseconds(named: "latencyMs", from: logLine)
  }

  public static func boundaryToValueMilliseconds(
    from logLine: String
  ) -> Double? {
    milliseconds(named: "arrivalMs", from: logLine)
  }

  public static func preDispatchCallbackMilliseconds(
    from logLine: String
  ) -> Double? {
    milliseconds(named: "callbackMs", from: logLine)
  }

  private static func milliseconds(
    named field: String,
    from logLine: String
  ) -> Double? {
    guard
      let range = logLine.range(
        of: "\(field)=([0-9]+(?:,[0-9]{3})*(?:\\.[0-9]+)?)(?=\\s|$)",
        options: .regularExpression
      )
    else { return nil }
    let token = logLine[range]
      .dropFirst(field.count + 1)
      .replacingOccurrences(of: ",", with: "")
    return Double(token)
  }
}
