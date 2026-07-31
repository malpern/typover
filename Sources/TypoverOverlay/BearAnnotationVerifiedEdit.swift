import TypoverAccessibility

public struct BearAnnotationVerifiedEdit: Equatable, Sendable {
  public let replacedRange: AccessibilityTextRange
  public let replacementLength: Int

  public init(
    replacedRange: AccessibilityTextRange,
    replacementLength: Int
  ) {
    self.replacedRange = replacedRange
    self.replacementLength = replacementLength
  }

  public func transformedRange(
    for correctionRange: AccessibilityTextRange
  ) -> AccessibilityTextRange? {
    guard
      replacedRange.location >= 0,
      replacedRange.length >= 0,
      replacementLength >= 0,
      correctionRange.location >= 0,
      correctionRange.length >= 0
    else {
      return nil
    }
    let editEnd = replacedRange.location + replacedRange.length
    let correctionEnd = correctionRange.location + correctionRange.length

    if correctionEnd <= replacedRange.location {
      return correctionRange
    }
    if correctionRange.location >= editEnd {
      return AccessibilityTextRange(
        location: correctionRange.location
          + replacementLength - replacedRange.length,
        length: correctionRange.length
      )
    }
    return nil
  }
}
