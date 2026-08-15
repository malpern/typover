import AppKit
import Foundation
import Testing
import TypoverAccessibility
import TypoverBearAdapter
import TypoverCore
import TypoverOverlay

@testable import TypoverApp

@MainActor
@Suite("Bear automatic correction", .serialized)
struct BearAutomaticCorrectionCoordinatorTests {
  @Test("The VoiceOver safety pause lasts until the next Mac boot")
  func voiceOverSafetyPauseIsBootScoped() throws {
    let suiteName = "BearVoiceOverSafetyLatchTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let voiceOver = TestBoolean(false)

    let firstBoot = BearVoiceOverSafetyLatch(
      defaults: defaults,
      bootIdentifier: { "boot-a" },
      voiceOverIsEnabled: { voiceOver.value }
    )
    #expect(!firstBoot.requiresPause())

    voiceOver.value = true
    #expect(firstBoot.requiresPause())
    voiceOver.value = false
    #expect(firstBoot.requiresPause())

    let sameBootRelaunch = BearVoiceOverSafetyLatch(
      defaults: defaults,
      bootIdentifier: { "boot-a" },
      voiceOverIsEnabled: { false }
    )
    #expect(sameBootRelaunch.requiresPause())

    let nextBoot = BearVoiceOverSafetyLatch(
      defaults: defaults,
      bootIdentifier: { "boot-b" },
      voiceOverIsEnabled: { false }
    )
    #expect(!nextBoot.requiresPause())
  }

