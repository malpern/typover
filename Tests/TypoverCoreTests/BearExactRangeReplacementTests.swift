import AppKit
import ApplicationServices
import Foundation
import Testing
import TypoverBearAdapter

@testable import TypoverAccessibility

@Suite("Bear exact-range replacement")
struct BearExactRangeReplacementTests {
  @Test("Only the requested range changes and the caret is restored")
  func appliesExactRange() {
    let editor = FakeBearEditableTextClient(
      text: "alpha teh omega",
      selection: AccessibilityTextRange(location: 10, length: 0)
    )

    let report = BearExactRangeTransaction().apply(
      request(
        location: 6,
        original: "teh",
        replacement: "the"
      ),
      to: editor
    )

    #expect(report.status == .applied)
    #expect(report.isVerifiedApplication)
    #expect(editor.text as String == "alpha the omega")
    #expect(
      editor.selection
        == AccessibilityTextRange(location: 10, length: 0)
    )
    #expect(editor.replacementWriteCount == 1)
  }

  @Test("A longer replacement shifts the caret by only its length delta")
  func adjustsCaretForLengthDelta() {
    let editor = FakeBearEditableTextClient(
      text: "alpha adress omega",
      selection: AccessibilityTextRange(location: 13, length: 0)
    )

    let report = BearExactRangeTransaction().apply(
      request(
        location: 6,
        original: "adress",
        replacement: "address"
      ),
      to: editor
    )

    #expect(report.status == .applied)
    #expect(editor.text as String == "alpha address omega")
    #expect(
      report.selectionAfter
        == AccessibilityTextRange(location: 14, length: 0)
    )
  }

  @Test("A stale target makes no edit")
  func rejectsStaleTarget() {
    let editor = FakeBearEditableTextClient(
      text: "alpha ten omega",
      selection: AccessibilityTextRange(location: 10, length: 0)
    )

    let report = BearExactRangeTransaction().apply(
      request(
        location: 6,
        original: "teh",
        replacement: "the"
      ),
      to: editor
    )

    #expect(report.status == .preconditionFailed)
    #expect(!report.writeOccurred)
    #expect(editor.text as String == "alpha ten omega")
    #expect(editor.replacementWriteCount == 0)
  }

  @Test("Repeating an applied transaction is idempotent")
  func alreadyAppliedDoesNotWrite() {
    let editor = FakeBearEditableTextClient(
      text: "alpha the omega",
      selection: AccessibilityTextRange(location: 10, length: 0)
    )

    let report = BearExactRangeTransaction().apply(
      request(
        location: 6,
        original: "teh",
        replacement: "the"
      ),
      to: editor
    )

    #expect(report.status == .alreadyApplied)
    #expect(!report.writeOccurred)
    #expect(editor.replacementWriteCount == 0)
  }

  @Test("A shorter replacement is not mistaken for already applied")
  func shorterReplacementStillApplies() {
    let editor = FakeBearEditableTextClient(
      text: "alpha cats omega",
      selection: AccessibilityTextRange(location: 11, length: 0)
    )

    let report = BearExactRangeTransaction().apply(
      request(
        location: 6,
        original: "cats",
        replacement: "cat"
      ),
      to: editor
    )

    #expect(report.status == .applied)
    #expect(editor.text as String == "alpha cat omega")
    #expect(
      report.selectionAfter
        == AccessibilityTextRange(location: 10, length: 0)
    )
  }

  @Test("Unexpected surrounding changes fail post-write verification")
  func detectsUnexpectedSurroundingChange() {
    let editor = FakeBearEditableTextClient(
      text: "alpha teh omega",
      selection: AccessibilityTextRange(location: 10, length: 0),
      appendedTextAfterReplacement: "!"
    )

    let report = BearExactRangeTransaction().apply(
      request(
        location: 6,
        original: "teh",
        replacement: "the"
      ),
      to: editor
    )

    #expect(report.status == .verificationFailed)
    #expect(report.writeOccurred)
    #expect(!report.surroundingContextVerified)
  }

  @Test("A selection-write failure prevents replacement")
  func selectionFailureDoesNotWrite() {
    let editor = FakeBearEditableTextClient(
      text: "alpha teh omega",
      selection: AccessibilityTextRange(location: 10, length: 0),
      selectionErrors: [.cannotComplete]
    )

    let report = BearExactRangeTransaction().apply(
      request(
        location: 6,
        original: "teh",
        replacement: "the"
      ),
      to: editor
    )

    #expect(report.status == .selectionWriteFailed)
    #expect(!report.writeOccurred)
    #expect(editor.text as String == "alpha teh omega")
    #expect(editor.replacementWriteCount == 0)
  }

  @Test("A replacement-write failure restores the original caret")
  func replacementFailureRestoresCaret() {
    let originalSelection = AccessibilityTextRange(location: 10, length: 0)
    let editor = FakeBearEditableTextClient(
      text: "alpha teh omega",
      selection: originalSelection,
      replacementError: .cannotComplete
    )

    let report = BearExactRangeTransaction().apply(
      request(
        location: 6,
        original: "teh",
        replacement: "the"
      ),
      to: editor
    )

    #expect(report.status == .replacementWriteFailed)
    #expect(!report.writeOccurred)
    #expect(editor.text as String == "alpha teh omega")
    #expect(editor.selection == originalSelection)
  }

  @Test("A caret-restore failure is reported after the write")
  func caretRestoreFailureIsNotRecordedAsSuccess() {
    let editor = FakeBearEditableTextClient(
      text: "alpha teh omega",
      selection: AccessibilityTextRange(location: 10, length: 0),
      selectionErrors: [.success, .cannotComplete]
    )

    let report = BearExactRangeTransaction().apply(
      request(
        location: 6,
        original: "teh",
        replacement: "the"
      ),
      to: editor
    )

    #expect(report.status == .selectionRestoreFailed)
    #expect(report.writeOccurred)
    #expect(!report.caretRestored)
    #expect(editor.text as String == "alpha the omega")
  }

  @Test("An out-of-bounds target makes no edit")
  func rejectsOutOfBoundsTarget() {
    let editor = FakeBearEditableTextClient(
      text: "alpha teh omega",
      selection: AccessibilityTextRange(location: 10, length: 0)
    )

    let report = BearExactRangeTransaction().apply(
      request(
        location: 100,
        original: "teh",
        replacement: "the"
      ),
      to: editor
    )

    #expect(report.status == .targetOutOfBounds)
    #expect(!report.writeOccurred)
    #expect(editor.replacementWriteCount == 0)
  }

  @Test("Replacement reports contain no source or replacement text")
  func reportEncodingIsContentFree() throws {
    let report = BearExactRangeReplacementReport(
      status: .applied,
      writeOccurred: true,
      targetRange: AccessibilityTextRange(location: 6, length: 3),
      replacementRange: AccessibilityTextRange(location: 6, length: 3),
      selectionBefore: AccessibilityTextRange(location: 10, length: 0),
      selectionAfter: AccessibilityTextRange(location: 10, length: 0),
      surroundingContextVerified: true,
      caretRestored: true
    )

    let data = try JSONEncoder().encode(report)
    let json = try #require(String(data: data, encoding: .utf8))

    #expect(!json.contains("teh"))
    #expect(!json.contains("the"))
    #expect(!json.contains("original"))
    #expect(!json.contains("replacementText"))
  }

  @Test("A correction record is created only after verified application")
  func adapterGatesCorrectionRecord() {
    let verifiedReport = BearExactRangeReplacementReport(
      status: .applied,
      writeOccurred: true,
      targetRange: AccessibilityTextRange(location: 6, length: 3),
      replacementRange: AccessibilityTextRange(location: 6, length: 3),
      selectionBefore: AccessibilityTextRange(location: 10, length: 0),
      selectionAfter: AccessibilityTextRange(location: 10, length: 0),
      surroundingContextVerified: true,
      caretRestored: true
    )
    let failedReport = BearExactRangeReplacementReport(
      status: .verificationFailed,
      writeOccurred: true,
      targetRange: AccessibilityTextRange(location: 6, length: 3)
    )

    let verified = BearCorrectionAdapter(
      replacer: StubBearReplacer(report: verifiedReport)
    ).apply(
      original: "teh",
      replacement: "the",
      at: AccessibilityTextRange(location: 6, length: 3)
    )
    let failed = BearCorrectionAdapter(
      replacer: StubBearReplacer(report: failedReport)
    ).apply(
      original: "teh",
      replacement: "the",
      at: AccessibilityTextRange(location: 6, length: 3)
    )

    #expect(verified.correctionRecord?.correction.original == "teh")
    #expect(verified.correctionRecord?.correction.replacement == "the")
    #expect(failed.correction.original == "teh")
    #expect(failed.correction.replacement == "the")
    #expect(failed.correctionRecord == nil)
  }

  @Test(
    "Live Bear transaction replaces the completed synthetic typo",
    .enabled(
      if: ProcessInfo.processInfo.environment[
        "TYPOVER_RUN_LIVE_BEAR_REPLACEMENT"
      ] == "1"
    )
  )
  func liveBearExactRangeReplacement() throws {
    let probe = BearAccessibilityProbe().run()
    let selection = try #require(probe.selectedRange)
    #expect(probe.status == .ready)
    #expect(selection.length == 0)
    #expect(selection.location >= 4)

    let targetRange = AccessibilityTextRange(
      location: selection.location - 4,
      length: 3
    )
    let adapter = BearCorrectionAdapter()
    let application = adapter.apply(
      original: "teh",
      replacement: "the",
      at: targetRange
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let encoded = try encoder.encode(application.report)
    let json = try #require(String(data: encoded, encoding: .utf8))
    print(json)

    #expect(application.report.isVerifiedApplication)
    #expect(application.correctionRecord != nil)

    let repeated = adapter.apply(
      original: "teh",
      replacement: "the",
      at: targetRange
    )
    #expect(repeated.report.status == .alreadyApplied)
    #expect(!repeated.report.writeOccurred)
    #expect(repeated.correctionRecord == nil)
  }

  @Test(
    "Live Bear native Undo reverses the Accessibility transaction",
    .enabled(
      if: ProcessInfo.processInfo.environment[
        "TYPOVER_RUN_LIVE_BEAR_UNDO"
      ] == "1"
    )
  )
  func liveBearUndo() throws {
    #expect(try performBearUndoMenuAction())
  }

  private func request(
    location: Int,
    original: String,
    replacement: String
  ) -> BearExactRangeReplacementRequest {
    BearExactRangeReplacementRequest(
      targetRange: AccessibilityTextRange(
        location: location,
        length: original.utf16.count
      ),
      expectedOriginal: original,
      replacement: replacement
    )
  }
}

