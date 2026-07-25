import AppKit
import SwiftUI
import TypoverAppleIntelligence
import TypoverAppleSpell
import TypoverCore

struct EditorLabView: NSViewRepresentable {
  let behaviorSettings: CorrectionBehaviorSettings
  let learningStore: CorrectionLearningStore

  func makeNSView(context: Context) -> NSScrollView {
    let textView = TypoverTextView(usingTextLayoutManager: true)
    textView.useBehaviorSettings(behaviorSettings)
    textView.useLearningStore(learningStore)
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
final class TypoverTextView: NSTextView {
  private enum LearningEffect {
    case none
    case removePreference
    case suppress
    case prefer(String, outcome: CorrectionOutcome?)
  }

  private struct PendingManualCorrection {
    let correctionID: Correction.ID
    var range: NSRange
    var replacement: String
  }

  private struct PendingUserEdit {
    let replacement: String
  }

  private final class AlternativeSelection: NSObject {
    let correctionID: Correction.ID
    let replacement: String

    init(correctionID: Correction.ID, replacement: String) {
      self.correctionID = correctionID
      self.replacement = replacement
    }
  }

  private var correctionEngine: any CorrectionEngine = AppleSpellCheckerEngine()
  private var contextualCorrectionEngine: any ContextualCorrectionEngine =
    AppleContextualCorrectionEngine()
  private var behaviorSettings = CorrectionBehaviorSettings()
  private var learningStore = CorrectionLearningStore()

  private var contextualCorrectionTask: Task<Void, Never>?
  private var correctionsByID: [Correction.ID: Correction] = [:]
  private var isPerformingCorrection = false
  private var isPerformingPaste = false
  private var ledger = CorrectionLedger()
  private var pendingManualCorrections: [Correction.ID: PendingManualCorrection] =
    [:]
  private var proposalsByID: [Correction.ID: CorrectionProposal] = [:]
  private var pendingUserEdit: PendingUserEdit?
  private var testingUndoManager: UndoManager?
  private var viewportRange: NSTextRange?
  private(set) var correctionDiagnostics: [CorrectionDiagnostic] = []
  private(set) var correctionTransactionSamples: [CorrectionTransactionSample] = []

  struct CorrectionSnapshot: Equatable {
    let correction: Correction
    let disposition: CorrectionDisposition
    let annotatedRanges: [NSRange]
  }

  var correctionSnapshots: [CorrectionSnapshot] {
    correctionsByID.values.compactMap { correction in
      guard let record = ledger.record(for: correction.id) else {
        return nil
      }
      return CorrectionSnapshot(
        correction: correction,
        disposition: record.disposition,
        annotatedRanges: annotatedRanges(for: correction.id)
      )
    }
    .sorted { $0.correction.createdAt < $1.correction.createdAt }
  }

  func configureForTesting(
    correctionEngine: any CorrectionEngine,
    contextualCorrectionEngine: any ContextualCorrectionEngine =
      DisabledContextualCorrectionEngine(),
    behaviorSettings: CorrectionBehaviorSettings? = nil,
    learningStore: CorrectionLearningStore,
    undoManager: UndoManager
  ) {
    self.correctionEngine = correctionEngine
    self.contextualCorrectionEngine = contextualCorrectionEngine
    if let behaviorSettings {
      self.behaviorSettings = behaviorSettings
    }
    self.learningStore = learningStore
    testingUndoManager = undoManager
  }

  func useBehaviorSettings(
    _ behaviorSettings: CorrectionBehaviorSettings
  ) {
    self.behaviorSettings = behaviorSettings
  }

  func useLearningStore(_ learningStore: CorrectionLearningStore) {
    self.learningStore = learningStore
  }

  override var undoManager: UndoManager? {
    testingUndoManager ?? super.undoManager
  }

  override func shouldChangeText(
    in affectedCharRange: NSRange,
    replacementString: String?
  ) -> Bool {
    let shouldChange = super.shouldChangeText(
      in: affectedCharRange,
      replacementString: replacementString
    )
    guard shouldChange, !isPerformingCorrection else {
      return shouldChange
    }

    pendingUserEdit = PendingUserEdit(
      replacement: replacementString ?? ""
    )
    updatePendingManualCorrections(
      for: affectedCharRange,
      replacementString: replacementString ?? ""
    )
    captureManualReplacement(
      in: affectedCharRange,
      replacementString: replacementString ?? ""
    )
    return true
  }

  override func didChangeText() {
    super.didChangeText()

    guard !isPerformingCorrection else {
      return
    }

    let completedUserEdit = pendingUserEdit
    pendingUserEdit = nil
    reconcileAnnotations()
    guard !isPerformingPaste else {
      recordDiagnostic(.pasteSkipped)
      return
    }
    applyCorrectionBeforeTypedBoundary()
    if let completedUserEdit {
      scheduleContextualCorrection(after: completedUserEdit)
    }
  }

  override func paste(_ sender: Any?) {
    isPerformingPaste = true
    defer { isPerformingPaste = false }
    super.paste(sender)
  }

  func insertPastedTextForTesting(_ text: String) {
    performPaste {
      insertText(text, replacementRange: selectedRange())
    }
  }

  func applyPendingCorrectionForTesting() {
    applyCorrectionBeforeTypedBoundary()
  }

  func waitForContextualCorrectionForTesting() async {
    await contextualCorrectionTask?.value
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
      let textStorage,
      !hasMarkedText(),
      let completedWord = CompletedWordDetector.immediatelyBeforeCaret(
        in: textStorage.string,
        caretUTF16Offset: caret
      )
    else {
      return
    }

    guard
      let baseProposal = correctionEngine.proposal(for: completedWord.text),
      let proposal = learningStore.applyingPreference(to: baseProposal),
      proposal.correction.changesText
    else {
      return
    }

    let correction = proposal.correction
    correctionsByID[correction.id] = correction
    proposalsByID[correction.id] = proposal
    ledger.record(correction)
    let appliedLearningEffect: LearningEffect =
      proposal.source == .rememberedPreference
      ? .prefer(correction.replacement, outcome: nil)
      : .removePreference
    let didApply = replaceCorrectionText(
      correctionAfter: correction,
      correctionForReverse: correction,
      range: completedWord.range,
      expectedText: correction.original,
      replacementText: correction.replacement,
      annotateReplacement: true,
      dispositionAfter: .applied,
      undoAnnotatesReplacement: false,
      undoDisposition: .restored,
      learningEffectAfter: appliedLearningEffect,
      reverseLearningEffect: .suppress,
      actionName: String(
        localized: "Correct Spelling",
        bundle: #bundle,
        comment: "Undo menu action name for an automatic Typover correction."
      )
    )
    if didApply {
      learningStore.recordApplied(proposal)
    }
  }

  private func scheduleContextualCorrection(
    after userEdit: PendingUserEdit
  ) {
    guard
      CompletedSentenceDetector.isSentenceTerminator(userEdit.replacement),
      selectedRange().length == 0,
      !hasMarkedText(),
      let textStorage,
      let sentence = CompletedSentenceDetector.immediatelyBeforeCaret(
        in: textStorage.string,
        caretUTF16Offset: selectedRange().location
      )
    else {
      return
    }

    contextualCorrectionTask?.cancel()
    let engine = contextualCorrectionEngine
    let language = NSSpellChecker.shared.userPreferredLanguages.first
    let scope = behaviorSettings.contextualScope
    let allowsSentenceRewrite =
      scope == .comprehensive
      && behaviorSettings.allowsSentenceRewrites
    contextualCorrectionTask = Task { [weak self] in
      guard
        await engine.availability(for: language) == .available,
        !Task.isCancelled
      else {
        return
      }

      do {
        let result = try await engine.proposal(
          for: ContextualCorrectionRequest(
            sentence: sentence.text,
            language: language,
            scope: scope,
            allowsSentenceRewrite: allowsSentenceRewrite
          )
        )
        guard !Task.isCancelled, let result else {
          return
        }
        self?.applyContextualResult(
          result,
          to: sentence,
          language: language
        )
      } catch is CancellationError {
        return
      } catch {
        self?.recordDiagnostic(.contextualModelFailure)
      }
    }
  }

  private func applyContextualResult(
    _ result: ContextualCorrectionResult,
    to capturedSentence: CompletedSentence,
    language: String?
  ) {
    guard let textStorage else {
      return
    }
    guard NSMaxRange(capturedSentence.range) <= textStorage.length else {
      recordDiagnostic(
        .contextualStaleSentence,
        range: capturedSentence.range
      )
      return
    }
    guard
      (textStorage.string as NSString).substring(
        with: capturedSentence.range
      ) == capturedSentence.text
    else {
      recordDiagnostic(
        .contextualStaleSentence,
        range: capturedSentence.range
      )
      return
    }
    guard
      let resolvedCorrections = ContextualCorrectionResolver.resolve(
        result,
        in: capturedSentence,
        language: language
      )
    else {
      recordDiagnostic(
        .contextualProposalRejected,
        range: capturedSentence.range
      )
      return
    }

    let actionName = String(
      localized: "Correct in Context",
      bundle: #bundle,
      comment:
        "Undo menu action name for one or more on-device contextual Typover corrections."
    )
    let shouldGroupUndo = resolvedCorrections.count > 1
    if shouldGroupUndo {
      undoManager?.beginUndoGrouping()
    }
    defer {
      if shouldGroupUndo {
        undoManager?.endUndoGrouping()
        undoManager?.setActionName(actionName)
      }
    }

    for resolved in resolvedCorrections.sorted(by: {
      $0.range.location > $1.range.location
    }) {
      let proposal = resolved.proposal
      let correction = proposal.correction
      correctionsByID[correction.id] = correction
      proposalsByID[correction.id] = proposal
      ledger.record(correction)
      let didApply = replaceCorrectionText(
        correctionAfter: correction,
        correctionForReverse: correction,
        range: resolved.range,
        expectedText: correction.original,
        replacementText: correction.replacement,
        annotateReplacement: true,
        dispositionAfter: .applied,
        undoAnnotatesReplacement: false,
        undoDisposition: .restored,
        actionName: actionName
      )
      if didApply {
        learningStore.recordApplied(proposal)
      }
    }
  }

  @discardableResult
  private func replaceCorrectionText(
    correctionAfter: Correction,
    correctionForReverse: Correction,
    range: NSRange,
    expectedText: String,
    replacementText: String,
    annotateReplacement: Bool,
    dispositionAfter: CorrectionDisposition,
    undoAnnotatesReplacement: Bool,
    undoDisposition: CorrectionDisposition,
    learningEffectAfter: LearningEffect = .none,
    reverseLearningEffect: LearningEffect = .none,
    actionName: String
  ) -> Bool {
    guard let textStorage else {
      return false
    }
    guard NSMaxRange(range) <= textStorage.length else {
      recordDiagnostic(
        .staleRange,
        correctionID: correctionAfter.id,
        range: range
      )
      ledger.transition(correctionAfter.id, to: .invalidated)
      return false
    }
    guard
      (textStorage.string as NSString).substring(with: range) == expectedText
    else {
      recordDiagnostic(
        .staleText,
        correctionID: correctionAfter.id,
        range: range
      )
      ledger.transition(correctionAfter.id, to: .invalidated)
      return false
    }

    let clock = ContinuousClock()
    let transactionStart = clock.now
    isPerformingCorrection = true
    undoManager?.disableUndoRegistration()
    guard shouldChangeText(in: range, replacementString: replacementText) else {
      undoManager?.enableUndoRegistration()
      isPerformingCorrection = false
      recordDiagnostic(
        .editRejected,
        correctionID: correctionAfter.id,
        range: range
      )
      ledger.transition(correctionAfter.id, to: .invalidated)
      return false
    }

    let selectionBeforeChange = selectedRange()
    let replacementRange = NSRange(
      location: range.location,
      length: replacementText.utf16.count
    )

    textStorage.beginEditing()
    textStorage.replaceCharacters(in: range, with: replacementText)
    if annotateReplacement {
      textStorage.addAttribute(
        .typoverCorrectionID,
        value: correctionAfter.id.uuidString,
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
    undoManager?.enableUndoRegistration()
    isPerformingCorrection = false
    recordTransactionSample(
      correctionID: correctionAfter.id,
      elapsed: transactionStart.duration(to: clock.now)
    )

    correctionsByID[correctionAfter.id] = correctionAfter
    ledger.record(correctionAfter)
    ledger.transition(correctionAfter.id, to: dispositionAfter)
    applyLearningEffect(
      learningEffectAfter,
      correctionID: correctionAfter.id
    )

    undoManager?.registerUndo(withTarget: self) { target in
      let currentRange =
        annotateReplacement
        ? target.annotatedRanges(for: correctionAfter.id).first
          ?? replacementRange
        : replacementRange
      target.replaceCorrectionText(
        correctionAfter: correctionForReverse,
        correctionForReverse: correctionAfter,
        range: currentRange,
        expectedText: replacementText,
        replacementText: expectedText,
        annotateReplacement: undoAnnotatesReplacement,
        dispositionAfter: undoDisposition,
        undoAnnotatesReplacement: annotateReplacement,
        undoDisposition: dispositionAfter,
        learningEffectAfter: reverseLearningEffect,
        reverseLearningEffect: learningEffectAfter,
        actionName: actionName
      )
    }
    undoManager?.setActionName(actionName)
    return true
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
      let manualReplacement =
        pendingManualCorrections[id]?.replacement
        ?? (ranges.count == 1
          ? (textStorage.string as NSString).substring(with: ranges[0])
          : nil)
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
      recordDiagnostic(
        .annotationInvalidated,
        correctionID: id,
        range: ranges.first
      )
      ledger.transition(id, to: .invalidated)
      if let proposal = proposalsByID[id] {
        recordEngineResponse(.edited, for: proposal)
        if pendingManualCorrections[id] == nil {
          recordManualEdit(
            manualReplacement,
            for: proposal
          )
        }
      }
    }
  }

  private func captureManualReplacement(
    in affectedRange: NSRange,
    replacementString: String
  ) {
    guard let textStorage else {
      return
    }

    for (id, _) in correctionsByID {
      guard
        ledger.record(for: id)?.disposition == .applied,
        let annotationRange = annotatedRanges(for: id).first,
        affectedRange.location >= annotationRange.location,
        NSMaxRange(affectedRange) <= NSMaxRange(annotationRange)
      else {
        continue
      }

      let currentText = (textStorage.string as NSString).substring(
        with: annotationRange
      )
      let localRange = NSRange(
        location: affectedRange.location - annotationRange.location,
        length: affectedRange.length
      )
      let replacement =
        (currentText as NSString).replacingCharacters(
          in: localRange,
          with: replacementString
        )
      pendingManualCorrections[id] = PendingManualCorrection(
        correctionID: id,
        range: NSRange(
          location: annotationRange.location,
          length: replacement.utf16.count
        ),
        replacement: replacement
      )
    }
  }

  private func updatePendingManualCorrections(
    for affectedRange: NSRange,
    replacementString: String
  ) {
    for id in Array(pendingManualCorrections.keys) {
      guard var pending = pendingManualCorrections[id] else {
        continue
      }

      let editContinuesReplacement =
        affectedRange.location >= pending.range.location
        && NSMaxRange(affectedRange) <= NSMaxRange(pending.range)
        && isWordEdit(replacementString)
      guard editContinuesReplacement else {
        finalizePendingManualCorrection(id)
        continue
      }

      let localRange = NSRange(
        location: affectedRange.location - pending.range.location,
        length: affectedRange.length
      )
      pending.replacement =
        (pending.replacement as NSString).replacingCharacters(
          in: localRange,
          with: replacementString
        )
      pending.range.length = pending.replacement.utf16.count
      pendingManualCorrections[id] = pending
    }
  }

  private func finalizePendingManualCorrection(_ id: Correction.ID) {
    guard
      let pending = pendingManualCorrections.removeValue(forKey: id),
      let proposal = proposalsByID[pending.correctionID]
    else {
      return
    }
    recordManualEdit(pending.replacement, for: proposal)
  }

  private func isWordEdit(_ replacement: String) -> Bool {
    replacement.allSatisfy { character in
      character.isLetter || character == "'" || character == "’"
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
      let menu = correctionMenu(for: id),
      let firstItem = menu.items.first
    else {
      return
    }

    menu.popUp(
      positioning: firstItem,
      at: convert(event.locationInWindow, from: nil),
      in: self
    )
  }

  func correctionMenu(for id: Correction.ID) -> NSMenu? {
    guard
      let correction = correctionsByID[id],
      ledger.record(for: id)?.disposition == .applied
    else {
      return nil
    }

    let menu = NSMenu()
    let changeBackItem = NSMenuItem(
      title: String(
        localized: "Revert to “\(correction.original)”",
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

    let replacements =
      ([proposalsByID[id]?.correction.replacement].compactMap { $0 }
      + (proposalsByID[id]?.alternatives ?? []))
      .filter { $0 != correction.replacement }

    if !replacements.isEmpty {
      menu.addItem(.separator())
      for replacement in replacements {
        let alternativeItem = NSMenuItem(
          title: replacement,
          action: #selector(useAlternative(_:)),
          keyEquivalent: ""
        )
        alternativeItem.representedObject = AlternativeSelection(
          correctionID: id,
          replacement: replacement
        )
        alternativeItem.target = self
        menu.addItem(alternativeItem)
      }
    }

    menu.addItem(.separator())
    let sourceItem = NSMenuItem(
      title: sourceTitle(for: proposalsByID[id]?.source),
      action: nil,
      keyEquivalent: ""
    )
    sourceItem.isEnabled = false
    menu.addItem(sourceItem)
    return menu
  }

  @objc
  private func changeBack(_ sender: NSMenuItem) {
    guard let id = correctionID(from: sender) else {
      return
    }
    changeBack(correctionID: id)
  }

  @discardableResult
  func changeBack(correctionID id: Correction.ID) -> Bool {
    guard
      let correction = correctionsByID[id],
      let range = annotatedRanges(for: id).first
    else {
      return false
    }

    let didReplace = replaceCorrectionText(
      correctionAfter: correction,
      correctionForReverse: correction,
      range: range,
      expectedText: correction.replacement,
      replacementText: correction.original,
      annotateReplacement: false,
      dispositionAfter: .restored,
      undoAnnotatesReplacement: true,
      undoDisposition: .applied,
      learningEffectAfter: .suppress,
      reverseLearningEffect: restorationEffect(
        for: correction,
        proposal: proposalsByID[id]
      ),
      actionName: String(
        localized: "Change Back",
        bundle: #bundle,
        comment: "Undo menu action name after restoring an automatically corrected word."
      )
    )
    if didReplace, let proposal = proposalsByID[id] {
      recordEngineResponse(.reverted, for: proposal)
    }
    return didReplace
  }

  @objc
  private func useAlternative(_ sender: NSMenuItem) {
    guard let selection = sender.representedObject as? AlternativeSelection else {
      return
    }
    useAlternative(
      correctionID: selection.correctionID,
      replacement: selection.replacement
    )
  }

  @discardableResult
  func useAlternative(
    correctionID: Correction.ID,
    replacement: String
  ) -> Bool {
    guard
      let correction = correctionsByID[correctionID],
      let range = annotatedRanges(for: correctionID).first
    else {
      return false
    }
    let alternative = Correction(
      id: correction.id,
      original: correction.original,
      replacement: replacement,
      createdAt: correction.createdAt
    )
    let didReplace = replaceCorrectionText(
      correctionAfter: alternative,
      correctionForReverse: correction,
      range: range,
      expectedText: correction.replacement,
      replacementText: alternative.replacement,
      annotateReplacement: true,
      dispositionAfter: .applied,
      undoAnnotatesReplacement: true,
      undoDisposition: .applied,
      learningEffectAfter: .prefer(
        alternative.replacement,
        outcome: .alternativeChosen
      ),
      reverseLearningEffect: restorationEffect(
        for: correction,
        proposal: proposalsByID[correction.id]
      ),
      actionName: String(
        localized: "Change Correction",
        bundle: #bundle,
        comment: "Undo menu action name after choosing a different spelling correction."
      )
    )
    if didReplace, let proposal = proposalsByID[correction.id] {
      recordEngineResponse(.edited, for: proposal)
    }
    return didReplace
  }

  private func applyLearningEffect(
    _ effect: LearningEffect,
    correctionID: Correction.ID
  ) {
    guard
      let proposal = proposalsByID[correctionID]
    else {
      return
    }

    switch effect {
    case .none:
      return
    case .removePreference:
      guard !isContextualSource(proposal.source) else {
        return
      }
      learningStore.removePreference(
        for: proposal.correction.original,
        language: proposal.language
      )
    case .suppress:
      if isContextualSource(proposal.source) {
        learningStore.recordOutcome(.reverted, for: proposal)
      } else {
        learningStore.recordReverted(proposal)
      }
    case .prefer(let replacement, let outcome):
      if isContextualSource(proposal.source) {
        if let outcome {
          learningStore.recordOutcome(outcome, for: proposal)
        }
      } else {
        learningStore.recordPreferred(
          replacement,
          for: proposal,
          outcome: outcome
        )
      }
    }
  }

  private func restorationEffect(
    for correction: Correction,
    proposal: CorrectionProposal?
  ) -> LearningEffect {
    guard let proposal else {
      return .none
    }

    if proposal.source == .rememberedPreference
      || correction.replacement != proposal.correction.replacement
    {
      return .prefer(correction.replacement, outcome: nil)
    }
    return .removePreference
  }

  private func recordManualEdit(
    _ replacement: String?,
    for proposal: CorrectionProposal
  ) {
    if isContextualSource(proposal.source) {
      learningStore.recordOutcome(.manuallyEdited, for: proposal)
    } else {
      learningStore.recordManualEdit(replacement, for: proposal)
    }
  }

  private func recordEngineResponse(
    _ response: CorrectionUserResponse,
    for proposal: CorrectionProposal
  ) {
    guard !isContextualSource(proposal.source) else {
      return
    }
    correctionEngine.record(response, for: proposal)
  }

  private func sourceTitle(
    for source: CorrectionSource?
  ) -> String {
    switch source {
    case .appleIntelligence:
      return String(
        localized: "Apple Intelligence",
        bundle: #bundle,
        comment:
          "Disabled correction-menu label identifying Apple's local contextual model."
      )
    case .appleIntelligenceRewrite:
      return String(
        localized: "Apple Rewrite",
        bundle: #bundle,
        comment:
          "Disabled correction-menu label identifying an opt-in local sentence rewrite."
      )
    case .rememberedPreference:
      return String(
        localized: "Remembered Preference",
        bundle: #bundle,
        comment:
          "Disabled correction-menu label identifying a locally remembered correction preference."
      )
    case .appleSpelling, .demo, nil:
      return String(
        localized: "Apple Spelling",
        bundle: #bundle,
        comment: "Disabled correction-menu label identifying the local spelling source."
      )
    }
  }

  private func isContextualSource(_ source: CorrectionSource) -> Bool {
    source == .appleIntelligence
      || source == .appleIntelligenceRewrite
  }

  private func correctionID(from menuItem: NSMenuItem) -> Correction.ID? {
    guard let rawID = menuItem.representedObject as? String else {
      return nil
    }
    return Correction.ID(uuidString: rawID)
  }

  private func performPaste(_ edit: () -> Void) {
    isPerformingPaste = true
    defer { isPerformingPaste = false }
    edit()
  }

  private func recordDiagnostic(
    _ kind: CorrectionDiagnosticKind,
    correctionID: Correction.ID? = nil,
    range: NSRange? = nil
  ) {
    correctionDiagnostics.append(
      CorrectionDiagnostic(
        kind: kind,
        correctionID: correctionID,
        range: range,
        documentUTF16Length: textStorage?.length ?? 0
      )
    )
    let maximumDiagnostics = 200
    if correctionDiagnostics.count > maximumDiagnostics {
      correctionDiagnostics.removeFirst(
        correctionDiagnostics.count - maximumDiagnostics
      )
    }
  }

  private func recordTransactionSample(
    correctionID: Correction.ID,
    elapsed: Duration
  ) {
    correctionTransactionSamples.append(
      CorrectionTransactionSample(
        correctionID: correctionID,
        elapsed: elapsed,
        documentUTF16Length: textStorage?.length ?? 0
      )
    )
    let maximumSamples = 200
    if correctionTransactionSamples.count > maximumSamples {
      correctionTransactionSamples.removeFirst(
        correctionTransactionSamples.count - maximumSamples
      )
    }
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