  @Test("The real boot identifier is a stable boot-session identity")
  func systemBootIdentifierDoesNotDriftWithinABoot() throws {
    let identifier = try #require(
      BearVoiceOverSafetyLatch.systemBootIdentifier()
    )
    #expect(BearVoiceOverSafetyLatch.systemBootIdentifier() == identifier)
    // Pins the identity to `kern.bootsessionuuid`. A seconds-based value such
    // as `kern.boottime` is recomputed from the wall clock and can move inside
    // one boot, which would release the safety pause while Bear is still
    // unsafe to mutate.
    #expect(UUID(uuidString: identifier) != nil)
  }

  @Test("Only word-completion characters arm automatic correction")
  func recognizesBoundaryInput() {
    #expect(BearTypingInput.isCompletionBoundary(" "))
    #expect(BearTypingInput.isCompletionBoundary("\n"))
    #expect(BearTypingInput.isCompletionBoundary("."))
    #expect(!BearTypingInput.isCompletionBoundary("x"))
    #expect(!BearTypingInput.isCompletionBoundary(""))
    #expect(
      BearTypingInput.intent(characters: " ", modifiers: [])
        == .completionBoundary(" ")
    )
    #expect(
      BearTypingInput.intent(
        characters: "?",
        charactersIgnoringModifiers: "/",
        modifiers: [.shift]
      ) == .completionBoundary("?")
    )
    #expect(
      BearTypingInput.intent(
        characters: "Ω",
        charactersIgnoringModifiers: "z",
        modifiers: [.command]
      ) == .undoOrRedo
    )
    #expect(
      BearTypingInput.intent(
        characters: "Z",
        modifiers: [.command, .shift]
      ) == .undoOrRedo
    )
    #expect(
      BearTypingInput.intent(characters: " ", modifiers: [.option])
        == .other
    )
  }

  @Test("A verified typed boundary corrects the completed word")
  func correctsTypedBoundary() async throws {
    let fixture = try Fixture()
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)
    fixture.monitor.emit(.selectionChanged)
    #expect(
      await waitUntil {
        fixture.tracker.applications.count == 1
      }
    )

    let request = try #require(fixture.applicator.requests.first)
    #expect(request.original == "teh")
    #expect(request.replacement == "the")
    #expect(request.range == AccessibilityTextRange(location: 0, length: 3))
    #expect(fixture.tracker.applications.count == 1)
    #expect(fixture.tracker.userRecencies.count == 1)
    #expect(fixture.tracker.userRecencies[0] != nil)
    #expect(fixture.store.statistics().correctionsApplied == 1)
    #expect(fixture.coordinator.diagnostics.snapshot.boundaryInputs == 1)
    #expect(fixture.coordinator.diagnostics.snapshot.valueChanges == 1)
    // The applied diagnostic is recorded after annotation tracking, so it
    // trails the tracker signal this test already waited on.
    #expect(
      await waitUntil {
        fixture.coordinator.diagnostics.snapshot.correctionsApplied == 1
      }
    )
    #expect(
      fixture.coordinator.diagnostics.snapshot
        .correctionToAnnotationSampleCount == 1
    )

    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.reader.readCount >= 4
      }
    )
    #expect(fixture.coordinator.diagnostics.snapshot.valueChanges == 1)
    #expect(fixture.coordinator.diagnostics.snapshot.safeSkips == 0)
    #expect(fixture.coordinator.diagnostics.snapshot.lastOutcome == .applied)
  }

  @Test("The gated text-expansion path adopts a reversible correction")
  func adoptsVerifiedTextExpansion() async throws {
    let fixture = try Fixture(
      textExpansionEnabled: true,
      textExpansionVerificationDelays: [.milliseconds(1)]
    )
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.inputMonitor.emitText("t")
    fixture.inputMonitor.emitText("e")
    fixture.inputMonitor.emitText("h")
    fixture.reader.result = .ready(snapshot(text: "the ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)

    #expect(
      await waitUntil {
        fixture.tracker.applications.count == 1
      }
    )
    #expect(fixture.textExpansionPerformer.plans.count == 1)
    #expect(fixture.syntheticAdopter.requests.count == 1)
    #expect(fixture.applicator.requests.isEmpty)
    #expect(fixture.coordinator.status == .observing)
    #expect(fixture.store.statistics().correctionsApplied == 1)
    #expect(
      fixture.coordinator.diagnostics.snapshot.correctionsApplied == 1
    )
  }

  @Test("A pre-dispatch receipt is adopted without a second synthetic write")
  func adoptsVerifiedPreDispatchReceipt() async throws {
    let fixture = try Fixture(
      textExpansionEnabled: true,
      textExpansionVerificationDelays: [.milliseconds(1)]
    )
    fixture.reader.result = .ready(snapshot(text: "", caret: 0))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .ready(snapshot(text: "the ", caret: 4))
    fixture.inputMonitor.emitPreDispatchMutation(
      plan: BearTextExpansionPlan(
        original: "teh",
        replacement: "the",
        boundary: " ",
        deleteCount: 3,
        insertedText: "the "
      ),
      authorizedSnapshot: snapshot(text: "teh", caret: 3)
    )
    fixture.monitor.emit(.valueChanged)

    #expect(
      await waitUntil {
        fixture.tracker.applications.count == 1
      }
    )
    #expect(fixture.textExpansionPerformer.plans.isEmpty)
    #expect(fixture.syntheticAdopter.requests.count == 1)
    #expect(fixture.applicator.requests.isEmpty)
    #expect(fixture.coordinator.status == .observing)
    #expect(fixture.store.statistics().correctionsApplied == 1)
  }

  @Test("A learned suppression never authorizes the pre-dispatch tap")
  func learnedSuppressionDeauthorizesPreDispatchTap() throws {
    let fixture = try Fixture(textExpansionEnabled: true)
    let proposal = try #require(fixture.engine.proposal(for: "teh"))
    fixture.store.recordReverted(proposal)
    fixture.reader.result = .ready(snapshot(text: "", caret: 0))

    fixture.coordinator.setEnabled(true)

    #expect(
      !fixture.inputMonitor.authorizedSnapshots.contains(where: { snapshot in
        snapshot != nil
      })
    )
    #expect(!fixture.inputMonitor.authorizedSnapshots.isEmpty)
  }

  @Test("A settled ordinary edit rearms pre-dispatch from fresh AX state")
  func settledOrdinaryEditRearmsPreDispatch() async throws {
    let fixture = try Fixture(textExpansionEnabled: true)
    fixture.reader.result = .ready(snapshot(text: "the ", caret: 4))
    fixture.coordinator.setEnabled(true)
    let authorizationsBeforeEdit =
      fixture.inputMonitor.authorizedSnapshots.count

    fixture.inputMonitor.emitOther()
    let freshSnapshot = snapshot(text: "the \n", caret: 5)
    fixture.reader.result = .ready(freshSnapshot)
    fixture.monitor.emit(.valueChanged)

    #expect(
      await waitUntil {
        fixture.inputMonitor.authorizedSnapshots.count
          > authorizationsBeforeEdit
      }
    )
    let latestAuthorization = try #require(
      fixture.inputMonitor.authorizedSnapshots.last
    )
    #expect(latestAuthorization == freshSnapshot)
    #expect(fixture.coordinator.status == .observing)
  }

  @Test("Settled direct letters do not reset pre-dispatch authorization")
  func settledDirectLettersPreservePreDispatchAuthorization() async throws {
    let fixture = try Fixture(textExpansionEnabled: true)
    fixture.reader.result = .ready(snapshot(text: "the ", caret: 4))
    fixture.coordinator.setEnabled(true)
    let authorizationsBeforeLetter =
      fixture.inputMonitor.authorizedSnapshots.count
    let readsBeforeLetter = fixture.reader.readCount

    fixture.inputMonitor.emitText("t")
    fixture.reader.result = .ready(snapshot(text: "the t", caret: 5))
    fixture.monitor.emit(.valueChanged)

    #expect(
      await waitUntil {
        fixture.reader.readCount > readsBeforeLetter
      }
    )
    #expect(
      fixture.inputMonitor.authorizedSnapshots.count
        == authorizationsBeforeLetter
    )
    #expect(fixture.coordinator.status == .observing)
  }

  @Test("The deferred AX lane explicitly disarms pre-dispatch")
  func deferredAXLaneDisarmsPreDispatch() async throws {
    let fixture = try Fixture(
      deferredCorrectionIdleDelay: .milliseconds(80),
      textExpansionEnabled: true
    )
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)

    #expect(
      await waitUntil {
        fixture.coordinator.diagnostics.snapshot.correctionsDeferred == 1
      }
    )
    let authorizationWhileDeferred = try #require(
      fixture.inputMonitor.authorizedSnapshots.last
    )
    #expect(authorizationWhileDeferred == nil)

    #expect(
      await waitUntil {
        fixture.applicator.requests.count == 1
      }
    )
    #expect(
      await waitUntil {
        fixture.inputMonitor.authorizedSnapshots.last.flatMap { $0 } != nil
      }
    )
    let authorizationAfterRebaseline = try #require(
      fixture.inputMonitor.authorizedSnapshots.last
    )
    #expect(authorizationAfterRebaseline != nil)
  }

  @Test("An unrecognized pre-dispatch write opens the mutation circuit")
  func unrecognizedPreDispatchReceiptOpensCircuit() throws {
    let fixture = try Fixture(textExpansionEnabled: true)
    fixture.reader.result = .ready(snapshot(text: "", caret: 0))
    fixture.coordinator.setEnabled(true)
    let stopCountBeforeReceipt = fixture.inputMonitor.stopCount

    fixture.inputMonitor.emitPreDispatchMutation(
      plan: BearTextExpansionPlan(
        original: "teh",
        replacement: "ten",
        boundary: " ",
        deleteCount: 3,
        insertedText: "ten "
      ),
      authorizedSnapshot: snapshot(text: "teh", caret: 3)
    )

    #expect(fixture.coordinator.status == .pausedAfterIndeterminateWrite)
    #expect(fixture.inputMonitor.stopCount == stopCountBeforeReceipt + 1)
    #expect(fixture.textExpansionPerformer.plans.isEmpty)
    #expect(fixture.syntheticAdopter.requests.isEmpty)
    #expect(fixture.applicator.requests.isEmpty)
  }

  @Test("An ambiguous emitted text expansion opens the mutation circuit")
  func textExpansionVerificationFailureOpensCircuit() async throws {
    let fixture = try Fixture(
      textExpansionEnabled: true,
      textExpansionVerificationDelays: [.milliseconds(1)]
    )
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.inputMonitor.emitText("t")
    fixture.inputMonitor.emitText("e")
    fixture.inputMonitor.emitText("h")
    fixture.reader.result = .ready(snapshot(text: "ten ", caret: 4))
    fixture.inputMonitor.emitBoundary()

    #expect(
      await waitUntil {
        fixture.coordinator.status == .pausedAfterIndeterminateWrite
      }
    )
    #expect(fixture.textExpansionPerformer.plans.count == 1)
    #expect(fixture.syntheticAdopter.requests.isEmpty)
    #expect(fixture.applicator.requests.isEmpty)
    #expect(fixture.tracker.applications.isEmpty)
    #expect(fixture.store.statistics().correctionsApplied == 0)
  }

  @Test("Continued typing can be adopted behind the synthetic correction")
  func textExpansionAllowsAppendOnlyTyping() async throws {
    let fixture = try Fixture(
      textExpansionEnabled: true,
      textExpansionVerificationDelays: [.milliseconds(5)]
    )
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.inputMonitor.emitText("t")
    fixture.inputMonitor.emitText("e")
    fixture.inputMonitor.emitText("h")
    fixture.inputMonitor.emitBoundary()
    fixture.reader.result = .ready(snapshot(text: "the x", caret: 5))
    fixture.inputMonitor.emitText("x")

    #expect(
      await waitUntil {
        fixture.tracker.applications.count == 1
      }
    )
    #expect(fixture.coordinator.status == .observing)
    #expect(fixture.syntheticAdopter.requests.count == 1)
    #expect(
      fixture.syntheticAdopter.requests.first?.replacementRange
        == AccessibilityTextRange(location: 0, length: 3)
    )
  }

  @Test("Secure Input keeps the experimental path from emitting")
  func secureInputFallsBackWithoutSyntheticWrite() async throws {
    let physicalIdle = TestPhysicalIdleDuration(.zero)
    let fixture = try Fixture(
      physicalInputIdleDuration: { physicalIdle.value },
      textExpansionEnabled: true,
      secureInputIsActive: true
    )
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.inputMonitor.emitText("t")
    fixture.inputMonitor.emitText("e")
    fixture.inputMonitor.emitText("h")
    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)

    #expect(
      await waitUntil {
        fixture.coordinator.diagnostics.snapshot.correctionsDeferred == 1
      }
    )
    #expect(fixture.applicator.requests.isEmpty)
    physicalIdle.value = .seconds(60)
    #expect(
      await waitUntil {
        fixture.applicator.requests.count == 1
      }
    )
    #expect(fixture.textExpansionPerformer.plans.isEmpty)
    #expect(fixture.syntheticAdopter.requests.isEmpty)
    #expect(fixture.tracker.applications.count == 1)
  }

  @Test("Punctuation and newline keys authorize only their exact transition")
  func correctsPunctuationBoundaries() async throws {
    for boundary in [".", "?", "\n"] {
      let fixture = try Fixture()
      fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
      fixture.coordinator.setEnabled(true)

      fixture.reader.result = .ready(
        snapshot(text: "teh\(boundary)", caret: 4)
      )
      fixture.inputMonitor.emitBoundary(boundary)
      fixture.monitor.emit(.valueChanged)

      #expect(
        await waitUntil {
          fixture.applicator.requests.count == 1
        }
      )
      #expect(
        fixture.applicator.requests.first?.range
          == AccessibilityTextRange(location: 0, length: 3)
      )
    }
  }

  @Test("Only the validated Bear and macOS versions are supported")
  func validatesSupportedEnvironment() {
    let policy = BearSupportPolicy.current
    #expect(
      policy.evaluate(
        bearVersion: "2.8.1",
        operatingSystemVersion: OperatingSystemVersion(
          majorVersion: 27,
          minorVersion: 0,
          patchVersion: 1
        )
      ) == .supported
    )
    #expect(
      policy.evaluate(
        bearVersion: "2.9.1",
        operatingSystemVersion: OperatingSystemVersion(
          majorVersion: 27,
          minorVersion: 0,
          patchVersion: 1
        )
      ) == .supported
    )
    #expect(
      policy.evaluate(
        bearVersion: "2.8.2",
        operatingSystemVersion: OperatingSystemVersion(
          majorVersion: 27,
          minorVersion: 0,
          patchVersion: 0
        )
      ) == .unsupportedBearVersion(installed: "2.8.2")
    )
    #expect(
      policy.evaluate(
        bearVersion: "2.8.1",
        operatingSystemVersion: OperatingSystemVersion(
          majorVersion: 27,
          minorVersion: 1,
          patchVersion: 0
        )
      ) == .unsupportedMacOSVersion(installed: "27.1.0")
    )
  }

  @Test("Unsupported environments never attach mutation observers")
  func blocksUnsupportedEnvironment() throws {
    let fixture = try Fixture(
      environmentSupport: .unsupportedBearVersion(installed: "2.8.2")
    )
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))

    fixture.coordinator.setEnabled(true)

    #expect(
      fixture.coordinator.status
        == .unsupportedBearVersion(installed: "2.8.2")
    )
    #expect(fixture.monitor.startCount == 0)
    #expect(fixture.inputMonitor.startCount == 0)
    #expect(fixture.coordinator.diagnostics.snapshot.refusals == 1)
  }

  @Test("Disabling stops observation and re-enabling starts fresh")
  func disablesAndReenablesObservation() throws {
    let fixture = try Fixture()
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)
    let monitorStopsAfterEnable = fixture.monitor.stopCount
    let inputStopsAfterEnable = fixture.inputMonitor.stopCount

    fixture.coordinator.setEnabled(false)

    #expect(fixture.coordinator.status == .disabled)
    #expect(fixture.monitor.stopCount == monitorStopsAfterEnable + 1)
    #expect(fixture.inputMonitor.stopCount == inputStopsAfterEnable + 1)
    #expect(fixture.tracker.stopCount == 1)

    fixture.coordinator.setEnabled(true)

    #expect(fixture.coordinator.status == .observing)
    #expect(fixture.monitor.startCount == 2)
    #expect(fixture.inputMonitor.startCount == 2)
  }

  @Test("Consecutive typed words create consecutive annotations")
  func correctsConsecutiveWords() async throws {
    let fixture = try Fixture()
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.tracker.applications.count == 1
      }
    )

    fixture.reader.result = .ready(snapshot(text: "teh teh", caret: 7))
    let readsBeforeIntermediateEdit = fixture.reader.readCount
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.reader.readCount >= readsBeforeIntermediateEdit + 1
      }
    )
    fixture.reader.result = .ready(snapshot(text: "teh teh ", caret: 8))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)

    #expect(
      await waitUntil {
        fixture.tracker.applications.count == 2
      }
    )
    #expect(
      fixture.applicator.requests.map(\.range) == [
        AccessibilityTextRange(location: 0, length: 3),
        AccessibilityTextRange(location: 4, length: 3),
      ])
    #expect(
      fixture.tracker.verifiedEdits == [
        BearAnnotationVerifiedEdit(
          replacedRange: AccessibilityTextRange(location: 0, length: 3),
          replacementLength: 3
        ),
        BearAnnotationVerifiedEdit(
          replacedRange: AccessibilityTextRange(location: 4, length: 3),
          replacementLength: 3
        ),
      ])
  }

  @Test("The next ordinary key does not erase a pending boundary")
  func preservesBoundaryWhileRapidTypingContinues() async throws {
    let fixture = try Fixture()
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.inputMonitor.emitOther()
    fixture.monitor.emit(.valueChanged)

    #expect(
      await waitUntil {
        fixture.applicator.requests.count == 1
      }
    )
    #expect(
      fixture.applicator.requests.first?.range
        == AccessibilityTextRange(location: 0, length: 3)
    )
  }

  @Test("Rapid typing defers correction until input becomes idle")
  func defersCorrectionDuringRapidTyping() async throws {
    let fixture = try Fixture(
      deferredCorrectionIdleDelay: .milliseconds(80)
    )
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.inputMonitor.emitOther()
    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)

    #expect(
      await waitUntil {
        fixture.coordinator.diagnostics.snapshot.correctionsDeferred == 1
      }
    )
    #expect(fixture.applicator.requests.isEmpty)
    #expect(
      fixture.coordinator.diagnostics.snapshot.lastOutcome
        == .rapidTypingDeferred
    )

    #expect(
      await waitUntil {
        fixture.applicator.requests.count == 1
      }
    )
    #expect(
      fixture.applicator.requests.first?.range
        == AccessibilityTextRange(location: 0, length: 3)
    )
    // The applied diagnostic is recorded after the write, so it trails the
    // applicator signal this test already waited on.
    #expect(
      await waitUntil {
        fixture.coordinator.diagnostics.snapshot.correctionsApplied == 1
      }
    )
  }

  @Test("The VoiceOver safety latch cancels a queued correction")
  func voiceOverSafetyPauseCancelsQueuedCorrection() async throws {
    let physicalIdle = TestPhysicalIdleDuration(.zero)
    let safetyPause = TestBoolean(false)
    let fixture = try Fixture(
      deferredCorrectionIdleDelay: .milliseconds(40),
      physicalInputIdleDuration: { physicalIdle.value },
      voiceOverSafetyPauseIsRequired: { safetyPause.value }
    )
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.coordinator.diagnostics.snapshot.correctionsDeferred == 1
      }
    )

    safetyPause.value = true
    physicalIdle.value = .seconds(60)
    #expect(
      await waitUntil {
        fixture.coordinator.status == .pausedForVoiceOver
      }
    )
    try? await Task.sleep(for: .milliseconds(80))

    #expect(fixture.applicator.requests.isEmpty)
  }

  @Test("A caret move and adjacent edit invalidate a deferred correction")
  func refusesDeferredCorrectionAfterContextDrift() async throws {
    let physicalIdle = TestPhysicalIdleDuration(.zero)
    let fixture = try Fixture(
      deferredCorrectionIdleDelay: .milliseconds(80),
      physicalInputIdleDuration: { physicalIdle.value }
    )
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.coordinator.diagnostics.snapshot.correctionsDeferred == 1
      }
    )

    fixture.inputMonitor.emitOther()
    fixture.inputMonitor.emitOther()
    fixture.reader.result = .ready(
      snapshot(text: "tehx ", caret: 4, documentLength: 5)
    )
    let readsBeforeSelectionChange = fixture.reader.readCount
    fixture.monitor.emit(.selectionChanged)
    #expect(
      await waitUntil {
        fixture.reader.readCount > readsBeforeSelectionChange
      }
    )
    physicalIdle.value = .seconds(60)
    #expect(
      await waitUntil {
        fixture.coordinator.diagnostics.snapshot.safeSkips >= 1
      }
    )
    #expect(fixture.applicator.requests.isEmpty)
    #expect(
      fixture.coordinator.diagnostics.snapshot.lastOutcome == .contextChanged
    )
  }

  @Test("Append-only typing retains a deferred correction authorization")
  func permitsDeferredCorrectionAfterAppendOnlyTyping() {
    let authorized = snapshot(
      text: "prefix teh ",
      caret: 11,
      documentLength: 16,
      trailing: " tail"
    )
    let appended = snapshot(
      text: "prefix teh next ",
      caret: 16,
      documentLength: 21,
      trailing: " tail"
    )

    #expect(
      BearDeferredTypingTransition.preservesAppendOnlyContext(
        from: authorized,
        to: appended
      )
    )
  }

  @Test("A queued physical key postpones AX mutation before its callback arrives")
  func physicalInputIdleGatePreventsPrematureMutation() async throws {
    let physicalIdle = TestPhysicalIdleDuration(.milliseconds(5))
    let fixture = try Fixture(
      deferredCorrectionIdleDelay: .milliseconds(40),
      physicalInputIdleDuration: { physicalIdle.value }
    )
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.coordinator.diagnostics.snapshot.correctionsDeferred == 1
      }
    )

    try? await Task.sleep(for: .milliseconds(70))
    #expect(fixture.applicator.requests.isEmpty)

    physicalIdle.value = .seconds(1)
    #expect(
      await waitUntil {
        fixture.applicator.requests.count == 1
      }
    )
    #expect(
      fixture.applicator.requests.first?.range
        == AccessibilityTextRange(location: 0, length: 3)
    )
  }

  @Test("Post-burst catch-up applies queued corrections from end to beginning")
  func catchesUpInReverseDocumentOrder() async throws {
    let physicalIdle = TestPhysicalIdleDuration(.zero)
    let fixture = try Fixture(
      deferredCorrectionIdleDelay: .milliseconds(150),
      physicalInputIdleDuration: { physicalIdle.value }
    )
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.inputMonitor.emitOther()
    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.coordinator.diagnostics.snapshot.correctionsDeferred == 1
      }
    )

    fixture.inputMonitor.emitOther()
    fixture.reader.result = .ready(snapshot(text: "teh teh", caret: 7))
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.reader.readCount >= 3
      }
    )

    fixture.inputMonitor.emitOther()
    fixture.reader.result = .ready(snapshot(text: "teh teh ", caret: 8))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.coordinator.diagnostics.snapshot.correctionsDeferred == 2
      }
    )
    #expect(fixture.applicator.requests.isEmpty)

    // Release the injected physical-idle gate only after both corrections are
    // queued. This keeps parallel test load from racing the production timer.
    physicalIdle.value = .seconds(60)
    #expect(
      await waitUntil {
        fixture.applicator.requests.count == 2
      }
    )
    #expect(
      fixture.applicator.requests.map(\.range) == [
        AccessibilityTextRange(location: 4, length: 3),
        AccessibilityTextRange(location: 0, length: 3),
      ])
    // The coordinator records the applied diagnostic after the overlay work
    // that follows each write, so the counter trails the applicator request.
    #expect(
      await waitUntil {
        fixture.coordinator.diagnostics.snapshot.correctionsApplied == 2
      }
    )
  }

  @Test("Post-burst scan recovers boundaries coalesced by Accessibility")
  func catchesUpCoalescedRapidBoundaries() async throws {
    let physicalIdle = TestPhysicalIdleDuration(.zero)
    let fixture = try Fixture(
      deferredCorrectionIdleDelay: .milliseconds(80),
      physicalInputIdleDuration: { physicalIdle.value }
    )
    fixture.reader.result = .ready(snapshot(text: "te", caret: 2))
    fixture.coordinator.setEnabled(true)

    fixture.inputMonitor.emitOther()
    fixture.reader.result = .ready(snapshot(text: "teh t", caret: 5))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.coordinator.diagnostics.snapshot.valueChanges == 1
      }
    )

    fixture.inputMonitor.emitOther()
    fixture.reader.result = .ready(snapshot(text: "teh teh ", caret: 8))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.coordinator.diagnostics.snapshot.valueChanges == 2
      }
    )

    // Full-suite contention may delay this test past the logical idle timer.
    // Model the production physical-input gate so no write can begin until the
    // complete burst has reached the coordinator, regardless of main-actor
    // scheduling latency.
    physicalIdle.value = .seconds(1)

    #expect(
      await waitUntil {
        fixture.applicator.requests.count == 2
      }
    )
    #expect(
      fixture.applicator.requests.map(\.range) == [
        AccessibilityTextRange(location: 4, length: 3),
        AccessibilityTextRange(location: 0, length: 3),
      ])
    #expect(fixture.coordinator.diagnostics.snapshot.correctionsDeferred == 2)
    #expect(fixture.coordinator.diagnostics.snapshot.safeSkips == 0)
  }

  @Test("Post-burst scan excludes text before rapid typing began")
  func catchUpScanIsBoundedToRapidTyping() async throws {
    let fixture = try Fixture(
      deferredCorrectionIdleDelay: .milliseconds(60)
    )
    fixture.reader.result = .ready(snapshot(text: "teh te", caret: 6))
    fixture.coordinator.setEnabled(true)

    fixture.inputMonitor.emitOther()
    fixture.reader.result = .ready(snapshot(text: "teh teh ", caret: 8))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)

    #expect(
      await waitUntil {
        fixture.applicator.requests.count == 1
      }
    )
    #expect(
      fixture.applicator.requests.first?.range
        == AccessibilityTextRange(location: 4, length: 3)
    )
  }

  @Test("Post-burst scan fails closed when the typed start was never observed")
  func catchUpRequiresObservedBurstStart() async throws {
    let fixture = try Fixture(
      deferredCorrectionIdleDelay: .milliseconds(50)
    )
    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.coordinator.setEnabled(true)

    fixture.inputMonitor.emitOther()
    fixture.reader.result = .ready(snapshot(text: "teh teh ", caret: 8))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)

    #expect(
      await waitUntil {
        fixture.coordinator.diagnostics.snapshot.safeSkips == 1
      }
    )
    try await Task.sleep(for: .milliseconds(80))
    #expect(fixture.applicator.requests.isEmpty)
    #expect(
      fixture.coordinator.diagnostics.snapshot.lastOutcome == .contextChanged
    )
  }

  @Test("New input during the idle scan postpones every queued write")
  func inputDuringScanReschedulesCatchUp() async throws {
    let fixture = try Fixture(
      deferredCorrectionIdleDelay: .milliseconds(100)
    )
    fixture.reader.result = .ready(snapshot(text: "te", caret: 2))
    fixture.coordinator.setEnabled(true)

    var scanWasInterrupted = false
    fixture.engine.onProposal = {
      scanWasInterrupted = true
      fixture.inputMonitor.emitOther()
    }
    fixture.inputMonitor.emitOther()
    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)

    #expect(
      await waitUntil {
        scanWasInterrupted
      }
    )
    #expect(fixture.applicator.requests.isEmpty)
    #expect(
      await waitUntil {
        fixture.applicator.requests.count == 1
      }
    )
  }

  @Test("Changing focused editors cancels queued rapid corrections")
  func focusChangeCancelsDeferredCorrections() async throws {
    let fixture = try Fixture(
      deferredCorrectionIdleDelay: .milliseconds(100)
    )
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.inputMonitor.emitOther()
    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.coordinator.diagnostics.snapshot.correctionsDeferred == 1
      }
    )

    fixture.monitor.emit(.focusedElementChanged)
    #expect(
      await waitUntil {
        fixture.monitor.startCount == 2
      }
    )
    try await Task.sleep(for: .milliseconds(150))

    #expect(fixture.applicator.requests.isEmpty)
  }

  @Test("Idle catch-up recovers a completed word before a coalesced next character")
  func recoversBoundaryCoalescedWithRapidTyping() async throws {
    let fixture = try Fixture()
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .ready(snapshot(text: "teh t", caret: 5))
    fixture.inputMonitor.emitBoundary()
    fixture.inputMonitor.emitOther()
    fixture.monitor.emit(.valueChanged)

    #expect(
      await waitUntil {
        fixture.applicator.requests.count == 1
          && fixture.coordinator.diagnostics.snapshot.lastOutcome == .applied
      }
    )
    #expect(
      fixture.applicator.requests.map(\.range) == [
        AccessibilityTextRange(location: 0, length: 3)
      ])
    #expect(fixture.coordinator.diagnostics.snapshot.lastOutcome == .applied)
  }

  @Test("Later Bear notifications do not postpone an armed boundary")
  func preservesArmedBoundaryDeadlineDuringRapidTyping() async throws {
    let fixture = try Fixture(settleDelay: .milliseconds(100))
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)
    try await Task.sleep(for: .milliseconds(70))
    fixture.monitor.emit(.selectionChanged)

    #expect(
      await waitUntil(timeout: .milliseconds(60)) {
        fixture.applicator.requests.count == 1
      }
    )
  }

  @Test("A pasted or coalesced insertion is ignored")
  func ignoresBulkInsertion() async throws {
    let fixture = try Fixture()
    fixture.reader.result = .ready(snapshot(text: "", caret: 0))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.reader.readCount >= 2
      }
    )

    #expect(fixture.applicator.requests.isEmpty)
    #expect(fixture.tracker.applications.isEmpty)
    #expect(
      await waitUntil {
        fixture.coordinator.diagnostics.snapshot.safeSkips == 1
      }
    )
    #expect(
      fixture.coordinator.diagnostics.snapshot.lastOutcome == .contextChanged
    )
  }

  @Test("A boundary inserted without a matching keystroke is ignored")
  func ignoresNonKeyboardBoundary() async throws {
    let fixture = try Fixture()
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.reader.readCount >= 2
      }
    )

    #expect(fixture.applicator.requests.isEmpty)
    #expect(
      await waitUntil {
        fixture.coordinator.diagnostics.snapshot.safeSkips == 1
      }
    )
    #expect(
      fixture.coordinator.diagnostics.snapshot.lastOutcome
        == .unarmedValueChange
    )
  }

  @Test("A stale completion key cannot authorize a later value change")
  func ignoresStaleBoundaryInput() async throws {
    let fixture = try Fixture(maximumBoundaryPairingDelay: .zero)
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.reader.readCount >= 2
      }
    )

    #expect(fixture.applicator.requests.isEmpty)
    #expect(fixture.tracker.applications.isEmpty)
    #expect(
      await waitUntil {
        fixture.coordinator.diagnostics.snapshot.safeSkips == 1
      }
    )
    #expect(
      fixture.coordinator.diagnostics.snapshot.lastOutcome
        == .staleBoundaryInput
    )
  }

  @Test("Undo or Redo clears an armed completion boundary")
  func undoRedoDisarmsBoundary() async throws {
    let fixture = try Fixture()
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.inputMonitor.emitUndoOrRedo()
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.reader.readCount >= 2
      }
    )

    #expect(fixture.applicator.requests.isEmpty)
    #expect(fixture.tracker.applications.isEmpty)
  }

  @Test("A composition commit that changes text is ignored")
  func ignoresCompositionCommit() async throws {
    let fixture = try Fixture()
    fixture.reader.result = .ready(snapshot(text: "te", caret: 2))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.reader.readCount >= 2
      }
    )

    #expect(fixture.applicator.requests.isEmpty)
    #expect(fixture.tracker.applications.isEmpty)
  }

  @Test("A selection pauses observation without applying a correction")
  func pausesForSelection() async throws {
    let fixture = try Fixture()
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .selectionActive
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.coordinator.status == .pausedForSelection
      }
    )

    #expect(fixture.coordinator.status == .pausedForSelection)
    #expect(fixture.applicator.requests.isEmpty)
  }

  @Test("Collapsing a selection establishes a fresh typing baseline")
  func resumesAfterSelection() async throws {
    let fixture = try Fixture()
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .selectionActive
    fixture.monitor.emit(.selectionChanged)
    #expect(
      await waitUntil {
        fixture.coordinator.status == .pausedForSelection
      }
    )

    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.monitor.emit(.selectionChanged)
    #expect(
      await waitUntil {
        fixture.coordinator.status == .observing
      }
    )

    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.applicator.requests.count == 1
      }
    )
  }

  @Test("Changing focused editors disarms an in-flight boundary")
  func focusChangeDisarmsBoundary() async throws {
    let fixture = try Fixture()
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.focusedElementChanged)
    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    #expect(
      await waitUntil {
        fixture.monitor.startCount == 2
      }
    )

    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        fixture.reader.readCount >= 3
      }
    )

    #expect(fixture.applicator.requests.isEmpty)
    #expect(
      fixture.coordinator.diagnostics.snapshot.lastOutcome
        == .unarmedValueChange
    )
  }

  @Test("A learned Change Back suppresses the next matching typo")
  func learnsChangeBack() async throws {
    let fixture = try Fixture()
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)
    #expect(
      await waitUntil {
        !fixture.tracker.applications.isEmpty
      }
    )
    fixture.tracker.resolve(.changedBack)

    #expect(
      fixture.store.preference(for: "teh", language: "en_US")
        == .suppressed
    )
    #expect(fixture.engine.responses == [.reverted])
    #expect(
      fixture.coordinator.diagnostics.snapshot.interactionLatencySampleCount
        == 1
    )
    #expect(
      fixture.coordinator.diagnostics.snapshot
        .medianInteractionLatencyMilliseconds == 42
    )
  }

  @Test("Observation retries while Bear's focused editor is attaching")
  func retriesObserverAttachment() async throws {
    let fixture = try Fixture()
    fixture.monitor.startResults = [false, true]
    fixture.reader.result = .focusedEditorUnavailable

    fixture.coordinator.setEnabled(true)
    fixture.reader.result = .ready(snapshot(text: "", caret: 0))

    #expect(
      await waitUntil {
        fixture.monitor.startCount == 2
          && fixture.inputMonitor.startCount == 1
      }
    )
    #expect(fixture.coordinator.status == .observing)
  }

  @Test("Input monitoring failure is explicit and recovers on activation")
  func recoversInputMonitoring() async throws {
    let fixture = try Fixture()
    fixture.inputMonitor.startResults = [false, true]
    fixture.reader.result = .ready(snapshot(text: "", caret: 0))

    fixture.coordinator.setEnabled(true)

    #expect(fixture.coordinator.status == .inputMonitoringUnavailable)
    #expect(fixture.monitor.startCount == 1)
    #expect(fixture.inputMonitor.startCount == 1)
    #expect(fixture.coordinator.diagnostics.snapshot.refusals == 1)
    #expect(
      fixture.coordinator.diagnostics.snapshot.lastOutcome
        == .inputMonitoringUnavailable
    )

    fixture.workspaceNotificationCenter.post(
      name: NSWorkspace.didActivateApplicationNotification,
      object: nil
    )

    #expect(
      await waitUntil {
        fixture.inputMonitor.startCount == 2
          && fixture.coordinator.status == .observing
      }
    )
  }

  @Test("An unreconciled post-write result opens the mutation circuit")
  func pausesAfterIndeterminateWrite() async throws {
    let fixture = try Fixture()
    let correction = Correction(original: "teh", replacement: "the")
    fixture.applicator.setNextApplication(
      BearCorrectionApplication(
        report: BearExactRangeReplacementReport(
          status: .verificationFailed,
          writeOccurred: true,
          targetRange: AccessibilityTextRange(location: 0, length: 3),
          replacementRange: AccessibilityTextRange(location: 0, length: 3),
          selectionAfter: AccessibilityTextRange(location: 4, length: 0)
        ),
        correction: correction,
        correctionRecord: nil,
        correctionAnchor: nil
      )
    )
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)

    #expect(
      await waitUntil {
        fixture.coordinator.status == .pausedAfterIndeterminateWrite
      }
    )
    #expect(
      fixture.coordinator.diagnostics.snapshot.lastOutcome
        == .postWriteReconciliationFailed
    )
    #expect(fixture.tracker.applications.isEmpty)
  }

  @Test("A VoiceOver safety latch pauses before any Accessibility write")
  func pausesBeforeWritingWhileVoiceOverIsActive() async throws {
    let fixture = try Fixture(
      voiceOverSafetyPauseIsRequired: { true }
    )
    fixture.reader.result = .ready(snapshot(text: "teh", caret: 3))
    fixture.coordinator.setEnabled(true)

    #expect(fixture.coordinator.status == .pausedForVoiceOver)

    fixture.reader.result = .ready(snapshot(text: "teh ", caret: 4))
    fixture.inputMonitor.emitBoundary()
    fixture.monitor.emit(.valueChanged)
    try? await Task.sleep(for: .milliseconds(50))

    #expect(fixture.applicator.requests.isEmpty)
    #expect(fixture.coordinator.status == .pausedForVoiceOver)
  }

  #if DEBUG
    @Test("Debug post-write fault injection alters only one successful write")
    func debugPostWriteFaultIsOneShot() {
      let base = TestCorrectionApplicator()
      let applicator = BearAutomaticCorrectionDebugFaults.correctionApplicator(
        base: base,
        environment: [
          BearAutomaticCorrectionDebugFaults.environmentKey:
            BearAutomaticCorrectionDebugFaults.unreconciledPostWriteValue
        ]
      )

      let first = applicator.apply(
        original: "teh",
        replacement: "the",
        at: AccessibilityTextRange(location: 0, length: 3)
      )
      let second = applicator.apply(
        original: "teh",
        replacement: "the",
        at: AccessibilityTextRange(location: 4, length: 3)
      )

      #expect(first.report.status == .verificationFailed)
      #expect(first.report.writeOccurred)
      #expect(first.correctionRecord == nil)
      #expect(first.correctionAnchor == nil)
      #expect(second.report.isVerifiedApplication)
      #expect(second.isReversibleApplication)
      #expect(base.requests.count == 2)
    }
  #endif

  @Test("Typing transition requires unchanged bounded context")
  func rejectsChangedContext() {
    let previous = snapshot(
      text: "before teh",
      caret: 10,
      trailing: " after"
    )
    let current = snapshot(
      text: "beforz teh ",
      caret: 11,
      documentLength: 17,
      trailing: " after"
    )

    #expect(
      BearTypingTransition.completedWord(
        from: previous,
        to: current,
        expectedBoundary: " "
      ) == nil
    )
  }

  @Test("The inserted boundary must match the observed key")
  func rejectsMismatchedBoundary() {
    let previous = snapshot(text: "teh", caret: 3)
    let current = snapshot(text: "teh.", caret: 4)

    #expect(
      BearTypingTransition.completedWord(
        from: previous,
        to: current,
        expectedBoundary: " "
      ) == nil
    )
    #expect(
      BearTypingTransition.completedWord(
        from: previous,
        to: current,
        expectedBoundary: "."
      ) != nil
    )
  }

  private func snapshot(
    text: String,
    caret: Int,
    documentLength: Int? = nil,
    trailing: String = ""
  ) -> BearTypingContextSnapshot {
    BearTypingContextSnapshot(
      leadingRange: AccessibilityTextRange(
        location: 0,
        length: text.utf16.count
      ),
      leadingText: text,
      trailingText: trailing,
      caretLocation: caret,
      documentLength: documentLength ?? caret + trailing.utf16.count
    )
  }

  private func waitUntil(
    timeout: Duration = .seconds(10),
    condition: () -> Bool
  ) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
      if condition() {
        return true
      }
      try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
  }
}