private func performBearUndoMenuAction() throws -> Bool {
  let application = try #require(
    NSRunningApplication.runningApplications(
      withBundleIdentifier: BearAccessibilityProbe.bearBundleIdentifier
    ).first
  )
  application.activate(options: [.activateAllWindows])
  let applicationElement = AXUIElementCreateApplication(
    application.processIdentifier
  )
  let menuBar = try #require(
    testElementAttribute(
      applicationElement,
      kAXMenuBarAttribute as CFString
    )
  )
  let editMenu = try #require(
    testDescendants(of: menuBar).first { element in
      testStringAttribute(element, kAXRoleAttribute as CFString)
        == (kAXMenuBarItemRole as String)
        && testStringAttribute(element, kAXTitleAttribute as CFString)
          == "Edit"
    }
  )
  guard AXUIElementPerformAction(
    editMenu,
    kAXPressAction as CFString
  ) == .success else {
    return false
  }

  CFRunLoopRunInMode(.defaultMode, 0.1, false)
  let undoItem = try #require(
    testDescendants(of: editMenu).first { element in
      testStringAttribute(element, kAXRoleAttribute as CFString)
        == (kAXMenuItemRole as String)
        && testStringAttribute(element, kAXTitleAttribute as CFString)?
          .hasPrefix("Undo") == true
    }
  )
  return AXUIElementPerformAction(
    undoItem,
    kAXPressAction as CFString
  ) == .success
}

