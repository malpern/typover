import AppKit
import CoreGraphics
import TypoverAccessibility
import TypoverBearAdapter
import TypoverCore

enum BearTextExpansionExperimentConfiguration {
  static let environmentKey = "TYPOVER_EXPERIMENTAL_BEAR_TEXT_EXPANSION"

  static func isEnabled(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Bool {
    environment[environmentKey] == "1"
  }
}

/// A deliberately narrow, disabled-by-default experiment for comparing
/// text-expander-style mutation with Bear's production idle-first AX lane.
/// Planning is pure and transport is protocol-isolated so no caller can treat
/// emitted key events as a verified correction.
struct BearTextExpansionRequest: Equatable, Sendable {
  let original: String
  let replacement: String
  let boundary: String
  let bearIsFrontmost: Bool
  let selectionIsCollapsed: Bool
  let hasMarkedText: Bool
  let secureInputIsActive: Bool
  let isKeyRepeat: Bool
}

struct BearTextExpansionPlan: Equatable, Sendable {
  let original: String
  let replacement: String
  let boundary: String
  let deleteCount: Int
  let insertedText: String
}

enum BearTextExpansionRefusal: Equatable, Sendable {
  case bearNotFrontmost
  case activeSelection
  case markedText
  case secureInput
  case keyRepeat
  case unsupportedBoundary
  case unsupportedWord
  case invalidProposal
}

enum BearTextExpansionPlanningResult: Equatable, Sendable {
  case planned(BearTextExpansionPlan)
  case refused(BearTextExpansionRefusal)
}

enum BearTextExpansionInputToken: Equatable, Sendable {
  case text(String)
  case boundary(String)
  case invalidate
}

struct BearTextExpansionCompletion: Equatable, Sendable {
  let word: String
  let boundary: String
}

struct BearTextExpansionWordTracker: Sendable {
  private var word = ""

  mutating func consume(
    _ token: BearTextExpansionInputToken
  ) -> BearTextExpansionCompletion? {
    switch token {
    case .text(let text):
      guard
        text.utf16.count == 1,
        text.unicodeScalars.allSatisfy({ scalar in
          scalar.value >= 65 && scalar.value <= 90
            || scalar.value >= 97 && scalar.value <= 122
        }),
        word.utf16.count < BearTextExpansionPlanner.maximumWordLength
      else {
        word = ""
        return nil
      }
      word += text
      return nil
    case .boundary(let boundary):
      defer { word = "" }
      guard !word.isEmpty else {
        return nil
      }
      return BearTextExpansionCompletion(
        word: word,
        boundary: boundary
      )
    case .invalidate:
      word = ""
      return nil
    }
  }

  mutating func reset() {
    word = ""
  }
}

enum BearTextExpansionPlanner {
  static let maximumWordLength = 48

  static func plan(
    _ request: BearTextExpansionRequest
  ) -> BearTextExpansionPlanningResult {
    guard request.bearIsFrontmost else {
      return .refused(.bearNotFrontmost)
    }
    guard request.selectionIsCollapsed else {
      return .refused(.activeSelection)
    }
    guard !request.hasMarkedText else {
      return .refused(.markedText)
    }
    guard !request.secureInputIsActive else {
      return .refused(.secureInput)
    }
    guard !request.isKeyRepeat else {
      return .refused(.keyRepeat)
    }
    guard
      request.boundary.utf16.count == 1,
      BearTypingInput.isCompletionBoundary(request.boundary)
    else {
      return .refused(.unsupportedBoundary)
    }
    guard
      isLowercaseASCIIWord(request.original),
      request.original.utf16.count <= maximumWordLength
    else {
      return .refused(.unsupportedWord)
    }
    guard
      !request.replacement.isEmpty,
      request.replacement != request.original,
      isSingleReplacementToken(request.replacement),
      request.replacement.utf16.count <= maximumWordLength * 2
    else {
      return .refused(.invalidProposal)
    }

    return .planned(
      BearTextExpansionPlan(
        original: request.original,
        replacement: request.replacement,
        boundary: request.boundary,
        deleteCount: request.original.utf16.count
          + request.boundary.utf16.count,
        insertedText: request.replacement + request.boundary
      )
    )
  }

