import AppKit
import Testing
import TypoverAccessibility
import TypoverBearAdapter
import TypoverCore

@testable import TypoverApp

@Suite("Bear text-expansion spike")
struct BearTextExpansionSpikeTests {
  @Test("The pre-dispatch model orders a prepared correction before Space")
  func preDispatchModelProducesBoundedPlan() throws {
    var machine = BearPreDispatchCorrectionStateMachine(
      rules: [
        BearPreDispatchCorrectionRule(
          original: "teh",
          replacement: "the"
        )
      ]
    )
    machine.authorize(
      from: BearTypingContextSnapshot(
        leadingRange: AccessibilityTextRange(location: 0, length: 0),
        leadingText: "",
        trailingText: "tail",
        caretLocation: 0,
        documentLength: 4
      )
    )

    #expect(machine.consume(.letter("t")) == .passThrough)
    #expect(machine.consume(.letter("e")) == .passThrough)
    #expect(machine.consume(.letter("h")) == .passThrough)
    let decision = machine.consume(.boundary(" "))

    guard
      case .replace(let plan, let authorizedSnapshot) = decision
    else {
      Issue.record("Expected a prepared pre-dispatch replacement")
      return
    }
    #expect(plan.deleteCount == 3)
    #expect(plan.replacement == "the")
    #expect(plan.insertedText == "the ")
    #expect(authorizedSnapshot.leadingText == "teh")
    #expect(authorizedSnapshot.trailingText == "tail")
    #expect(authorizedSnapshot.caretLocation == 3)
    #expect(authorizedSnapshot.documentLength == 7)
  }