private func testDescendants(of root: AXUIElement) -> [AXUIElement] {
  var result: [AXUIElement] = []
  var queue = [root]
  var visited = Set<ObjectIdentifier>()
  while !queue.isEmpty, visited.count < 200 {
    let element = queue.removeFirst()
    guard visited.insert(ObjectIdentifier(element)).inserted else {
      continue
    }
    result.append(element)
    queue.append(
      contentsOf: testElementArrayAttribute(
        element,
        kAXChildrenAttribute as CFString
      )
    )
  }
  return result
}

private func testElementAttribute(
  _ element: AXUIElement,
  _ name: CFString
) -> AXUIElement? {
  var value: CFTypeRef?
  guard
    AXUIElementCopyAttributeValue(element, name, &value) == .success,
    let value,
    CFGetTypeID(value) == AXUIElementGetTypeID()
  else {
    return nil
  }
  return unsafeDowncast(value, to: AXUIElement.self)
}

private func testElementArrayAttribute(
  _ element: AXUIElement,
  _ name: CFString
) -> [AXUIElement] {
  var value: CFTypeRef?
  guard
    AXUIElementCopyAttributeValue(element, name, &value) == .success,
    let value,
    CFGetTypeID(value) == CFArrayGetTypeID()
  else {
    return []
  }
  let values = unsafeDowncast(value, to: CFArray.self)
  return (0..<CFArrayGetCount(values)).compactMap { index in
    guard let pointer = CFArrayGetValueAtIndex(values, index) else {
      return nil
    }
    let child = unsafeBitCast(pointer, to: CFTypeRef.self)
    guard CFGetTypeID(child) == AXUIElementGetTypeID() else {
      return nil
    }
    return unsafeDowncast(child, to: AXUIElement.self)
  }
}

