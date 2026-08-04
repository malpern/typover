import AppKit
import ApplicationServices
import Foundation

public struct BearAccessibilityProbe: BearAccessibilityProbing, Sendable {
  public static let bearBundleIdentifier = "net.shinyfrog.bear"

  public init() {}

  public func run() -> BearAccessibilityReport {
    let trusted = AXIsProcessTrusted()
    let runningApplication = NSRunningApplication.runningApplications(
      withBundleIdentifier: Self.bearBundleIdentifier
    ).first
    let bearIsRunning = runningApplication != nil

    guard trusted else {
      return BearAccessibilityReport(
        status: .accessibilityPermissionRequired,
        accessibilityTrusted: false,
        bearIsRunning: bearIsRunning
      )
    }

    guard let runningApplication else {
      return BearAccessibilityReport(
        status: .bearNotRunning,
        accessibilityTrusted: true,
        bearIsRunning: false
      )
    }

    let applicationElement = AXUIElementCreateApplication(
      runningApplication.processIdentifier
    )
    configureBearAccessibilityMessagingTimeout(applicationElement)
    guard
      let focusedElement = copyElementAttribute(
        applicationElement,
        kAXFocusedUIElementAttribute as CFString
      )
    else {
      return BearAccessibilityReport(
        status: .focusedEditorUnavailable,
        accessibilityTrusted: true,
        bearIsRunning: true
      )
    }

    let editorElement = nearestTextArea(
      startingAt: focusedElement
    )
    if let editorElement {
      return inspect(
        editorElement,
        applicationElement: applicationElement,
        processIdentifier: runningApplication.processIdentifier,
        status: .ready,
        editorWasFocused: true,
        textAreaCandidateCount: 1
      )
    }

    let focusedWindow = copyElementAttribute(
      applicationElement,
      kAXFocusedWindowAttribute as CFString
    )
    let candidates = focusedWindow.map(textAreas(in:)) ?? []
    if candidates.count == 1, let inactiveEditor = candidates.first {
      return inspect(
        inactiveEditor,
        applicationElement: applicationElement,
        processIdentifier: runningApplication.processIdentifier,
        status: .editorAvailableButNotFocused,
        editorWasFocused: false,
        textAreaCandidateCount: candidates.count
      )
    }

    return BearAccessibilityReport(
      status: .focusedElementIsNotTextArea,
      accessibilityTrusted: true,
      bearIsRunning: true,
      editorRole: copyStringAttribute(
        focusedElement,
        kAXRoleAttribute as CFString
      ),
      editorIdentifier: copyStringAttribute(
        focusedElement,
        kAXIdentifierAttribute as CFString
      ),
      editorWasFocused: false,
      focusedWindowAvailable: focusedWindow != nil,
      textAreaCandidateCount: candidates.count
    )
  }

  private func inspect(
    _ editorElement: AXUIElement,
    applicationElement: AXUIElement,
    processIdentifier: pid_t,
    status: BearAccessibilityProbeStatus,
    editorWasFocused: Bool,
    textAreaCandidateCount: Int
  ) -> BearAccessibilityReport {
    let attributeNames = copyAttributeNames(editorElement)
    let parameterizedNames = copyParameterizedAttributeNames(editorElement)
    let selectedRange = copyRangeAttribute(
      editorElement,
      kAXSelectedTextRangeAttribute as CFString
    )
    let visibleRange = copyRangeAttribute(
      editorElement,
      kAXVisibleCharacterRangeAttribute as CFString
    )
    let characterCount = copyIntegerAttribute(
      editorElement,
      kAXNumberOfCharactersAttribute as CFString
    )
    let context = readBoundedContext(
      from: editorElement,
      selectedRange: selectedRange,
      characterCount: characterCount,
      parameterizedNames: parameterizedNames
    )
    let bounds = readRangeBounds(
      from: editorElement,
      selectedRange: selectedRange,
      characterCount: characterCount,
      parameterizedNames: parameterizedNames
    )

    return BearAccessibilityReport(
      status: status,
      accessibilityTrusted: true,
      bearIsRunning: true,
      editorRole: copyStringAttribute(
        editorElement,
        kAXRoleAttribute as CFString
      ),
      editorIdentifier: copyStringAttribute(
        editorElement,
        kAXIdentifierAttribute as CFString
      ),
      editorWasFocused: editorWasFocused,
      focusedWindowAvailable: true,
      textAreaCandidateCount: textAreaCandidateCount,
      selectedRange: selectedRange,
      visibleRange: visibleRange,
      characterCount: characterCount,
      boundedContextUTF16Length: context.length,
      boundedContextReader: context.reader,
      rangeBounds: bounds,
      attributes: requiredAttributeCapabilities(
        for: editorElement,
        names: attributeNames
      ),
      parameterizedAttributes: requiredParameterizedCapabilities(
        names: parameterizedNames
      ),
      notificationRegistrations: notificationRegistrationCapabilities(
        editorElement: editorElement,
        applicationElement: applicationElement,
        processIdentifier: processIdentifier
      )
    )
  }
}

