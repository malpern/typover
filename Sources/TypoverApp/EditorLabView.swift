import AppKit
import SwiftUI
import TypoverCore

struct EditorLabView: NSViewRepresentable {
  func makeNSView(context: Context) -> NSScrollView {
    let textView = TypoverTextView(usingTextLayoutManager: true)
    textView.allowsUndo = true
    textView.autoresizingMask = [.width]
    textView.backgroundColor = NSColor.clear
    textView.drawsBackground = false
    textView.font = NSFont.preferredFont(forTextStyle: .body)
    textView.insertionPointColor = NSColor.labelColor
    textView.isHorizontallyResizable = false
    textView.isRichText = false
    textView.isVerticallyResizable = true
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.isContinuousSpellCheckingEnabled = false
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.minSize = NSSize(width: 0, height: 240)
    textView.textColor = NSColor.labelColor
    textView.textContainerInset = NSSize(width: 18, height: 18)
    textView.undoManager?.removeAllActions()
    textView.setAccessibilityIdentifier("typover.editor")

    textView.textContainer?.containerSize = NSSize(
      width: 0,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.textContainer?.widthTracksTextView = true

    textView.string = String(
      localized: """
        This is Typover’s controlled AppKit editor.

        Type “teh” followed by a space:

        """,
      bundle: #bundle,
      comment: "Starter text in the editor lab explaining how to trigger the demo correction."
    )
    textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

    let scrollView = NSScrollView()
    scrollView.borderType = .noBorder
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.documentView = textView
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {}
}

extension NSAttributedString.Key {
  fileprivate static let typoverCorrectionID = NSAttributedString.Key(
    "com.malpern.typover.correction-id"
  )
}

@MainActor
private final class TypoverTextView: NSTextView {
  private let correctionEngine: any CorrectionEngine = DemoCorrectionEngine()
  private let automaticConfidenceThreshold = 0.98

  private var correctionsByID: [Correction.ID: Correction] = [:]
  private var isPerformingCorrection = false
  private var ledger = CorrectionLedger()
  private var viewportRange: NSTextRange?

  override func didChangeText() {
    super.didChangeText()

    guard !isPerformingCorrection else {
      return
    }

    reconcileAnnotations()
    applyCorrectionBeforeTypedBoundary()
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    for (id, _) in correctionsByID {
      guard ledger.record(for: id)?.disposition == .applied else {
        continue
      }

      for range in annotatedRanges(for: id) {
        for rect in textSegmentRects(for: range)
        where dirtyRect.intersects(rect.insetBy(dx: -2, dy: -3)) {
          drawSquiggle(
            from: NSPoint(x: rect.minX, y: rect.maxY + 1),
            toX: rect.maxX
          )
        }
      }
    }
  }

  override func textViewportLayoutControllerDidLayout(
    _ textViewportLayoutController: NSTextViewportLayoutController
  ) {
    super.textViewportLayoutControllerDidLayout(textViewportLayoutController)
    viewportRange = textViewportLayoutController.viewportRange
    needsDisplay = true
  }

  override func mouseDown(with event: NSEvent) {
    guard let correctionID = correctionID(at: event) else {
      super.mouseDown(with: event)
      return
    }

    showCorrectionMenu(for: correctionID, event: event)
  }

  private func applyCorrectionBeforeTypedBoundary() {
    let caret = selectedRange().location
    guard
      selectedRange().length == 0,
      caret > 0,
      let textStorage,
      let boundary = textStorage.string.utf16CodeUnit(at: caret - 1),
      CharacterSet.whitespacesAndNewlines.contains(boundary)
    else {
      return
    }

    let wordEnd = caret - 1
    let prefix = (textStorage.string as NSString).substring(to: wordEnd)
    let separatorRange = (prefix as NSString).rangeOfCharacter(
      from: CharacterSet.letters.inverted,
      options: .backwards
    )
    let wordStart =
      separatorRange.location == NSNotFound
      ? 0
      : NSMaxRange(separatorRange)
    let wordRange = NSRange(
      location: wordStart,
      length: wordEnd - wordStart
    )

    guard wordRange.length > 0 else {
      return
    }

    let word = (textStorage.string as NSString).substring(with: wordRange)
    guard
      let correction = correctionEngine.correction(for: word),
      correction.changesText,
      correction.confidence >= automaticConfidenceThreshold
    else {
      return
    }

    correctionsByID[correction.id] = correction
    ledger.record(correction)
    replaceCorrectionText(
      correction: correction,
      range: wordRange,
      expectedText: correction.original,
      replacementText: correction.replacement,
      annotateReplacement: true,
      dispositionAfter: .applied,
      undoAnnotatesReplacement: false,
      undoDisposition: .restored,
      actionName: String(
        localized: "Correct Spelling",
        bundle: #bundle,
        comment: "Undo menu action name for an automatic Typover correction."
      )
    )
  }

  private func replaceCorrectionText(
    correction: Correction,
    range: NSRange,
    expectedText: String,
    replacementText: String,
    annotateReplacement: Bool,
    dispositionAfter: CorrectionDisposition,
    undoAnnotatesReplacement: Bool,
    undoDisposition: CorrectionDisposition,
    actionName: String
  ) {
    guard
      let textStorage,
      NSMaxRange(range) <= textStorage.length,
      (textStorage.string as NSString).substring(with: range) == expectedText,
      shouldChangeText(in: range, replacementString: replacementText)
    else {
      ledger.transition(correction.id, to: .invalidated)
      return
    }

    let selectionBeforeChange = selectedRange()
    let replacementRange = NSRange(
      location: range.location,
      length: replacementText.utf16.count
    )

    isPerformingCorrection = true
    textStorage.beginEditing()
    textStorage.replaceCharacters(in: range, with: replacementText)
    if annotateReplacement {
      textStorage.addAttribute(
        .typoverCorrectionID,
        value: correction.id.uuidString,
        range: replacementRange
      )
    } else {
      textStorage.removeAttribute(
        .typoverCorrectionID,
        range: replacementRange
      )
    }
    textStorage.endEditing()
    setSelectedRange(
      TextSelectionAdjustment.afterReplacing(
        range,
        withLength: replacementRange.length,
        selection: selectionBeforeChange
      )
    )
    didChangeText()
    isPerformingCorrection = false

    ledger.transition(correction.id, to: dispositionAfter)

    undoManager?.registerUndo(withTarget: self) { target in
      target.replaceCorrectionText(
        correction: correction,
        range: replacementRange,
        expectedText: replacementText,
        replacementText: expectedText,
        annotateReplacement: undoAnnotatesReplacement,
        dispositionAfter: undoDisposition,
        undoAnnotatesReplacement: annotateReplacement,
        undoDisposition: dispositionAfter,
        actionName: actionName
      )
    }
    undoManager?.setActionName(actionName)
  }

  private func reconcileAnnotations() {
    guard let textStorage else {
      return
    }

    for (id, correction) in correctionsByID {
      guard ledger.record(for: id)?.disposition == .applied else {
        continue
      }

      let ranges = annotatedRanges(for: id)
      let annotationIsValid =
        ranges.count == 1
        && (textStorage.string as NSString).substring(with: ranges[0])
          == correction.replacement

      guard !annotationIsValid else {
        continue
      }

      for range in ranges {
        textStorage.removeAttribute(.typoverCorrectionID, range: range)
      }
      ledger.transition(id, to: .invalidated)
    }
  }

  private func annotatedRanges(for id: Correction.ID) -> [NSRange] {
    guard let textStorage else {
      return []
    }

    var ranges: [NSRange] = []
    textStorage.enumerateAttribute(
      .typoverCorrectionID,
      in: NSRange(location: 0, length: textStorage.length)
    ) { value, range, _ in
      if value as? String == id.uuidString {
        ranges.append(range)
      }
    }
    return ranges
  }

  private func correctionID(at event: NSEvent) -> Correction.ID? {
    let viewPoint = convert(event.locationInWindow, from: nil)

    for (id, _) in correctionsByID {
      guard ledger.record(for: id)?.disposition == .applied else {
        continue
      }

      let containsPoint = annotatedRanges(for: id).contains { range in
        textSegmentRects(for: range).contains { rect in
          rect.insetBy(dx: -2, dy: -3).contains(viewPoint)
        }
      }

      if containsPoint {
        return id
      }
    }

    return nil
  }

  private func showCorrectionMenu(for id: Correction.ID, event: NSEvent) {
    guard
      let correction = correctionsByID[id],
      ledger.record(for: id)?.disposition == .applied
    else {
      return
    }

    let menu = NSMenu()
    let changeBackItem = NSMenuItem(
      title: String(
        localized: "Change Back to “\(correction.original)”",
        bundle: #bundle,
        comment:
          "Menu action that restores the original word. The variable is the original typed word."
      ),
      action: #selector(changeBack(_:)),
      keyEquivalent: ""
    )
    changeBackItem.representedObject = id.uuidString
    changeBackItem.target = self
    menu.addItem(changeBackItem)

    let keepItem = NSMenuItem(
      title: String(
        localized: "Keep Correction",
        bundle: #bundle,
        comment: "Menu action that accepts an automatic correction and removes its annotation."
      ),
      action: #selector(keepCorrection(_:)),
      keyEquivalent: ""
    )
    keepItem.representedObject = id.uuidString
    keepItem.target = self
    menu.addItem(keepItem)

    menu.addItem(.separator())
    let alternativesItem = NSMenuItem(
      title: String(
        localized: "Alternative Corrections Coming Later",
        bundle: #bundle,
        comment: "Disabled placeholder describing a future correction-menu capability."
      ),
      action: nil,
      keyEquivalent: ""
    )
    alternativesItem.isEnabled = false
    menu.addItem(alternativesItem)

    menu.popUp(
      positioning: changeBackItem,
      at: convert(event.locationInWindow, from: nil),
      in: self
    )
  }

  @objc
  private func changeBack(_ sender: NSMenuItem) {
    guard
      let id = correctionID(from: sender),
      let correction = correctionsByID[id],
      let range = annotatedRanges(for: id).first
    else {
      return
    }

    replaceCorrectionText(
      correction: correction,
      range: range,
      expectedText: correction.replacement,
      replacementText: correction.original,
      annotateReplacement: false,
      dispositionAfter: .restored,
      undoAnnotatesReplacement: true,
      undoDisposition: .applied,
      actionName: String(
        localized: "Change Back",
        bundle: #bundle,
        comment: "Undo menu action name after restoring an automatically corrected word."
      )
    )
  }

  @objc
  private func keepCorrection(_ sender: NSMenuItem) {
    guard
      let id = correctionID(from: sender),
      let textStorage
    else {
      return
    }

    for range in annotatedRanges(for: id) {
      textStorage.removeAttribute(.typoverCorrectionID, range: range)
    }
    ledger.transition(id, to: .kept)
  }

  private func correctionID(from menuItem: NSMenuItem) -> Correction.ID? {
    guard let rawID = menuItem.representedObject as? String else {
      return nil
    }
    return Correction.ID(uuidString: rawID)
  }

  private func textSegmentRects(for characterRange: NSRange) -> [NSRect] {
    guard
      let textLayoutManager,
      let textContentManager = textLayoutManager.textContentManager,
      let startLocation = textContentManager.location(
        textContentManager.documentRange.location,
        offsetBy: characterRange.location
      ),
      let endLocation = textContentManager.location(
        startLocation,
        offsetBy: characterRange.length
      ),
      let textRange = NSTextRange(
        location: startLocation,
        end: endLocation
      )
    else {
      return []
    }

    if let viewportRange, !viewportRange.intersects(textRange) {
      return []
    }

    textLayoutManager.ensureLayout(for: textRange)

    let containerOrigin = textContainerOrigin
    var rects: [NSRect] = []
    textLayoutManager.enumerateTextSegments(
      in: textRange,
      type: .standard,
      options: [.rangeNotRequired]
    ) { _, frame, _, _ in
      rects.append(
        frame.offsetBy(
          dx: containerOrigin.x,
          dy: containerOrigin.y
        )
      )
      return true
    }
    return rects
  }

  private func drawSquiggle(
    from start: NSPoint,
    toX endX: CGFloat
  ) {
    guard endX > start.x else {
      return
    }

    let path = NSBezierPath()
    path.lineWidth = 1
    path.move(to: start)

    let halfWavelength: CGFloat = 2
    let amplitude: CGFloat = 1.25
    var x = start.x
    var rises = true

    while x < endX {
      let nextX = min(x + halfWavelength, endX)
      let controlPoint = NSPoint(
        x: (x + nextX) / 2,
        y: start.y + (rises ? -amplitude : amplitude)
      )
      path.curve(
        to: NSPoint(x: nextX, y: start.y),
        controlPoint1: controlPoint,
        controlPoint2: controlPoint
      )
      rises.toggle()
      x = nextX
    }

    NSColor.tertiaryLabelColor.withAlphaComponent(0.72).setStroke()
    path.stroke()
  }
}

extension String {
  fileprivate func utf16CodeUnit(at offset: Int) -> Unicode.Scalar? {
    guard
      offset >= 0,
      offset < utf16.count
    else {
      return nil
    }

    let index = utf16.index(utf16.startIndex, offsetBy: offset)
    return Unicode.Scalar(utf16[index])
  }
}
