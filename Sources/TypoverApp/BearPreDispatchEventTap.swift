import AppKit
import CoreGraphics
import OSLog
import TypoverAccessibility
import TypoverBearAdapter

struct BearPreDispatchCorrectionRule: Equatable, Sendable {
  let original: String
  let replacement: String
}

enum BearPreDispatchPhysicalInput: Equatable, Sendable {
  case letter(String)
  case boundary(String)
  case invalidate
  case synthetic
}

struct BearPreDispatchMutationReceipt: Equatable, Sendable {
  let plan: BearTextExpansionPlan
  let predictedAuthorizedSnapshot: BearTypingContextSnapshot
  let boundaryObservedAt: ContinuousClock.Instant
  let callbackDuration: Duration
}

enum BearPreDispatchDecision: Equatable, Sendable {
  case passThrough
  case replace(
    plan: BearTextExpansionPlan,
    predictedAuthorizedSnapshot: BearTypingContextSnapshot
  )
}

enum BearPreDispatchEmissionStep: Equatable, Sendable {
  case deleteKeyDown
  case deleteKeyUp
  case replacementKeyDown(String)
  case replacementKeyUp
  case returnPhysicalBoundary
}

enum BearPreDispatchEmissionSequence {
  static func steps(for plan: BearTextExpansionPlan)
    -> [BearPreDispatchEmissionStep]
  {
    guard plan.deleteCount > 0, !plan.replacement.isEmpty else {
      return [.returnPhysicalBoundary]
    }
    var steps: [BearPreDispatchEmissionStep] = []
    steps.reserveCapacity(plan.deleteCount * 2 + 3)
    for _ in 0..<plan.deleteCount {
      steps.append(.deleteKeyDown)
      steps.append(.deleteKeyUp)
    }
    steps.append(.replacementKeyDown(plan.replacement))
    steps.append(.replacementKeyUp)
    steps.append(.returnPhysicalBoundary)
    return steps
  }
}

/// A deliberately small, deterministic model used by the ordering experiment.
/// It never reads Bear or invokes a correction engine. Instead, it advances a
/// previously verified bounded snapshot using only the physical events that it
/// passes through. Any event it cannot model invalidates the fast path.
struct BearPreDispatchCorrectionStateMachine: Sendable {
  private enum WordState: Equatable, Sendable {
    case atBoundary
    case word(String)
    case unknown
  }

  private let rules: [String: String]
  private var predictedSnapshot: BearTypingContextSnapshot?
  private var wordState: WordState = .unknown

  init(rules: [BearPreDispatchCorrectionRule]) {
    self.rules = Dictionary(
      uniqueKeysWithValues: rules.map { ($0.original, $0.replacement) }
    )
  }

  mutating func authorize(from snapshot: BearTypingContextSnapshot?) {
    guard let snapshot, Self.isInternallyConsistent(snapshot) else {
      invalidate()
      return
    }
    predictedSnapshot = snapshot
    if snapshot.caretLocation == 0 || Self.endsInBoundary(snapshot) {
      wordState = .atBoundary
    } else {
      // The first boundary will establish a safe word start. Never match a
      // suffix of text that existed before the event tap was authorized.
      wordState = .unknown
    }
  }

