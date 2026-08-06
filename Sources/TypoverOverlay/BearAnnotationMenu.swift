import Foundation
import TypoverBearAdapter

public enum BearAnnotationAction: Equatable, Hashable, Sendable {
  case changeBack
  case chooseAlternative(String)
}

public struct BearAnnotationMenuItem: Equatable, Sendable {
  public let title: String
  public let action: BearAnnotationAction
  public let beginsAlternativeSection: Bool

  public init(
    title: String,
    action: BearAnnotationAction,
    beginsAlternativeSection: Bool = false
  ) {
    self.title = title
    self.action = action
    self.beginsAlternativeSection = beginsAlternativeSection
  }
}

public struct BearAnnotationInteraction {
  public let id: UUID
  public let items: [BearAnnotationMenuItem]
  public let accessibilityLabel: String
  public let onMenuVisibilityChanged: @MainActor @Sendable (Bool) -> Void
  public let handler: @MainActor @Sendable (BearAnnotationAction) -> Void

  public init(
    id: UUID = UUID(),
    items: [BearAnnotationMenuItem],
    accessibilityLabel: String,
    onMenuVisibilityChanged: @escaping @MainActor @Sendable (Bool) -> Void = {
      _ in
    },
    handler:
      @escaping @MainActor @Sendable (
        BearAnnotationAction
      ) -> Void
  ) {
    self.id = id
    self.items = items
    self.accessibilityLabel = accessibilityLabel
    self.onMenuVisibilityChanged = onMenuVisibilityChanged
    self.handler = handler
  }
}

public enum BearAnnotationMenuModel {
  public static let maximumAlternativeCount = 5

  public static func items(
    for application: BearCorrectionApplication,
    alternatives: [String]
  ) -> [BearAnnotationMenuItem] {
    var items = [
      BearAnnotationMenuItem(
        title: "Revert to \(quoted(application.correction.original))",
        action: .changeBack
      )
    ]
    var seen = Set([
      application.correction.original,
      application.correction.replacement,
    ])
    let filtered = alternatives.compactMap { candidate -> String? in
      let candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !candidate.isEmpty,
        candidate.utf16.count <= 160,
        !candidate.contains("\n"),
        seen.insert(candidate).inserted
      else {
        return nil
      }
      return candidate
    }.prefix(maximumAlternativeCount)
    for (index, alternative) in filtered.enumerated() {
      items.append(
        BearAnnotationMenuItem(
          title: alternative,
          action: .chooseAlternative(alternative),
          beginsAlternativeSection: index == 0
        )
      )
    }
    return items
  }

  public static func accessibilityLabel(
    for application: BearCorrectionApplication
  ) -> String {
    "Correction options for \(application.correction.replacement)"
  }

  private static func quoted(_ text: String) -> String {
    "“\(text)”"
  }
}