private func testStringAttribute(
  _ element: AXUIElement,
  _ name: CFString
) -> String? {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, name, &value) == .success else {
    return nil
  }
  return value as? String
}

private final class FakeBearEditableTextClient: BearEditableTextClient {
  let text: NSMutableString
  private(set) var selection: AccessibilityTextRange
  private var selectionErrors: [AXError]
  private let replacementError: AXError
  private let appendedTextAfterReplacement: String?
  private(set) var replacementWriteCount = 0

  init(
    text: String,
    selection: AccessibilityTextRange,
    selectionErrors: [AXError] = [],
    replacementError: AXError = .success,
    appendedTextAfterReplacement: String? = nil
  ) {
    self.text = NSMutableString(string: text)
    self.selection = selection
    self.selectionErrors = selectionErrors
    self.replacementError = replacementError
    self.appendedTextAfterReplacement = appendedTextAfterReplacement
  }

  func selectedRange() -> AccessibilityTextRange? {
    selection
  }

  func characterCount() -> Int? {
    text.length
  }

  func string(in range: AccessibilityTextRange) -> String? {
    let nsRange = NSRange(location: range.location, length: range.length)
    guard
      nsRange.location >= 0,
      nsRange.length >= 0,
      NSMaxRange(nsRange) <= text.length
    else {
      return nil
    }
    return text.substring(with: nsRange)
  }

  func setSelectedRange(_ range: AccessibilityTextRange) -> AXError {
    if !selectionErrors.isEmpty {
      let error = selectionErrors.removeFirst()
      guard error == .success else {
        return error
      }
    }
    selection = range
    return .success
  }

  func replaceSelectedText(with replacement: String) -> AXError {
    guard replacementError == .success else {
      return replacementError
    }
    replacementWriteCount += 1
    text.replaceCharacters(
      in: NSRange(location: selection.location, length: selection.length),
      with: replacement
    )
    selection = AccessibilityTextRange(
      location: selection.location + replacement.utf16.count,
      length: 0
    )
    if let appendedTextAfterReplacement {
      text.append(appendedTextAfterReplacement)
    }
    return .success
  }
}

private struct StubBearReplacer: BearExactRangeReplacing {
  let report: BearExactRangeReplacementReport

  func replace(
    _: BearExactRangeReplacementRequest
  ) -> BearExactRangeReplacementReport {
    report
  }
}