extension BearAccessibilityProbe {
  func textAreas(in root: AXUIElement) -> [AXUIElement] {
    var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
    var textAreas: [AXUIElement] = []
    var visited = Set<ObjectIdentifier>()

    while !queue.isEmpty, visited.count < 500 {
      let next = queue.removeFirst()
      let identity = ObjectIdentifier(next.element)
      guard visited.insert(identity).inserted else {
        continue
      }

      let role = copyStringAttribute(
        next.element,
        kAXRoleAttribute as CFString
      )
      if role == (kAXTextAreaRole as String) {
        textAreas.append(next.element)
      }

      guard next.depth < 12 else {
        continue
      }
      // Bear's note list can expose thousands of rows. The editor is a
      // sibling of that table, never one of its descendants.
      if role == (kAXTableRole as String)
        || role == (kAXOutlineRole as String)
      {
        continue
      }
      let childAttributes: [CFString] = [
        kAXChildrenAttribute as CFString,
        kAXVisibleChildrenAttribute as CFString,
        "AXChildrenInNavigationOrder" as CFString,
        kAXContentsAttribute as CFString,
      ]
      for attribute in childAttributes {
        queue.append(
          contentsOf: copyElementArrayAttribute(
            next.element,
            attribute
          ).map { child in
            (child, next.depth + 1)
          }
        )
      }
    }

    return textAreas
  }

  func nearestTextArea(startingAt element: AXUIElement) -> AXUIElement? {
    var current: AXUIElement? = element
    for _ in 0..<8 {
      guard let candidate = current else {
        return nil
      }
      if copyStringAttribute(
        candidate,
        kAXRoleAttribute as CFString
      ) == (kAXTextAreaRole as String) {
        return candidate
      }
      current = copyElementAttribute(
        candidate,
        kAXParentAttribute as CFString
      )
    }
    return nil
  }

  fileprivate func requiredAttributeCapabilities(
    for element: AXUIElement,
    names: Set<String>
  ) -> [AccessibilityCapability] {
    [
      kAXSelectedTextAttribute,
      kAXSelectedTextRangeAttribute,
      kAXVisibleCharacterRangeAttribute,
      kAXNumberOfCharactersAttribute,
      kAXValueAttribute,
    ].map { name in
      let name = name as String
      guard names.contains(name) else {
        return AccessibilityCapability(name: name, state: .unsupported)
      }

      var isWritable = DarwinBoolean(false)
      let error = AXUIElementIsAttributeSettable(
        element,
        name as CFString,
        &isWritable
      )
      return AccessibilityCapability(
        name: name,
        state: error == .success ? .available : .failed,
        isWritable: error == .success ? isWritable.boolValue : nil,
        errorCode: error == .success ? nil : error.rawValue
      )
    }
  }

  fileprivate func requiredParameterizedCapabilities(
    names: Set<String>
  ) -> [AccessibilityCapability] {
    [
      kAXStringForRangeParameterizedAttribute,
      kAXAttributedStringForRangeParameterizedAttribute,
      kAXBoundsForRangeParameterizedAttribute,
    ].map { name in
      let name = name as String
      return AccessibilityCapability(
        name: name,
        state: names.contains(name) ? .available : .unsupported
      )
    }
  }