  mutating func consume(
    _ input: BearPreDispatchPhysicalInput
  ) -> BearPreDispatchDecision {
    switch input {
    case .synthetic:
      return .passThrough
    case .invalidate:
      invalidate()
      return .passThrough
    case .letter(let letter):
      guard
        letter.utf16.count == 1,
        letter.unicodeScalars.allSatisfy({ scalar in
          scalar.value >= 97 && scalar.value <= 122
        }),
        appendPassedThroughText(letter)
      else {
        invalidate()
        return .passThrough
      }
      switch wordState {
      case .atBoundary:
        wordState = .word(letter)
      case .word(let word):
        guard word.utf16.count < BearTextExpansionPlanner.maximumWordLength
        else {
          wordState = .unknown
          return .passThrough
        }
        wordState = .word(word + letter)
      case .unknown:
        break
      }
      return .passThrough
    case .boundary(let boundary):
      guard boundary == " " else {
        invalidate()
        return .passThrough
      }

      let completedWord: String?
      if case .word(let word) = wordState {
        completedWord = word
      } else {
        completedWord = nil
      }

      guard
        let completedWord,
        let replacement = rules[completedWord],
        replacement != completedWord,
        let authorized = predictedSnapshot,
        Self.snapshot(authorized, endsIn: completedWord)
      else {
        guard appendPassedThroughText(boundary) else {
          invalidate()
          return .passThrough
        }
        wordState = .atBoundary
        return .passThrough
      }

      let plan = BearTextExpansionPlan(
        original: completedWord,
        replacement: replacement,
        boundary: boundary,
        deleteCount: completedWord.utf16.count,
        insertedText: replacement + boundary
      )
      // One authorization owns at most one destructive transaction. The
      // coordinator reauthorizes from a fresh AX snapshot only after adoption
      // verifies the exact range. Under load this produces a safe miss instead
      // of allowing a second unverified write to race the first.
      invalidate()
      return .replace(
        plan: plan,
        predictedAuthorizedSnapshot: authorized
      )
    }
  }

  mutating func invalidate() {
    predictedSnapshot = nil
    wordState = .unknown
  }

  mutating func failOpenAfterUnemittedReplacement(
    _: BearTextExpansionPlan,
    authorizedSnapshot _: BearTypingContextSnapshot
  ) {
    invalidate()
  }

  private mutating func appendPassedThroughText(_ text: String) -> Bool {
    guard
      let snapshot = predictedSnapshot,
      Self.isInternallyConsistent(snapshot)
    else {
      return false
    }
    let length = text.utf16.count
    predictedSnapshot = BearTypingContextSnapshot(
      leadingRange: AccessibilityTextRange(
        location: snapshot.leadingRange.location,
        length: snapshot.leadingRange.length + length
      ),
      leadingText: snapshot.leadingText + text,
      trailingText: snapshot.trailingText,
      caretLocation: snapshot.caretLocation + length,
      documentLength: snapshot.documentLength + length
    )
    return true
  }

  private static func isInternallyConsistent(
    _ snapshot: BearTypingContextSnapshot
  ) -> Bool {
    snapshot.leadingText.utf16.count == snapshot.leadingRange.length
      && snapshot.caretLocation
        == snapshot.leadingRange.location + snapshot.leadingRange.length
      && snapshot.documentLength >= snapshot.caretLocation
  }

  private static func snapshot(
    _ snapshot: BearTypingContextSnapshot,
    endsIn text: String
  ) -> Bool {
    snapshot.leadingText.hasSuffix(text)
  }

  private static func endsInBoundary(
    _ snapshot: BearTypingContextSnapshot
  ) -> Bool {
    guard let scalar = snapshot.leadingText.unicodeScalars.last else {
      return snapshot.caretLocation == 0
    }
    return CharacterSet.whitespacesAndNewlines.contains(scalar)
      || CharacterSet(charactersIn: ".,!?;:…").contains(scalar)
  }
}

/// Main-actor adapter for the disabled-by-default ordering experiment. The
/// Core Graphics callback itself lives in a separate locked runtime because
/// the system invokes it on the tap's dedicated run-loop thread.
@MainActor
final class CGEventTapBearTypingInputMonitor: BearTypingInputMonitoring {
  private let runtime = BearPreDispatchEventTapRuntime()

  func start(
    handler: @escaping @MainActor @Sendable (
      BearTypingInputObservation
    ) -> Void
  ) -> Bool {
    runtime.start(handler: handler)
  }

  func authorizePreDispatch(
    from snapshot: BearTypingContextSnapshot?
  ) {
    runtime.authorizePreDispatch(from: snapshot)
  }

  func stop() {
    runtime.stop()
  }
}

/// Thread-safe active event-tap transport. The callback performs only
/// deterministic state transitions and event construction. Bear/AX
/// verification remains on the coordinator's main-actor async lane.
private final class BearPreDispatchEventTapRuntime: @unchecked Sendable {
  private static let deleteKeyCode: CGKeyCode = 51
  private static let spaceKeyCode: CGKeyCode = 49
  private static let startupTimeout: DispatchTimeInterval = .seconds(2)
  private static let letterByKeyCode: [CGKeyCode: String] = [
    0: "a", 11: "b", 8: "c", 2: "d", 14: "e", 3: "f", 5: "g",
    4: "h", 34: "i", 38: "j", 40: "k", 37: "l", 46: "m",
    45: "n", 31: "o", 35: "p", 12: "q", 15: "r", 1: "s",
    17: "t", 32: "u", 9: "v", 13: "w", 7: "x", 16: "y", 6: "z",
  ]