@MainActor
private final class TestPhysicalIdleDuration {
  var value: Duration

  init(_ value: Duration) {
    self.value = value
  }
}

@MainActor
private final class TestBoolean {
  var value: Bool

  init(_ value: Bool) {
    self.value = value
  }
}

@MainActor
private final class Fixture {
  let reader = TestTypingContextReader()
  let monitor = TestInvalidationMonitor()
  let engine = TestCorrectionEngine()
  let applicator = TestCorrectionApplicator()
  let tracker = TestAnnotationTracker()
  let inputMonitor = TestTypingInputMonitor()
  let textExpansionPerformer = TestCoordinatorTextExpansionPerformer()
  let syntheticAdopter = TestCoordinatorSyntheticAdopter()
  let store: CorrectionLearningStore
  let coordinator: BearAutomaticCorrectionCoordinator
  let workspaceNotificationCenter = NotificationCenter()
  private let directory: URL

  init(
    environmentSupport: BearEnvironmentSupport = .supported,
    settleDelay: Duration = .milliseconds(1),
    maximumBoundaryPairingDelay: Duration = .seconds(10),
    deferredCorrectionIdleDelay: Duration = .milliseconds(20),
    physicalInputIdleDuration: @escaping @MainActor @Sendable () -> Duration? = {
      .seconds(60)
    },
    textExpansionEnabled: Bool = false,
    voiceOverSafetyPauseIsRequired: @escaping
      @MainActor @Sendable () -> Bool = {
      false
    },
    secureInputIsActive: Bool = false,
    textExpansionVerificationDelays: [Duration] = [.milliseconds(1)]
  ) throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    store = CorrectionLearningStore(
      fileURL: directory.appendingPathComponent("learning.json")
    )
    coordinator = BearAutomaticCorrectionCoordinator(
      contextReader: reader,
      invalidationMonitor: monitor,
      correctionEngine: engine,
      correctionApplicator: applicator,
      textExpansionLane:
        textExpansionEnabled
        ? BearTextExpansionExperimentalLane(
          performer: textExpansionPerformer,
          adopter: syntheticAdopter
        )
        : nil,
      annotationTracker: tracker,
      typingInputMonitor: inputMonitor,
      environmentChecker: TestBearEnvironmentChecker(
        result: environmentSupport
      ),
      learningStore: store,
      frontmostBundleIdentifier: {
        BearAccessibilityProbe.bearBundleIdentifier
      },
      settleDelay: settleDelay,
      maximumBoundaryPairingDelay: maximumBoundaryPairingDelay,
      deferredCorrectionIdleDelay: deferredCorrectionIdleDelay,
      physicalInputIdleDuration: physicalInputIdleDuration,
      observationRestartDelay: .milliseconds(1),
      privateDiagnosticsEnabled: { false },
      textExpansionExperimentEnabled: { textExpansionEnabled },
      voiceOverSafetyPauseIsRequired: voiceOverSafetyPauseIsRequired,
      secureInputIsActive: { secureInputIsActive },
      textExpansionVerificationDelays: textExpansionVerificationDelays,
      workspaceNotificationCenter: workspaceNotificationCenter
    )
  }

  deinit {
    try? FileManager.default.removeItem(at: directory)
  }
}

