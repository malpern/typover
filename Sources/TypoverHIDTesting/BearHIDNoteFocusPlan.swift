import Foundation

public enum BearHIDNoteFocusPlan {
  public static func isValid(noteID: String) -> Bool {
    UUID(uuidString: noteID) != nil
  }

  public static func terminalByteOffset(for content: String) -> Int {
    content.utf8.count
  }

  public static func openArguments(
    noteID: String,
    content: String
  ) -> [String]? {
    guard isValid(noteID: noteID) else { return nil }
    return [
      "app", "open", noteID,
      "--selection-offset", String(terminalByteOffset(for: content)),
      "--selection-length", "0",
    ]
  }
}
