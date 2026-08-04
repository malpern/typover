import Foundation

public struct Correction: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let original: String
  public let replacement: String
  public let createdAt: Date

  public init(
    id: UUID = UUID(),
    original: String,
    replacement: String,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.original = original
    self.replacement = replacement
    self.createdAt = createdAt
  }

  public var changesText: Bool {
    original != replacement
  }
}