  fileprivate func readBoundedContext(
    from element: AXUIElement,
    selectedRange: AccessibilityTextRange?,
    characterCount: Int?,
    parameterizedNames: Set<String>
  ) -> (length: Int?, reader: String?) {
    guard
      let selectedRange,
      let characterCount,
      let queryRange = boundedRange(
        around: selectedRange.location,
        characterCount: characterCount
      )
    else {
      return (nil, nil)
    }

    if parameterizedNames.contains(
      kAXStringForRangeParameterizedAttribute as String
    ),
      let value = copyParameterizedValue(
        from: element,
        name: kAXStringForRangeParameterizedAttribute as CFString,
        range: queryRange
      ) as? String
    {
      // Reduce the scoped value to a count before it can leave this function.
      return (value.utf16.count, "AXStringForRange")
    }

    if parameterizedNames.contains(
      kAXAttributedStringForRangeParameterizedAttribute as String
    ),
      let value = copyParameterizedValue(
        from: element,
        name: kAXAttributedStringForRangeParameterizedAttribute as CFString,
        range: queryRange
      ) as? NSAttributedString
    {
      return (value.string.utf16.count, "AXAttributedStringForRange")
    }

    return (nil, nil)
  }

  fileprivate func readRangeBounds(
    from element: AXUIElement,
    selectedRange: AccessibilityTextRange?,
    characterCount: Int?,
    parameterizedNames: Set<String>
  ) -> AccessibilityBounds? {
    guard
      parameterizedNames.contains(
        kAXBoundsForRangeParameterizedAttribute as String
      ),
      let selectedRange,
      let characterCount
    else {
      return nil
    }

    let length = characterCount > selectedRange.location ? 1 : 0
    let range = AccessibilityTextRange(
      location: selectedRange.location,
      length: length
    )
    guard
      let rawValue = copyParameterizedValue(
        from: element,
        name: kAXBoundsForRangeParameterizedAttribute as CFString,
        range: range
      ),
      CFGetTypeID(rawValue) == AXValueGetTypeID()
    else {
      return nil
    }
    let value = unsafeDowncast(rawValue, to: AXValue.self)
    guard AXValueGetType(value) == .cgRect else {
      return nil
    }

    var rect = CGRect.zero
    guard AXValueGetValue(value, .cgRect, &rect) else {
      return nil
    }
    return AccessibilityBounds(
      x: rect.origin.x,
      y: rect.origin.y,
      width: rect.size.width,
      height: rect.size.height
    )
  }

  func boundedRange(
    around location: Int,
    characterCount: Int
  ) -> AccessibilityTextRange? {
    guard location >= 0, characterCount >= 0 else {
      return nil
    }
    let start = max(0, location - 40)
    let end = min(characterCount, location + 40)
    return AccessibilityTextRange(
      location: start,
      length: max(0, end - start)
    )
  }

  fileprivate func notificationRegistrationCapabilities(
    editorElement: AXUIElement,
    applicationElement: AXUIElement,
    processIdentifier: pid_t
  ) -> [AccessibilityCapability] {
    var observer: AXObserver?
    let observerError = AXObserverCreate(
      processIdentifier,
      bearAccessibilityObserverCallback,
      &observer
    )
    guard observerError == .success, let observer else {
      return [
        AccessibilityCapability(
          name: "AXObserver",
          state: .failed,
          errorCode: observerError.rawValue
        )
      ]
    }

    let registrations: [(String, AXUIElement)] = [
      (kAXSelectedTextChangedNotification as String, editorElement),
      (kAXValueChangedNotification as String, editorElement),
      (kAXLayoutChangedNotification as String, editorElement),
      (kAXFocusedUIElementChangedNotification as String, applicationElement),
      (kAXFocusedWindowChangedNotification as String, applicationElement),
    ]

    return registrations.map { name, element in
      let error = AXObserverAddNotification(
        observer,
        element,
        name as CFString,
        nil
      )
      if error == .success {
        AXObserverRemoveNotification(observer, element, name as CFString)
      }
      return AccessibilityCapability(
        name: name,
        state: notificationState(for: error),
        errorCode: error == .success ? nil : error.rawValue
      )
    }
  }

  fileprivate func notificationState(
    for error: AXError
  ) -> AccessibilityCapabilityState {
    switch error {
    case .success:
      .available
    case .notificationUnsupported, .attributeUnsupported,
      .actionUnsupported:
      .unsupported
    default:
      .failed
    }
  }
}

