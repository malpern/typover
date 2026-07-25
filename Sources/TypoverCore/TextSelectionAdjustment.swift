import Foundation

public enum TextSelectionAdjustment {
  public static func afterReplacing(
    _ replacedRange: NSRange,
    withLength replacementLength: Int,
    selection: NSRange
  ) -> NSRange {
    if NSMaxRange(selection) <= replacedRange.location {
      return selection
    }

    if selection.location >= NSMaxRange(replacedRange) {
      return NSRange(
        location: selection.location + replacementLength - replacedRange.length,
        length: selection.length
      )
    }

    return NSRange(
      location: replacedRange.location + replacementLength,
      length: 0
    )
  }
}
