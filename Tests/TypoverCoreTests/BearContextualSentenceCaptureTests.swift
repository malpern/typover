import Foundation
import Testing
import TypoverAccessibility
import TypoverCore

@testable import TypoverApp

struct BearContextualSentenceCaptureTests {
  @Test("Bear captures a completed sentence in document coordinates")
  func capturesAbsoluteSentenceRange() throws {
    let text = "Earlier sentence. Their going home."
    let start = 80
    let sentence = try #require(
      BearContextualSentenceCapture.capture(
        from: snapshot(text: text, start: start),
        expectedTerminator: "."
      )
    )

    #expect(sentence.text == "Their going home.")
    #expect(
      sentence.range
        == NSRange(
          location: start + (text as NSString).range(of: sentence.text).location,
          length: sentence.text.utf16.count
        )
    )
  }

  @Test("Bear requires the observed terminator to match the bounded text")
  func requiresExactTerminator() {
    let snapshot = snapshot(text: "Their going home.", start: 0)

    #expect(
      BearContextualSentenceCapture.capture(
        from: snapshot,
        expectedTerminator: "?"
      ) == nil
    )
    #expect(
      BearContextualSentenceCapture.capture(
        from: snapshot,
        expectedTerminator: " "
      ) == nil
    )
  }

  @Test("Bear refuses a sentence truncated by the bounded read")
  func refusesTruncatedSentence() {
    #expect(
      BearContextualSentenceCapture.capture(
        from: snapshot(text: "middle of a sentence.", start: 120),
        expectedTerminator: "."
      ) == nil
    )
  }

  @Test("Bear accepts document-start context without an earlier terminator")
  func acceptsDocumentStart() {
    let sentence = BearContextualSentenceCapture.capture(
      from: snapshot(text: "Their going home.", start: 0),
      expectedTerminator: "."
    )

    #expect(sentence?.range == NSRange(location: 0, length: 17))
  }

  @Test("Bear accepts continued typing only while the captured sentence is exact")
  func revalidatesCapturedSentenceAfterContinuedTyping() throws {
    let original = "Their going home."
    let captured = try #require(
      BearContextualSentenceCapture.capture(
        from: snapshot(text: original, start: 0),
        expectedTerminator: "."
      )
    )

    #expect(
      BearContextualSentenceCapture.isCurrent(
        captured,
        in: snapshot(text: original + " More typing", start: 0)
      )
    )
    #expect(
      !BearContextualSentenceCapture.isCurrent(
        captured,
        in: snapshot(text: "They're going home. More typing", start: 0)
      )
    )
  }

  @Test("Bear refuses a captured sentence that leaves the bounded window")
  func refusesSentenceOutsideCurrentWindow() {
    let captured = CompletedSentence(
      range: NSRange(location: 20, length: 17),
      text: "Their going home."
    )

    #expect(
      !BearContextualSentenceCapture.isCurrent(
        captured,
        in: snapshot(text: "Later bounded text.", start: 100)
      )
    )
  }

  private func snapshot(
    text: String,
    start: Int
  ) -> BearTypingContextSnapshot {
    BearTypingContextSnapshot(
      leadingRange: AccessibilityTextRange(
        location: start,
        length: text.utf16.count
      ),
      leadingText: text,
      trailingText: "",
      caretLocation: start + text.utf16.count,
      documentLength: start + text.utf16.count
    )
  }
}