public struct BearAccessibilityEventMonitor:
  BearAccessibilityEventMonitoring, Sendable
{
  public init() {}

  public func observe(
    for duration: TimeInterval = 5
  ) -> BearAccessibilityEventReport {
    let observationDuration = min(max(duration, 0.25), 30)
    let durationMilliseconds = Int(
      (observationDuration * 1_000).rounded()
    )

    guard AXIsProcessTrusted() else {
      return BearAccessibilityEventReport(
        status: .accessibilityPermissionRequired,
        editorWasFocused: false,
        durationMilliseconds: durationMilliseconds,
        registrations: [],
        observations: []
      )
    }

    guard
      let runningApplication = NSRunningApplication.runningApplications(
        withBundleIdentifier: BearAccessibilityProbe.bearBundleIdentifier
      ).first
    else {
      return BearAccessibilityEventReport(
        status: .bearNotRunning,
        editorWasFocused: false,
        durationMilliseconds: durationMilliseconds,
        registrations: [],
        observations: []
      )
    }

    let applicationElement = AXUIElementCreateApplication(
      runningApplication.processIdentifier
    )
    configureBearAccessibilityMessagingTimeout(applicationElement)
    guard
      let focusedElement = copyElementAttribute(
        applicationElement,
        kAXFocusedUIElementAttribute as CFString
      )
    else {
      return BearAccessibilityEventReport(
        status: .focusedEditorUnavailable,
        editorWasFocused: false,
        durationMilliseconds: durationMilliseconds,
        registrations: [],
        observations: []
      )
    }

    let probe = BearAccessibilityProbe()
    let focusedEditor = probe.nearestTextArea(startingAt: focusedElement)
    let focusedWindow = copyElementAttribute(
      applicationElement,
      kAXFocusedWindowAttribute as CFString
    )
    let candidates = focusedWindow.map(probe.textAreas(in:)) ?? []
    let editorElement =
      focusedEditor
      ?? (candidates.count == 1 ? candidates.first : nil)
    guard let editorElement else {
      return BearAccessibilityEventReport(
        status: .focusedElementIsNotTextArea,
        editorWasFocused: false,
        durationMilliseconds: durationMilliseconds,
        registrations: [],
        observations: []
      )
    }

    let status: BearAccessibilityProbeStatus =
      focusedEditor == nil ? .editorAvailableButNotFocused : .ready
    let windowElement =
      copyElementAttribute(
        editorElement,
        kAXWindowAttribute as CFString
      ) ?? focusedWindow

    var observer: AXObserver?
    let observerError = AXObserverCreate(
      runningApplication.processIdentifier,
      bearAccessibilityEventCallback,
      &observer
    )
    guard observerError == .success, let observer else {
      return BearAccessibilityEventReport(
        status: status,
        editorWasFocused: focusedEditor != nil,
        durationMilliseconds: durationMilliseconds,
        registrations: [
          AccessibilityCapability(
            name: "AXObserver",
            state: .failed,
            errorCode: observerError.rawValue
          )
        ],
        observations: []
      )
    }

    let collector = BearAccessibilityEventCollector()
    let collectorPointer = Unmanaged.passUnretained(collector).toOpaque()
    var targets: [(name: String, element: AXUIElement)] = [
      (kAXSelectedTextChangedNotification as String, editorElement),
      (kAXValueChangedNotification as String, editorElement),
      (kAXLayoutChangedNotification as String, editorElement),
      (kAXFocusedUIElementChangedNotification as String, applicationElement),
      (kAXFocusedWindowChangedNotification as String, applicationElement),
    ]
    if let windowElement {
      targets.append(
        (kAXWindowMovedNotification as String, windowElement)
      )
      targets.append(
        (kAXWindowResizedNotification as String, windowElement)
      )
    }

    let registrations = targets.map { target in
      let error = AXObserverAddNotification(
        observer,
        target.element,
        target.name as CFString,
        collectorPointer
      )
      return AccessibilityCapability(
        name: target.name,
        state: probe.notificationState(for: error),
        errorCode: error == .success ? nil : error.rawValue
      )
    }

    let runLoop = CFRunLoopGetCurrent()
    let source = AXObserverGetRunLoopSource(observer)
    CFRunLoopAddSource(runLoop, source, .defaultMode)

    let deadline = CFAbsoluteTimeGetCurrent() + observationDuration
    while CFAbsoluteTimeGetCurrent() < deadline {
      let remaining = deadline - CFAbsoluteTimeGetCurrent()
      CFRunLoopRunInMode(.defaultMode, min(0.1, remaining), true)
    }

    CFRunLoopRemoveSource(runLoop, source, .defaultMode)
    for target in targets {
      AXObserverRemoveNotification(
        observer,
        target.element,
        target.name as CFString
      )
    }

    return BearAccessibilityEventReport(
      status: status,
      editorWasFocused: focusedEditor != nil,
      durationMilliseconds: durationMilliseconds,
      registrations: registrations,
      observations: collector.snapshot()
    )
  }
}