private struct TestBearEnvironmentChecker: BearEnvironmentChecking {
  let result: BearEnvironmentSupport

  func support() -> BearEnvironmentSupport {
    result
  }
}

@MainActor
private final class TestTypingInputMonitor: BearTypingInputMonitoring {
  private var handler: (@MainActor @Sendable (BearTypingInputObservation) -> Void)?
  private(set) var startCount = 0
  private(set) var stopCount = 0
  var startResults: [Bool] = []
  private(set) var authorizedSnapshots: [BearTypingContextSnapshot?] = []

  func start(
    handler: @escaping @MainActor @Sendable (BearTypingInputObservation) -> Void
  ) -> Bool {
    startCount += 1
    if !startResults.isEmpty, !startResults.removeFirst() {
      self.handler = nil
      return false
    }
    self.handler = handler
    return true
  }

  func stop() {
    stopCount += 1
    handler = nil
  }

  func authorizePreDispatch(
    from snapshot: BearTypingContextSnapshot?
  ) {
    authorizedSnapshots.append(snapshot)
  }

  func emitBoundary(_ character: String = " ") {
    emit(
      .completionBoundary(character),
      token: .boundary(character)
    )
  }

  func emitUndoOrRedo() {
    emit(.undoOrRedo, token: .invalidate)
  }

