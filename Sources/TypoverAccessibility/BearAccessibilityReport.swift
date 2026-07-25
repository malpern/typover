import Foundation

public enum BearAccessibilityProbeStatus: String, Codable, Equatable, Sendable {
  case ready
  case accessibilityPermissionRequired
  case bearNotRunning
  case focusedEditorUnavailable
  case focusedElementIsNotTextArea
  case editorAvailableButNotFocused
}

public protocol BearAccessibilityProbing: Sendable {
  func run() -> BearAccessibilityReport
}

public protocol BearAccessibilityEventMonitoring: Sendable {
  func observe(for duration: TimeInterval) -> BearAccessibilityEventReport
}

public enum AccessibilityCapabilityState: String, Codable, Equatable, Sendable {
  case available
  case unsupported
  case failed
}

public struct AccessibilityCapability: Codable, Equatable, Sendable {
  public let name: String
  public let state: AccessibilityCapabilityState
  public let isWritable: Bool?
  public let errorCode: Int32?

  public init(
    name: String,
    state: AccessibilityCapabilityState,
    isWritable: Bool? = nil,
    errorCode: Int32? = nil
  ) {
    self.name = name
    self.state = state
    self.isWritable = isWritable
    self.errorCode = errorCode
  }
}

public struct AccessibilityTextRange: Codable, Equatable, Sendable {
  public let location: Int
  public let length: Int

  public init(location: Int, length: Int) {
    self.location = location
    self.length = length
  }
}

public struct AccessibilityBounds: Codable, Equatable, Sendable {
  public let x: Double
  public let y: Double
  public let width: Double
  public let height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }
}

public struct BearAccessibilityReport: Codable, Equatable, Sendable {
  public let status: BearAccessibilityProbeStatus
  public let accessibilityTrusted: Bool
  public let bearIsRunning: Bool
  public let editorRole: String?
  public let editorIdentifier: String?
  public let editorWasFocused: Bool?
  public let focusedWindowAvailable: Bool?
  public let textAreaCandidateCount: Int?
  public let selectedRange: AccessibilityTextRange?
  public let visibleRange: AccessibilityTextRange?
  public let characterCount: Int?
  public let boundedContextUTF16Length: Int?
  public let boundedContextReader: String?
  public let rangeBounds: AccessibilityBounds?
  public let attributes: [AccessibilityCapability]
  public let parameterizedAttributes: [AccessibilityCapability]
  public let notificationRegistrations: [AccessibilityCapability]

  public init(
    status: BearAccessibilityProbeStatus,
    accessibilityTrusted: Bool,
    bearIsRunning: Bool,
    editorRole: String? = nil,
    editorIdentifier: String? = nil,
    editorWasFocused: Bool? = nil,
    focusedWindowAvailable: Bool? = nil,
    textAreaCandidateCount: Int? = nil,
    selectedRange: AccessibilityTextRange? = nil,
    visibleRange: AccessibilityTextRange? = nil,
    characterCount: Int? = nil,
    boundedContextUTF16Length: Int? = nil,
    boundedContextReader: String? = nil,
    rangeBounds: AccessibilityBounds? = nil,
    attributes: [AccessibilityCapability] = [],
    parameterizedAttributes: [AccessibilityCapability] = [],
    notificationRegistrations: [AccessibilityCapability] = []
  ) {
    self.status = status
    self.accessibilityTrusted = accessibilityTrusted
    self.bearIsRunning = bearIsRunning
    self.editorRole = editorRole
    self.editorIdentifier = editorIdentifier
    self.editorWasFocused = editorWasFocused
    self.focusedWindowAvailable = focusedWindowAvailable
    self.textAreaCandidateCount = textAreaCandidateCount
    self.selectedRange = selectedRange
    self.visibleRange = visibleRange
    self.characterCount = characterCount
    self.boundedContextUTF16Length = boundedContextUTF16Length
    self.boundedContextReader = boundedContextReader
    self.rangeBounds = rangeBounds
    self.attributes = attributes
    self.parameterizedAttributes = parameterizedAttributes
    self.notificationRegistrations = notificationRegistrations
  }
}

public struct AccessibilityEventObservation:
  Codable, Equatable, Sendable, Identifiable
{
  public let name: String
  public let count: Int

  public var id: String {
    name
  }

  public init(name: String, count: Int) {
    self.name = name
    self.count = count
  }
}

public struct BearAccessibilityEventReport:
  Codable, Equatable, Sendable
{
  public let status: BearAccessibilityProbeStatus
  public let editorWasFocused: Bool
  public let durationMilliseconds: Int
  public let registrations: [AccessibilityCapability]
  public let observations: [AccessibilityEventObservation]

  public init(
    status: BearAccessibilityProbeStatus,
    editorWasFocused: Bool,
    durationMilliseconds: Int,
    registrations: [AccessibilityCapability],
    observations: [AccessibilityEventObservation]
  ) {
    self.status = status
    self.editorWasFocused = editorWasFocused
    self.durationMilliseconds = durationMilliseconds
    self.registrations = registrations
    self.observations = observations
  }
}