  @Test("Every synthetic event is ordered before the physical boundary")
  func preDispatchEmissionSequenceReturnsBoundaryLast() {
    let steps = BearPreDispatchEmissionSequence.steps(
      for: BearTextExpansionPlan(
        original: "teh",
        replacement: "the",
        boundary: " ",
        deleteCount: 3,
        insertedText: "the "
      )
    )
    #expect(
      steps == [
        .deleteKeyDown,
        .deleteKeyUp,
        .deleteKeyDown,
        .deleteKeyUp,
        .deleteKeyDown,
        .deleteKeyUp,
        .replacementKeyDown("the"),
        .replacementKeyUp,
        .returnPhysicalBoundary,
      ]
    )
  }

  @Test("Each pre-dispatch correction requires fresh authorization")
  func preDispatchModelRequiresFreshAuthorization() {
    var machine = BearPreDispatchCorrectionStateMachine(
      rules: [
        BearPreDispatchCorrectionRule(
          original: "teh",
          replacement: "the"
        )
      ]
    )
    machine.authorize(
      from: BearTypingContextSnapshot(
        leadingRange: AccessibilityTextRange(location: 0, length: 0),
        leadingText: "",
        trailingText: "",
        caretLocation: 0,
        documentLength: 0
      )
    )

    #expect(machine.consume(.letter("t")) == .passThrough)
    #expect(machine.consume(.letter("e")) == .passThrough)
    #expect(machine.consume(.letter("h")) == .passThrough)
    guard case .replace = machine.consume(.boundary(" ")) else {
      Issue.record("Expected the authorized word to be replaced")
      return
    }

    #expect(machine.consume(.letter("t")) == .passThrough)
    #expect(machine.consume(.letter("e")) == .passThrough)
    #expect(machine.consume(.letter("h")) == .passThrough)
    #expect(machine.consume(.boundary(" ")) == .passThrough)

    machine.authorize(
      from: BearTypingContextSnapshot(
        leadingRange: AccessibilityTextRange(location: 0, length: 8),
        leadingText: "the teh ",
        trailingText: "",
        caretLocation: 8,
        documentLength: 8
      )
    )
    #expect(machine.consume(.letter("t")) == .passThrough)
    #expect(machine.consume(.letter("e")) == .passThrough)
    #expect(machine.consume(.letter("h")) == .passThrough)
    guard case .replace = machine.consume(.boundary(" ")) else {
      Issue.record("Fresh AX authorization should rearm one transaction")
      return
    }
  }

  @Test("The pre-dispatch model never matches a suffix of unknown text")
  func preDispatchModelRefusesUnknownPrefix() {
    var machine = BearPreDispatchCorrectionStateMachine(
      rules: [
        BearPreDispatchCorrectionRule(
          original: "teh",
          replacement: "the"
        )
      ]
    )
    machine.authorize(
      from: BearTypingContextSnapshot(
        leadingRange: AccessibilityTextRange(location: 0, length: 1),
        leadingText: "x",
        trailingText: "",
        caretLocation: 1,
        documentLength: 1
      )
    )

    #expect(machine.consume(.letter("t")) == .passThrough)
    #expect(machine.consume(.letter("e")) == .passThrough)
    #expect(machine.consume(.letter("h")) == .passThrough)
    #expect(machine.consume(.boundary(" ")) == .passThrough)

    #expect(machine.consume(.letter("t")) == .passThrough)
    #expect(machine.consume(.letter("e")) == .passThrough)
    #expect(machine.consume(.letter("h")) == .passThrough)
    guard case .replace = machine.consume(.boundary(" ")) else {
      Issue.record("Expected matching to resume after a known boundary")
      return
    }
  }

  @Test("Unsupported input invalidates the pre-dispatch prediction")
  func preDispatchModelFailsOpenAfterUnsupportedInput() {
    var machine = BearPreDispatchCorrectionStateMachine(
      rules: [
        BearPreDispatchCorrectionRule(
          original: "teh",
          replacement: "the"
        )
      ]
    )
    machine.authorize(
      from: BearTypingContextSnapshot(
        leadingRange: AccessibilityTextRange(location: 0, length: 0),
        leadingText: "",
        trailingText: "",
        caretLocation: 0,
        documentLength: 0
      )
    )
    #expect(machine.consume(.letter("t")) == .passThrough)
    #expect(machine.consume(.invalidate) == .passThrough)
    #expect(machine.consume(.letter("t")) == .passThrough)
    #expect(machine.consume(.letter("e")) == .passThrough)
    #expect(machine.consume(.letter("h")) == .passThrough)
    #expect(machine.consume(.boundary(" ")) == .passThrough)
  }

  @Test("Synthetic input does not disturb the physical word model")
  func preDispatchModelIgnoresSyntheticEvents() {
    var machine = BearPreDispatchCorrectionStateMachine(
      rules: [
        BearPreDispatchCorrectionRule(
          original: "teh",
          replacement: "the"
        )
      ]
    )
    machine.authorize(
      from: BearTypingContextSnapshot(
        leadingRange: AccessibilityTextRange(location: 0, length: 0),
        leadingText: "",
        trailingText: "",
        caretLocation: 0,
        documentLength: 0
      )
    )
    #expect(machine.consume(.letter("t")) == .passThrough)
    #expect(machine.consume(.synthetic) == .passThrough)
    #expect(machine.consume(.letter("e")) == .passThrough)
    #expect(machine.consume(.letter("h")) == .passThrough)
    guard case .replace = machine.consume(.boundary(" ")) else {
      Issue.record("Synthetic events must not reset the physical tracker")
      return
    }
  }

  @Test("The physical token tracker emits only one bounded completed word")
  func tracksPhysicalWord() {
    var tracker = BearTextExpansionWordTracker()
    #expect(tracker.consume(.text("t")) == nil)
    #expect(tracker.consume(.text("e")) == nil)
    #expect(tracker.consume(.text("h")) == nil)
    #expect(
      tracker.consume(.boundary(" "))
        == BearTextExpansionCompletion(word: "teh", boundary: " ")
    )
    #expect(tracker.consume(.boundary(" ")) == nil)

    #expect(tracker.consume(.text("t")) == nil)
    #expect(tracker.consume(.invalidate) == nil)
    #expect(tracker.consume(.text("e")) == nil)
    #expect(tracker.consume(.text("h")) == nil)
    #expect(
      tracker.consume(.boundary(" "))
        == BearTextExpansionCompletion(word: "eh", boundary: " ")
    )
  }

  @Test("Only direct nonrepeating letters feed the text-expansion tracker")
  func classifiesPhysicalTokens() {
    #expect(
      BearTypingInput.textExpansionToken(
        characters: "t",
        modifiers: [],
        intent: .other,
        isRepeat: false
      ) == .text("t")
    )
    #expect(
      BearTypingInput.textExpansionToken(
        characters: " ",
        modifiers: [],
        intent: .completionBoundary(" "),
        isRepeat: false
      ) == .boundary(" ")
    )
    #expect(
      BearTypingInput.textExpansionToken(
        characters: "t",
        modifiers: [.command],
        intent: .other,
        isRepeat: false
      ) == .invalidate
    )
    #expect(
      BearTypingInput.textExpansionToken(
        characters: "t",
        modifiers: [],
        intent: .other,
        isRepeat: true
      ) == .invalidate
    )
  }

  @Test("The experimental transport is disabled unless explicitly enabled")
  func experimentRequiresExplicitEnvironmentGate() {
    #expect(
      !BearTextExpansionExperimentConfiguration.isEnabled(environment: [:])
    )
    #expect(
      !BearTextExpansionExperimentConfiguration.isEnabled(
        environment: [
          BearTextExpansionExperimentConfiguration.environmentKey: "true"
        ]
      )
    )
    #expect(
      BearTextExpansionExperimentConfiguration.isEnabled(
        environment: [
          BearTextExpansionExperimentConfiguration.environmentKey: "1"
        ]
      )
    )

    let plan = BearTextExpansionPlan(
      original: "teh",
      replacement: "the",
      boundary: " ",
      deleteCount: 4,
      insertedText: "the "
    )
    #expect(
      !CGEventBearTextExpansionPerformer(
        isExperimentEnabled: { false }
      ).perform(plan)
    )
  }

  @Test("The narrow happy path produces an exact delete and insertion plan")
  func plansLowercaseASCIICorrection() throws {
    let result = BearTextExpansionPlanner.plan(
      BearTextExpansionRequest(
        original: "teh",
        replacement: "the",
        boundary: " ",
        bearIsFrontmost: true,
        selectionIsCollapsed: true,
        hasMarkedText: false,
        secureInputIsActive: false,
        isKeyRepeat: false
      )
    )
    let plan = try #require(result.plan)

    #expect(plan.deleteCount == 4)
    #expect(plan.insertedText == "the ")
  }

  @Test(
    "The spike refuses every ambiguous input condition",
    arguments: [
      BearTextExpansionPlanningResult.refused(.bearNotFrontmost),
      .refused(.activeSelection),
      .refused(.markedText),
      .refused(.secureInput),
      .refused(.keyRepeat),
      .refused(.unsupportedBoundary),
      .refused(.unsupportedWord),
      .refused(.invalidProposal),
    ])
  func refusesAmbiguousInput(
    expected: BearTextExpansionPlanningResult
  ) {
    var request = validRequest
    switch expected {
    case .refused(.bearNotFrontmost):
      request = request.replacing(bearIsFrontmost: false)
    case .refused(.activeSelection):
      request = request.replacing(selectionIsCollapsed: false)
    case .refused(.markedText):
      request = request.replacing(hasMarkedText: true)
    case .refused(.secureInput):
      request = request.replacing(secureInputIsActive: true)
    case .refused(.keyRepeat):
      request = request.replacing(isKeyRepeat: true)
    case .refused(.unsupportedBoundary):
      request = request.replacing(boundary: "x")
    case .refused(.unsupportedWord):
      request = request.replacing(original: "Teh")
    case .refused(.invalidProposal):
      request = request.replacing(replacement: "teh")
    case .planned:
      Issue.record("Expected a refusal test case")
    }

    #expect(BearTextExpansionPlanner.plan(request) == expected)
  }

  @Test("Verification derives only the exact replacement range")
  func verifiesExactPostWriteRange() throws {
    let plan = try #require(
      BearTextExpansionPlanner.plan(validRequest).plan
    )
    let authorized = BearTypingContextSnapshot(
      leadingRange: AccessibilityTextRange(location: 100, length: 10),
      leadingText: "prefix teh",
      trailingText: "tail",
      caretLocation: 110,
      documentLength: 114
    )
    let current = BearTypingContextSnapshot(
      leadingRange: AccessibilityTextRange(location: 100, length: 11),
      leadingText: "prefix the ",
      trailingText: "tail",
      caretLocation: 111,
      documentLength: 115
    )

    let request = try #require(
      BearTextExpansionVerification.adoptionRequest(
        for: plan,
        from: authorized,
        to: current
      )
    )
    #expect(
      request.originalRange
        == AccessibilityTextRange(location: 107, length: 3)
    )
    #expect(
      request.replacementRange
        == AccessibilityTextRange(location: 107, length: 3)
    )
    #expect(
      request.selectionAfter
        == AccessibilityTextRange(location: 111, length: 0)
    )
  }

  @Test("Verification permits append-only typing after the synthetic edit")
  func verifiesWhileTypingContinues() throws {
    let plan = try #require(
      BearTextExpansionPlanner.plan(validRequest).plan
    )
    let authorized = BearTypingContextSnapshot(
      leadingRange: AccessibilityTextRange(location: 0, length: 3),
      leadingText: "teh",
      trailingText: "tail",
      caretLocation: 3,
      documentLength: 7
    )
    let current = BearTypingContextSnapshot(
      leadingRange: AccessibilityTextRange(location: 0, length: 7),
      leadingText: "the xyz",
      trailingText: "tail",
      caretLocation: 7,
      documentLength: 11
    )

    let request = try #require(
      BearTextExpansionVerification.adoptionRequest(
        for: plan,
        from: authorized,
        to: current
      )
    )
    #expect(
      request.replacementRange
        == AccessibilityTextRange(location: 0, length: 3)
    )
    #expect(
      request.selectionAfter
        == AccessibilityTextRange(location: 7, length: 0)
    )
  }

  @Test("Verification refuses any changed bounded transition evidence")
  func refusesUnverifiedPostWriteState() throws {
    let plan = try #require(
      BearTextExpansionPlanner.plan(validRequest).plan
    )
    let authorized = BearTypingContextSnapshot(
      leadingRange: AccessibilityTextRange(location: 0, length: 10),
      leadingText: "prefix teh",
      trailingText: "tail",
      caretLocation: 10,
      documentLength: 14
    )
    let invalidSnapshots = [
      BearTypingContextSnapshot(
        leadingRange: AccessibilityTextRange(location: 0, length: 11),
        leadingText: "prefix teh ",
        trailingText: "tail",
        caretLocation: 11,
        documentLength: 15
      ),
      BearTypingContextSnapshot(
        leadingRange: AccessibilityTextRange(location: 0, length: 11),
        leadingText: "changedthe ",
        trailingText: "tail",
        caretLocation: 11,
        documentLength: 15
      ),
      BearTypingContextSnapshot(
        leadingRange: AccessibilityTextRange(location: 0, length: 11),
        leadingText: "prefix the ",
        trailingText: "different",
        caretLocation: 11,
        documentLength: 15
      ),
      BearTypingContextSnapshot(
        leadingRange: AccessibilityTextRange(location: 0, length: 11),
        leadingText: "prefix the ",
        trailingText: "tail",
        caretLocation: 10,
        documentLength: 15
      ),
      BearTypingContextSnapshot(
        leadingRange: AccessibilityTextRange(location: 0, length: 11),
        leadingText: "prefix the ",
        trailingText: "tail",
        caretLocation: 11,
        documentLength: 16
      ),
    ]

    for snapshot in invalidSnapshots {
      #expect(
        BearTextExpansionVerification.adoptionRequest(
          for: plan,
          from: authorized,
          to: snapshot
        ) == nil
      )
    }
  }

  @Test("The transaction emits only from exact authorized pre-write text")
  func beginsOnlyFromAuthorizedSnapshot() throws {
    let plan = try #require(
      BearTextExpansionPlanner.plan(validRequest).plan
    )
    let performer = RecordingTextExpansionPerformer()
    let authorized = BearTypingContextSnapshot(
      leadingRange: AccessibilityTextRange(location: 0, length: 3),
      leadingText: "teh",
      trailingText: "",
      caretLocation: 3,
      documentLength: 3
    )

    let pending = BearTextExpansionTransaction.begin(
      plan: plan,
      authorizedSnapshot: authorized,
      performer: performer
    )
    #expect(pending?.plan == plan)
    #expect(performer.plans == [plan])

    let stale = BearTypingContextSnapshot(
      leadingRange: AccessibilityTextRange(location: 0, length: 3),
      leadingText: "ten",
      trailingText: "",
      caretLocation: 3,
      documentLength: 3
    )
    #expect(
      BearTextExpansionTransaction.begin(
        plan: plan,
        authorizedSnapshot: stale,
        performer: performer
      ) == nil
    )
    #expect(performer.plans == [plan])
  }

  @Test("The experimental lane adopts only a fully verified transition")
  func laneAdoptsVerifiedTransition() throws {
    let performer = RecordingTextExpansionPerformer()
    let adopter = RecordingSyntheticCorrectionAdopter()
    let lane = BearTextExpansionExperimentalLane(
      performer: performer,
      adopter: adopter
    )
    let proposal = CorrectionProposal(
      correction: Correction(original: "teh", replacement: "the"),
      source: .appleSpelling
    )
    let authorized = BearTypingContextSnapshot(
      leadingRange: AccessibilityTextRange(location: 0, length: 3),
      leadingText: "teh",
      trailingText: "",
      caretLocation: 3,
      documentLength: 3
    )
    let pending = try #require(
      lane.begin(
        completion: BearTextExpansionCompletion(
          word: "teh",
          boundary: " "
        ),
        proposal: proposal,
        authorizedSnapshot: authorized,
        boundaryObservedAt: ContinuousClock().now,
        bearIsFrontmost: true,
        secureInputIsActive: false
      )
    )
    let current = BearTypingContextSnapshot(
      leadingRange: AccessibilityTextRange(location: 0, length: 4),
      leadingText: "the ",
      trailingText: "",
      caretLocation: 4,
      documentLength: 4
    )

    let result = lane.complete(pending, currentSnapshot: current)

    guard case .verified(let application) = result else {
      Issue.record("Expected a verified synthetic application")
      return
    }
    #expect(application.isReversibleApplication)
    #expect(adopter.requests.count == 1)
    #expect(
      adopter.requests.first?.replacementRange
        == AccessibilityTextRange(location: 0, length: 3)
    )
  }

  @Test("The experimental lane never adopts an ambiguous transition")
  func laneRejectsAmbiguousTransition() throws {
    let performer = RecordingTextExpansionPerformer()
    let adopter = RecordingSyntheticCorrectionAdopter()
    let lane = BearTextExpansionExperimentalLane(
      performer: performer,
      adopter: adopter
    )
    let pending = try #require(
      lane.begin(
        completion: BearTextExpansionCompletion(
          word: "teh",
          boundary: " "
        ),
        proposal: CorrectionProposal(
          correction: Correction(original: "teh", replacement: "the"),
          source: .appleSpelling
        ),
        authorizedSnapshot: BearTypingContextSnapshot(
          leadingRange: AccessibilityTextRange(location: 0, length: 3),
          leadingText: "teh",
          trailingText: "",
          caretLocation: 3,
          documentLength: 3
        ),
        boundaryObservedAt: ContinuousClock().now,
        bearIsFrontmost: true,
        secureInputIsActive: false
      )
    )
    let changed = BearTypingContextSnapshot(
      leadingRange: AccessibilityTextRange(location: 0, length: 4),
      leadingText: "ten ",
      trailingText: "",
      caretLocation: 4,
      documentLength: 4
    )

    let result = lane.complete(pending, currentSnapshot: changed)

    guard case .transitionUnverified = result else {
      Issue.record("Expected transition verification to fail")
      return
    }
    #expect(adopter.requests.isEmpty)
  }

  private var validRequest: BearTextExpansionRequest {
    BearTextExpansionRequest(
      original: "teh",
      replacement: "the",
      boundary: " ",
      bearIsFrontmost: true,
      selectionIsCollapsed: true,
      hasMarkedText: false,
      secureInputIsActive: false,
      isKeyRepeat: false
    )
  }
}