  func emitOther() {
    emit(.other, token: .invalidate)
  }

  func emitText(_ text: String) {
    emit(.other, token: .text(text))
  }

  func emitPreDispatchMutation(
    plan: BearTextExpansionPlan,
    authorizedSnapshot: BearTypingContextSnapshot
  ) {
    let observedAt = ContinuousClock().now
    handler?(
      BearTypingInputObservation(
        intent: .completionBoundary(plan.boundary),
        textExpansionToken: .boundary(plan.boundary),
        observedAt: observedAt,
        preDispatchMutation: BearPreDispatchMutationReceipt(
          plan: plan,
          predictedAuthorizedSnapshot: authorizedSnapshot,
          boundaryObservedAt: observedAt,
          callbackDuration: .microseconds(50)
        )
      )
    )
  }

  private func emit(
    _ intent: BearTypingInputIntent,
    token: BearTextExpansionInputToken
  ) {
    handler?(
      BearTypingInputObservation(
        intent: intent,
        textExpansionToken: token,
        observedAt: ContinuousClock().now
      )
    )
  }
}

private final class TestTypingContextReader:
  BearTypingContextReading, @unchecked Sendable
{
  private let lock = NSLock()
  private var storedResult: BearTypingContextReadResult =
    .focusedEditorUnavailable
  private var storedReadCount = 0

  var result: BearTypingContextReadResult {
    get { lock.withLock { storedResult } }
    set { lock.withLock { storedResult = newValue } }
  }

  var readCount: Int {
    lock.withLock { storedReadCount }
  }

  func read() -> BearTypingContextReadResult {
    lock.withLock {
      storedReadCount += 1
      return storedResult
    }
  }
}