  private static func isLowercaseASCIIWord(_ text: String) -> Bool {
    guard !text.isEmpty else {
      return false
    }
    return text.unicodeScalars.allSatisfy { scalar in
      scalar.value >= 97 && scalar.value <= 122
    }
  }

  private static func isSingleReplacementToken(_ text: String) -> Bool {
    text.unicodeScalars.allSatisfy { scalar in
      !CharacterSet.whitespacesAndNewlines.contains(scalar)
        && !CharacterSet.controlCharacters.contains(scalar)
    }
  }
}

protocol BearTextExpansionPerforming: Sendable {
  /// Emits a provisional mutation. `true` means only that all events were
  /// created and posted; it is never evidence that Bear accepted the edit.
  func perform(_ plan: BearTextExpansionPlan) -> Bool
}

struct CGEventBearTextExpansionPerformer:
  BearTextExpansionPerforming, Sendable
{
  static let syntheticEventMarker: Int64 = 0x54_5950_4F56_4552
  private static let deleteKeyCode: CGKeyCode = 51
  private let isExperimentEnabled: @Sendable () -> Bool

  init(
    isExperimentEnabled: @escaping @Sendable () -> Bool = {
      BearTextExpansionExperimentConfiguration.isEnabled()
    }
  ) {
    self.isExperimentEnabled = isExperimentEnabled
  }

  func perform(_ plan: BearTextExpansionPlan) -> Bool {
    guard
      isExperimentEnabled(),
      plan.deleteCount > 0,
      !plan.insertedText.isEmpty,
      let source = CGEventSource(stateID: .hidSystemState)
    else {
      return false
    }

    var events: [CGEvent] = []
    events.reserveCapacity(plan.deleteCount * 2 + 2)
    for _ in 0..<plan.deleteCount {
      guard
        let down = CGEvent(
          keyboardEventSource: source,
          virtualKey: Self.deleteKeyCode,
          keyDown: true
        ),
        let up = CGEvent(
          keyboardEventSource: source,
          virtualKey: Self.deleteKeyCode,
          keyDown: false
        )
      else {
        return false
      }
      events.append(down)
      events.append(up)
    }

    guard
      let insertionDown = CGEvent(
        keyboardEventSource: source,
        virtualKey: 0,
        keyDown: true
      ),
      let insertionUp = CGEvent(
        keyboardEventSource: source,
        virtualKey: 0,
        keyDown: false
      )
    else {
      return false
    }
    insertionDown.keyboardSetUnicodeString(
      stringLength: plan.insertedText.utf16.count,
      unicodeString: Array(plan.insertedText.utf16)
    )
    events.append(insertionDown)
    events.append(insertionUp)

    for event in events {
      event.setIntegerValueField(
        .eventSourceUserData,
        value: Self.syntheticEventMarker
      )
      event.post(tap: .cghidEventTap)
    }
    return true
  }

  static func isTypoverSyntheticEvent(_ event: NSEvent) -> Bool {
    event.cgEvent?.getIntegerValueField(.eventSourceUserData)
      == syntheticEventMarker
  }
}

enum BearTextExpansionVerification {
  /// Verifies the entire bounded before/after transition. Seeing the expected
  /// replacement near the caret is insufficient: document growth, caret
  /// movement, unchanged leading overlap, and trailing context must all prove
  /// that only the planned word and boundary changed.
  static func adoptionRequest(
    for plan: BearTextExpansionPlan,
    from authorized: BearTypingContextSnapshot,
    to current: BearTypingContextSnapshot
  ) -> BearSyntheticCorrectionAdoptionRequest? {
    let originalLength = plan.original.utf16.count
    let replacementLength = plan.replacement.utf16.count
    let boundaryLength = plan.boundary.utf16.count
    guard
      authorized.leadingText.utf16.count == authorized.leadingRange.length,
      authorized.caretLocation
        == authorized.leadingRange.location + authorized.leadingRange.length,
      authorized.documentLength >= authorized.caretLocation,
      current.leadingText.utf16.count == current.leadingRange.length,
      current.caretLocation
        == current.leadingRange.location + current.leadingRange.length,
      current.documentLength >= current.caretLocation,
      authorized.caretLocation >= originalLength
    else {
      return nil
    }

    let originalRange = AccessibilityTextRange(
      location: authorized.caretLocation - originalLength,
      length: originalLength
    )
    guard
      originalRange.location >= authorized.leadingRange.location,
      text(
        in: originalRange,
        snapshot: authorized
      ) == plan.original
    else {
      return nil
    }

    let expectedDelta = replacementLength + boundaryLength - originalLength
    let minimumDocumentLength = authorized.documentLength + expectedDelta
    let additionalGrowth = current.documentLength - minimumDocumentLength
    guard
      additionalGrowth >= 0,
      current.caretLocation
        == authorized.caretLocation + expectedDelta + additionalGrowth,
      current.trailingText == authorized.trailingText
    else {
      return nil
    }

    let insertedRange = AccessibilityTextRange(
      location: originalRange.location,
      length: replacementLength + boundaryLength
    )
    guard
      text(in: insertedRange, snapshot: current) == plan.insertedText,
      unchangedLeadingOverlap(
        before: authorized,
        after: current,
        endingAt: originalRange.location
      )
    else {
      return nil
    }

    return BearSyntheticCorrectionAdoptionRequest(
      original: plan.original,
      replacement: plan.replacement,
      originalRange: originalRange,
      replacementRange: AccessibilityTextRange(
        location: originalRange.location,
        length: replacementLength
      ),
      selectionAfter: AccessibilityTextRange(
        location: current.caretLocation,
        length: 0
      )
    )
  }