private final class BearAccessibilityEventCollector: @unchecked Sendable {
  private let lock = NSLock()
  private var counts: [String: Int] = [:]

  func record(_ name: String) {
    lock.lock()
    counts[name, default: 0] += 1
    lock.unlock()
  }

  func snapshot() -> [AccessibilityEventObservation] {
    lock.lock()
    let snapshot = counts
    lock.unlock()
    return snapshot.keys.sorted().map { name in
      AccessibilityEventObservation(
        name: name,
        count: snapshot[name, default: 0]
      )
    }
  }
}

private func bearAccessibilityEventCallback(
  _: AXObserver,
  _: AXUIElement,
  notification: CFString,
  refcon: UnsafeMutableRawPointer?
) {
  guard let refcon else {
    return
  }
  let collector = Unmanaged<BearAccessibilityEventCollector>
    .fromOpaque(refcon)
    .takeUnretainedValue()
  collector.record(notification as String)
}

private func bearAccessibilityObserverCallback(
  _: AXObserver,
  _: AXUIElement,
  _: CFString,
  _: UnsafeMutableRawPointer?
) {}

private func copyAttributeNames(_ element: AXUIElement) -> Set<String> {
  var names: CFArray?
  guard
    AXUIElementCopyAttributeNames(element, &names) == .success,
    let names = names as? [String]
  else {
    return []
  }
  return Set(names)
}

private func copyParameterizedAttributeNames(
  _ element: AXUIElement
) -> Set<String> {
  var names: CFArray?
  guard
    AXUIElementCopyParameterizedAttributeNames(element, &names) == .success,
    let names = names as? [String]
  else {
    return []
  }
  return Set(names)
}

func copyElementAttribute(
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

private func copyElementArrayAttribute(
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

private func copyStringAttribute(
  _ element: AXUIElement,
  _ name: CFString
) -> String? {
  var value: CFTypeRef?
  guard
    AXUIElementCopyAttributeValue(element, name, &value) == .success
  else {
    return nil
  }
  return value as? String
}

func copyIntegerAttribute(
  _ element: AXUIElement,
  _ name: CFString
) -> Int? {
  var value: CFTypeRef?
  guard
    AXUIElementCopyAttributeValue(element, name, &value) == .success,
    let number = value as? NSNumber
  else {
    return nil
  }
  return number.intValue
}

func copyRangeAttribute(
  _ element: AXUIElement,
  _ name: CFString
) -> AccessibilityTextRange? {
  var value: CFTypeRef?
  guard
    AXUIElementCopyAttributeValue(element, name, &value) == .success,
    let value,
    CFGetTypeID(value) == AXValueGetTypeID()
  else {
    return nil
  }
  let axValue = unsafeDowncast(value, to: AXValue.self)
  guard AXValueGetType(axValue) == .cfRange else {
    return nil
  }
  var range = CFRange()
  guard AXValueGetValue(axValue, .cfRange, &range) else {
    return nil
  }
  return AccessibilityTextRange(
    location: range.location,
    length: range.length
  )
}

func copyParameterizedValue(
  from element: AXUIElement,
  name: CFString,
  range: AccessibilityTextRange
) -> CFTypeRef? {
  var rawRange = CFRange(
    location: range.location,
    length: range.length
  )
  guard let rangeValue = AXValueCreate(.cfRange, &rawRange) else {
    return nil
  }
  var result: CFTypeRef?
  guard
    AXUIElementCopyParameterizedAttributeValue(
      element,
      name,
      rangeValue,
      &result
    ) == .success
  else {
    return nil
  }
  return result
}