  private let lock = NSLock()
  private var stateMachine = BearPreDispatchCorrectionStateMachine(
    rules: [
      BearPreDispatchCorrectionRule(original: "teh", replacement: "the")
    ]
  )
  private var handler: (
    @MainActor @Sendable (BearTypingInputObservation) -> Void
  )?
  private var eventTap: CFMachPort?
  private var eventTapRunLoop: CFRunLoop?
  private var eventTapThread: Thread?
  private var isRunningRequested = false
  private let logger = Logger(
    subsystem: "com.malpern.typover",
    category: "BearPreDispatchEventTap"
  )

  func start(
    handler: @escaping @MainActor @Sendable (
      BearTypingInputObservation
    ) -> Void
  ) -> Bool {
    stop()
    lock.withLock {
      self.handler = handler
      stateMachine.invalidate()
      isRunningRequested = true
    }

    let startup = DispatchSemaphore(value: 0)
    let thread = Thread { [weak self] in
      self?.runEventTap(signaling: startup)
    }
    thread.name = "com.malpern.typover.bear-event-tap"
    thread.qualityOfService = .userInteractive
    lock.withLock {
      eventTapThread = thread
    }
    thread.start()

    guard startup.wait(timeout: .now() + Self.startupTimeout) == .success else {
      shutdown()
      return false
    }
    return lock.withLock { eventTap != nil }
  }

  func authorizePreDispatch(
    from snapshot: BearTypingContextSnapshot?
  ) {
    lock.withLock {
      stateMachine.authorize(from: snapshot)
    }
  }

  func stop() {
    shutdown()
  }

  private func shutdown() {
    let runtime = lock.withLock { () -> (CFMachPort?, CFRunLoop?) in
      handler = nil
      stateMachine.invalidate()
      isRunningRequested = false
      let runtime = (eventTap, eventTapRunLoop)
      eventTap = nil
      eventTapRunLoop = nil
      eventTapThread = nil
      return runtime
    }
    if let tap = runtime.0 {
      CGEvent.tapEnable(tap: tap, enable: false)
    }
    if let runLoop = runtime.1 {
      CFRunLoopStop(runLoop)
      CFRunLoopWakeUp(runLoop)
    }
  }

  private func runEventTap(
    signaling startup: DispatchSemaphore
  ) {
    let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
      | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
      | CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
      | CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: Self.eventTapCallback,
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      lock.withLock {
        eventTapThread = nil
      }
      startup.signal()
      return
    }
    let runLoop = CFRunLoopGetCurrent()
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    let shouldRun = lock.withLock {
      guard isRunningRequested else {
        return false
      }
      eventTap = tap
      eventTapRunLoop = runLoop
      return true
    }
    guard shouldRun else {
      startup.signal()
      return
    }
    CFRunLoopAddSource(runLoop, source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    startup.signal()
    CFRunLoopRun()
    CGEvent.tapEnable(tap: tap, enable: false)
    CFRunLoopRemoveSource(runLoop, source, .commonModes)
    lock.withLock {
      if eventTap === tap {
        eventTap = nil
        eventTapRunLoop = nil
        eventTapThread = nil
      }
    }
  }

  private static let eventTapCallback: CGEventTapCallBack = {
    proxy, type, event, userInfo in
    guard let userInfo else {
      return Unmanaged.passUnretained(event)
    }
    let monitor = Unmanaged<BearPreDispatchEventTapRuntime>
      .fromOpaque(userInfo)
      .takeUnretainedValue()
    return monitor.handleEvent(proxy: proxy, type: type, event: event)
  }