  private static func unchangedLeadingOverlap(
    before: BearTypingContextSnapshot,
    after: BearTypingContextSnapshot,
    endingAt end: Int
  ) -> Bool {
    let start = max(
      before.leadingRange.location,
      after.leadingRange.location
    )
    guard end >= start else {
      return false
    }
    let range = AccessibilityTextRange(
      location: start,
      length: end - start
    )
    return text(in: range, snapshot: before)
      == text(in: range, snapshot: after)
  }

  private static func text(
    in range: AccessibilityTextRange,
    snapshot: BearTypingContextSnapshot
  ) -> String? {
    let localLocation = range.location - snapshot.leadingRange.location
    guard
      localLocation >= 0,
      range.length >= 0,
      localLocation + range.length <= snapshot.leadingText.utf16.count
    else {
      return nil
    }
    return (snapshot.leadingText as NSString).substring(
      with: NSRange(
        location: localLocation,
        length: range.length
      )
    )
  }
}

struct BearTextExpansionPendingMutation: Equatable, Sendable {
  let plan: BearTextExpansionPlan
  let authorizedSnapshot: BearTypingContextSnapshot
}

protocol BearSyntheticCorrectionAdopting: Sendable {
  func adoptSyntheticCorrection(
    _ request: BearSyntheticCorrectionAdoptionRequest
  ) -> BearCorrectionApplication
}

extension BearCorrectionAdapter: BearSyntheticCorrectionAdopting {}

struct BearTextExpansionPendingCorrection: Sendable {
  let mutation: BearTextExpansionPendingMutation
  let proposal: CorrectionProposal
  let boundaryObservedAt: ContinuousClock.Instant
}

enum BearTextExpansionCompletionResult: Sendable {
  case verified(BearCorrectionApplication)
  case transitionUnverified(AccessibilityTextRange)
  case adoptionFailed(BearCorrectionApplication)
}

struct BearTextExpansionExperimentalLane: Sendable {
  private let performer: (any BearTextExpansionPerforming)?
  private let adopter: any BearSyntheticCorrectionAdopting

  init(
    performer: any BearTextExpansionPerforming,
    adopter: any BearSyntheticCorrectionAdopting
  ) {
    self.performer = performer
    self.adopter = adopter
  }

  init(adopter: any BearSyntheticCorrectionAdopting) {
    performer = nil
    self.adopter = adopter
  }