@MainActor
private final class TestInvalidationMonitor:
  BearAccessibilityInvalidationObserving
{
  var startResults: [Bool] = []
  private(set) var startCount = 0
  private(set) var stopCount = 0
  private var handler:
    (
      @MainActor @Sendable (
        BearAccessibilityInvalidationEvent
      ) -> Void
    )?

  func start(
    handler:
      @escaping @MainActor @Sendable (
        BearAccessibilityInvalidationEvent
      ) -> Void
  ) -> Bool {
    startCount += 1
    if !startResults.isEmpty, !startResults.removeFirst() {
      self.handler = nil
      return false
    }
    self.handler = handler
    return true
  }

  func stop() {
    stopCount += 1
    handler = nil
  }

  func emit(_ event: BearAccessibilityInvalidationEvent) {
    handler?(event)
  }
}

@MainActor
private final class TestCorrectionEngine: CorrectionEngine {
  var responses: [CorrectionUserResponse] = []
  var onProposal: (() -> Void)?

  func proposal(for word: String) -> CorrectionProposal? {
    let callback = onProposal
    onProposal = nil
    callback?()
    guard word == "teh" else {
      return nil
    }
    return CorrectionProposal(
      correction: Correction(original: "teh", replacement: "the"),
      alternatives: ["ten"],
      source: .appleSpelling,
      language: "en_US",
      lookupDuration: .zero
    )
  }

