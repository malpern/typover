import Foundation

public struct Correction: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let original: String
  public let replacement: String
  public let confidence: Double
  public let createdAt: Date

  public init(
    id: UUID = UUID(),
    original: String,
    replacement: String,
    confidence: Double,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.original = original
    self.replacement = replacement
    self.confidence = min(max(confidence, 0), 1)
    self.createdAt = createdAt
  }

  public var changesText: Bool {
    original != replacement
  }
}