  func begin(
    completion: BearTextExpansionCompletion,
    proposal: CorrectionProposal,
    authorizedSnapshot: BearTypingContextSnapshot,
    boundaryObservedAt: ContinuousClock.Instant,
    bearIsFrontmost: Bool,
    secureInputIsActive: Bool,
    hasMarkedText: Bool = false
  ) -> BearTextExpansionPendingCorrection? {
    let request = BearTextExpansionRequest(
      original: completion.word,
      replacement: proposal.correction.replacement,
      boundary: completion.boundary,
      bearIsFrontmost: bearIsFrontmost,
      selectionIsCollapsed: true,
      hasMarkedText: hasMarkedText,
      secureInputIsActive: secureInputIsActive,
      isKeyRepeat: false
    )
    guard
      let performer,
      proposal.correction.original == completion.word,
      case .planned(let plan) = BearTextExpansionPlanner.plan(request),
      let mutation = BearTextExpansionTransaction.begin(
        plan: plan,
        authorizedSnapshot: authorizedSnapshot,
        performer: performer
      )
    else {
      return nil
    }
    return BearTextExpansionPendingCorrection(
      mutation: mutation,
      proposal: proposal,
      boundaryObservedAt: boundaryObservedAt
    )
  }

  func beginPreDispatched(
    receipt: BearPreDispatchMutationReceipt,
    proposal: CorrectionProposal,
    bearIsFrontmost: Bool,
    secureInputIsActive: Bool
  ) -> BearTextExpansionPendingCorrection? {
    let plan = receipt.plan
    guard
      bearIsFrontmost,
      !secureInputIsActive,
      proposal.correction.original == plan.original,
      proposal.correction.replacement == plan.replacement,
      plan.boundary == " ",
      plan.deleteCount == plan.original.utf16.count,
      plan.insertedText == plan.replacement + plan.boundary,
      BearTextExpansionVerification.preWriteIsAuthorized(
        plan: plan,
        snapshot: receipt.predictedAuthorizedSnapshot
      )
    else {
      return nil
    }
    return BearTextExpansionPendingCorrection(
      mutation: BearTextExpansionPendingMutation(
        plan: plan,
        authorizedSnapshot: receipt.predictedAuthorizedSnapshot
      ),
      proposal: proposal,
      boundaryObservedAt: receipt.boundaryObservedAt
    )
  }

  func complete(
    _ pending: BearTextExpansionPendingCorrection,
    currentSnapshot: BearTypingContextSnapshot
  ) -> BearTextExpansionCompletionResult {
    guard
      let request = BearTextExpansionVerification.adoptionRequest(
        for: pending.mutation.plan,
        from: pending.mutation.authorizedSnapshot,
        to: currentSnapshot
      )
    else {
      let originalLength = pending.mutation.plan.original.utf16.count
      return .transitionUnverified(
        AccessibilityTextRange(
          location: max(
            0,
            pending.mutation.authorizedSnapshot.caretLocation
              - originalLength
          ),
          length: originalLength
        )
      )
    }

    let application = adopter.adoptSyntheticCorrection(request)
    guard application.isReversibleApplication else {
      return .adoptionFailed(application)
    }
    return .verified(application)
  }
}

enum BearTextExpansionTransaction {
  static func begin(
    plan: BearTextExpansionPlan,
    authorizedSnapshot: BearTypingContextSnapshot,
    performer: any BearTextExpansionPerforming
  ) -> BearTextExpansionPendingMutation? {
    guard
      BearTextExpansionVerification.preWriteIsAuthorized(
        plan: plan,
        snapshot: authorizedSnapshot
      ),
      performer.perform(plan)
    else {
      return nil
    }
    return BearTextExpansionPendingMutation(
      plan: plan,
      authorizedSnapshot: authorizedSnapshot
    )
  }
}

extension BearTextExpansionVerification {
  fileprivate static func preWriteIsAuthorized(
    plan: BearTextExpansionPlan,
    snapshot: BearTypingContextSnapshot
  ) -> Bool {
    let originalRange = AccessibilityTextRange(
      location: snapshot.caretLocation - plan.original.utf16.count,
      length: plan.original.utf16.count
    )
    return snapshot.leadingText.utf16.count == snapshot.leadingRange.length
      && snapshot.caretLocation
        == snapshot.leadingRange.location + snapshot.leadingRange.length
      && originalRange.location >= snapshot.leadingRange.location
      && text(in: originalRange, snapshot: snapshot) == plan.original
  }
}