  func record(
    _ response: CorrectionUserResponse,
    for _: CorrectionProposal
  ) {
    responses.append(response)
  }
}

private final class TestCorrectionApplicator:
  BearCorrectionApplying, @unchecked Sendable
{
  struct Request: Equatable {
    let original: String
    let replacement: String
    let range: AccessibilityTextRange
  }

  private let lock = NSLock()
  private var storedRequests: [Request] = []
  private var nextApplication: BearCorrectionApplication?

  var requests: [Request] {
    lock.withLock { storedRequests }
  }

  func setNextApplication(_ application: BearCorrectionApplication) {
    lock.withLock {
      nextApplication = application
    }
  }

  func apply(
    original: String,
    replacement: String,
    at targetRange: AccessibilityTextRange
  ) -> BearCorrectionApplication {
    let override = lock.withLock { () -> BearCorrectionApplication? in
      storedRequests.append(
        Request(
          original: original,
          replacement: replacement,
          range: targetRange
        )
      )
      defer { nextApplication = nil }
      return nextApplication
    }
    if let override {
      return override
    }
    let replacementRange = AccessibilityTextRange(
      location: targetRange.location,
      length: replacement.utf16.count
    )
    let correction = Correction(
      original: original,
      replacement: replacement
    )
    return BearCorrectionApplication(
      report: BearExactRangeReplacementReport(
        status: .applied,
        writeOccurred: true,
        targetRange: targetRange,
        replacementRange: replacementRange,
        selectionBefore: AccessibilityTextRange(
          location: targetRange.location + targetRange.length + 1,
          length: 0
        ),
        selectionAfter: AccessibilityTextRange(
          location: targetRange.location + replacement.utf16.count + 1,
          length: 0
        ),
        surroundingContextVerified: true,
        caretRestored: true
      ),
      correction: correction,
      correctionRecord: CorrectionRecord(correction: correction),
      correctionAnchor: BearCorrectionAnchor(
        correctionRange: replacementRange,
        documentLength: replacement.utf16.count + 1,
        leadingContext: "",
        trailingContext: " "
      )
    )
  }
}