private final class RecordingTextExpansionPerformer:
  BearTextExpansionPerforming, @unchecked Sendable
{
  private let lock = NSLock()
  private var storedPlans: [BearTextExpansionPlan] = []

  var plans: [BearTextExpansionPlan] {
    lock.withLock { storedPlans }
  }

  func perform(_ plan: BearTextExpansionPlan) -> Bool {
    lock.withLock {
      storedPlans.append(plan)
    }
    return true
  }
}

private final class RecordingSyntheticCorrectionAdopter:
  BearSyntheticCorrectionAdopting, @unchecked Sendable
{
  private let lock = NSLock()
  private var storedRequests: [BearSyntheticCorrectionAdoptionRequest] = []

  var requests: [BearSyntheticCorrectionAdoptionRequest] {
    lock.withLock { storedRequests }
  }

  func adoptSyntheticCorrection(
    _ request: BearSyntheticCorrectionAdoptionRequest
  ) -> BearCorrectionApplication {
    lock.withLock {
      storedRequests.append(request)
    }
    let correction = Correction(
      original: request.original,
      replacement: request.replacement
    )
    return BearCorrectionApplication(
      report: BearExactRangeReplacementReport(
        status: .applied,
        writeOccurred: true,
        targetRange: request.originalRange,
        replacementRange: request.replacementRange,
        selectionAfter: request.selectionAfter,
        surroundingContextVerified: true,
        caretRestored: true
      ),
      correction: correction,
      correctionRecord: CorrectionRecord(correction: correction),
      correctionAnchor: BearCorrectionAnchor(
        correctionRange: request.replacementRange,
        documentLength: request.selectionAfter.location,
        leadingContext: "",
        trailingContext: " "
      )
    )
  }
}

extension BearTextExpansionPlanningResult {
  fileprivate var plan: BearTextExpansionPlan? {
    guard case .planned(let plan) = self else {
      return nil
    }
    return plan
  }
}

extension BearTextExpansionRequest {
  fileprivate func replacing(
    original: String? = nil,
    replacement: String? = nil,
    boundary: String? = nil,
    bearIsFrontmost: Bool? = nil,
    selectionIsCollapsed: Bool? = nil,
    hasMarkedText: Bool? = nil,
    secureInputIsActive: Bool? = nil,
    isKeyRepeat: Bool? = nil
  ) -> Self {
    Self(
      original: original ?? self.original,
      replacement: replacement ?? self.replacement,
      boundary: boundary ?? self.boundary,
      bearIsFrontmost: bearIsFrontmost ?? self.bearIsFrontmost,
      selectionIsCollapsed:
        selectionIsCollapsed ?? self.selectionIsCollapsed,
      hasMarkedText: hasMarkedText ?? self.hasMarkedText,
      secureInputIsActive:
        secureInputIsActive ?? self.secureInputIsActive,
      isKeyRepeat: isKeyRepeat ?? self.isKeyRepeat
    )
  }
}
