import CoreGraphics
import TypoverAccessibility

public struct BearOverlayDisplay: Equatable, Sendable {
  public let accessibilityFrame: AccessibilityBounds
  public let appKitFrame: AccessibilityBounds

  public init(
    accessibilityFrame: AccessibilityBounds,
    appKitFrame: AccessibilityBounds
  ) {
    self.accessibilityFrame = accessibilityFrame
    self.appKitFrame = appKitFrame
  }
}

public enum BearAnnotationLayout {
  public static let maximumFragmentCount = 16

  public static func visiblePlacements(
    for report: BearCorrectionGeometryReport,
    bearIsFrontmost: Bool,
    displays: [BearOverlayDisplay]
  ) -> [AccessibilityBounds]? {
    guard bearIsFrontmost, report.isUsable else {
      return nil
    }
    return placements(for: report.fragments, displays: displays)
  }

  /// Converts Accessibility's top-left screen coordinates to AppKit's
  /// bottom-left coordinates and reduces each glyph box to a narrow underline
  /// strip. Any unplaceable fragment rejects the complete annotation.
  public static func placements(
    for fragments: [AccessibilityBounds],
    displays: [BearOverlayDisplay]
  ) -> [AccessibilityBounds]? {
    guard !fragments.isEmpty,
      fragments.count <= maximumFragmentCount,
      !displays.isEmpty
    else {
      return nil
    }

    var placements: [AccessibilityBounds] = []
    placements.reserveCapacity(fragments.count)
    for fragment in fragments {
      guard
        fragment.isDrawable,
        let display = displays.first(where: {
          $0.accessibilityFrame.contains(fragment)
        })
      else {
        return nil
      }

      let accessibilityDisplay = display.accessibilityFrame
      let appKitDisplay = display.appKitFrame
      let relativeX = fragment.x - accessibilityDisplay.x
      let relativeTop = fragment.y - accessibilityDisplay.y
      let glyphBottom =
        appKitDisplay.y + appKitDisplay.height - relativeTop - fragment.height
      let stripHeight = min(5, max(3, fragment.height * 0.18))
      let stripBottom = glyphBottom + max(1, fragment.height * 0.06)
      let placement = AccessibilityBounds(
        x: appKitDisplay.x + relativeX,
        y: stripBottom,
        width: fragment.width,
        height: stripHeight
      )
      guard placement.isDrawable else {
        return nil
      }
      placements.append(placement)
    }
    return placements
  }
}

extension AccessibilityBounds {
  fileprivate var isDrawable: Bool {
    x.isFinite && y.isFinite && width.isFinite && height.isFinite
      && width > 0 && height > 0
  }

  fileprivate func contains(_ other: AccessibilityBounds) -> Bool {
    let tolerance = 0.5
    return other.x >= x - tolerance
      && other.y >= y - tolerance
      && other.x + other.width <= x + width + tolerance
      && other.y + other.height <= y + height + tolerance
  }
}