private final class TestCoordinatorTextExpansionPerformer:
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

private final class TestCoordinatorSyntheticAdopter:
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

@MainActor
private final class TestAnnotationTracker: BearAnnotationTracking {
  var applications: [BearCorrectionApplication] = []
  var userRecencies: [Date?] = []
  var verifiedEdits: [BearAnnotationVerifiedEdit] = []
  var invalidationEvents: [BearAccessibilityInvalidationEvent] = []
  private(set) var stopCount = 0
  private var onResolution:
    (
      @MainActor @Sendable (BearAnnotationResolution) -> Void
    )?
  private var onInteractionLatency: (@MainActor @Sendable (Duration) -> Void)?

  func handleInvalidation(_ event: BearAccessibilityInvalidationEvent) {
    invalidationEvents.append(event)
  }

  func recordVerifiedEdit(_ edit: BearAnnotationVerifiedEdit) {
    verifiedEdits.append(edit)
  }

  func trackWithResolution(
    _ application: BearCorrectionApplication,
    alternatives _: [String],
    userRecency: Date?,
    onFirstVisible: (@MainActor @Sendable () -> Void)?,
    onInteractionLatency: (
      @MainActor @Sendable (Duration) -> Void
    )?,
    onResolution: (
      @MainActor @Sendable (BearAnnotationResolution) -> Void
    )?,
    onFinished _: (@MainActor @Sendable () -> Void)?
  ) {
    applications.append(application)
    userRecencies.append(userRecency)
    onFirstVisible?()
    self.onInteractionLatency = onInteractionLatency
    self.onResolution = onResolution
  }

  func stop() {
    stopCount += 1
    applications = []
    userRecencies = []
    onInteractionLatency = nil
    onResolution = nil
  }

  func resolve(
    _ resolution: BearAnnotationResolution,
    interactionLatency: Duration = .milliseconds(42)
  ) {
    onInteractionLatency?(interactionLatency)
    onResolution?(resolution)
  }
}