  private func handleEvent(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent
  ) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      handleTapDisable(type)
      return Unmanaged.passUnretained(event)
    }
    guard type == .keyDown else {
      lock.withLock { stateMachine.invalidate() }
      publishInvalidation(observedAt: ContinuousClock().now)
      return Unmanaged.passUnretained(event)
    }

    let observedAt = ContinuousClock().now
    let input = physicalInput(for: event)
    let decision = lock.withLock {
      stateMachine.consume(input)
    }
    let intent: BearTypingInputIntent
    let token: BearTextExpansionInputToken
    switch input {
    case .letter(let letter):
      intent = .other
      token = .text(letter)
    case .boundary(let boundary):
      intent = .completionBoundary(boundary)
      token = .boundary(boundary)
    case .invalidate, .synthetic:
      intent = .other
      token = .invalidate
    }

    var receipt: BearPreDispatchMutationReceipt?
    if case .replace(let plan, let authorizedSnapshot) = decision {
      if postReplacement(plan, at: proxy) {
        receipt = BearPreDispatchMutationReceipt(
          plan: plan,
          predictedAuthorizedSnapshot: authorizedSnapshot,
          boundaryObservedAt: observedAt,
          callbackDuration: observedAt.duration(to: ContinuousClock().now)
        )
      } else {
        lock.withLock {
          stateMachine.failOpenAfterUnemittedReplacement(
            plan,
            authorizedSnapshot: authorizedSnapshot
          )
        }
      }
    }

    if input != .synthetic {
      let observation = BearTypingInputObservation(
        intent: intent,
        textExpansionToken: token,
        observedAt: observedAt,
        preDispatchMutation: receipt
      )
      let callback = lock.withLock { handler }
      if let callback {
        Task { @MainActor in
          callback(observation)
        }
      }
    }
    return Unmanaged.passUnretained(event)
  }

  private func physicalInput(
    for event: CGEvent
  ) -> BearPreDispatchPhysicalInput {
    if event.getIntegerValueField(.eventSourceUserData)
      == CGEventBearTextExpansionPerformer.syntheticEventMarker
    {
      return .synthetic
    }
    let disallowedFlags: CGEventFlags = [
      .maskShift,
      .maskControl,
      .maskAlternate,
      .maskCommand,
      .maskSecondaryFn,
    ]
    guard
      event.flags.intersection(disallowedFlags).isEmpty,
      event.getIntegerValueField(.keyboardEventAutorepeat) == 0
    else {
      return .invalidate
    }
    let keyCode = CGKeyCode(
      event.getIntegerValueField(.keyboardEventKeycode)
    )
    if keyCode == Self.spaceKeyCode {
      return .boundary(" ")
    }
    if let letter = Self.letterByKeyCode[keyCode] {
      return .letter(letter)
    }
    return .invalidate
  }

  private func postReplacement(
    _ plan: BearTextExpansionPlan,
    at proxy: CGEventTapProxy
  ) -> Bool {
    guard
      plan.deleteCount == plan.original.utf16.count,
      plan.boundary == " ",
      plan.insertedText == plan.replacement + plan.boundary,
      let source = CGEventSource(stateID: .combinedSessionState)
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
      stringLength: plan.replacement.utf16.count,
      unicodeString: Array(plan.replacement.utf16)
    )
    events.append(insertionDown)
    events.append(insertionUp)

    for event in events {
      event.setIntegerValueField(
        .eventSourceUserData,
        value: CGEventBearTextExpansionPerformer.syntheticEventMarker
      )
      event.tapPostEvent(proxy)
    }
    return true
  }

  private func handleTapDisable(_ type: CGEventType) {
    let tap = lock.withLock { () -> CFMachPort? in
      stateMachine.invalidate()
      return eventTap
    }
    if let tap {
      CGEvent.tapEnable(tap: tap, enable: true)
    }
    publishInvalidation(observedAt: ContinuousClock().now)
    Task { @MainActor [logger] in
      logger.error(
        "Experimental Bear event tap failed open after disable type=\(type.rawValue, privacy: .public)"
      )
    }
  }

  private func publishInvalidation(
    observedAt: ContinuousClock.Instant
  ) {
    let callback = lock.withLock { handler }
    guard let callback else {
      return
    }
    Task { @MainActor in
      callback(
        BearTypingInputObservation(
          intent: .other,
          textExpansionToken: .invalidate,
          observedAt: observedAt
        )
      )
    }
  }
}
