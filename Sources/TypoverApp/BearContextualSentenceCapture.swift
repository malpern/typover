import Foundation
import TypoverAccessibility
import TypoverCore

enum BearContextualSentenceCapture {
  static func capture(
    from snapshot: BearTypingContextSnapshot,
    expectedTerminator: String
  ) -> CompletedSentence? {
    guard
      CompletedSentenceDetector.isSentenceTerminator(expectedTerminator),
      snapshot.caretLocation >= snapshot.leadingRange.location,
      snapshot.caretLocation
        <= snapshot.leadingRange.location + snapshot.leadingRange.length
    else {
      return nil
    }

    let localCaret = snapshot.caretLocation - snapshot.leadingRange.location
    let leadingText = snapshot.leadingText as NSString
    guard
      localCaret > 0,
      localCaret <= leadingText.length,
      leadingText.substring(
        with: leadingText.rangeOfComposedCharacterSequence(
          at: localCaret - 1
        )
      ) == expectedTerminator
    else {
      return nil
    }

    return CompletedSentenceDetector.immediatelyBeforeCaret(
      inBoundedText: snapshot.leadingText,
      documentRange: NSRange(
        location: snapshot.leadingRange.location,
        length: snapshot.leadingRange.length
      ),
      caretDocumentOffset: snapshot.caretLocation
    )
  }

  static func isCurrent(
    _ capturedSentence: CompletedSentence,
    in snapshot: BearTypingContextSnapshot
  ) -> Bool {
    let availableStart = snapshot.leadingRange.location
    let availableEnd = availableStart + snapshot.leadingRange.length
    let sentenceEnd =
      capturedSentence.range.location
      + capturedSentence.range.length
    guard
      capturedSentence.range.location >= availableStart,
      sentenceEnd <= availableEnd
    else {
      return false
    }

    let localRange = NSRange(
      location: capturedSentence.range.location - availableStart,
      length: capturedSentence.range.length
    )
    let leadingText = snapshot.leadingText as NSString
    guard NSMaxRange(localRange) <= leadingText.length else {
      return false
    }
    return leadingText.substring(with: localRange) == capturedSentence.text
  }
}
