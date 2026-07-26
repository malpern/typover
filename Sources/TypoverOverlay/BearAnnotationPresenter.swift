import AppKit
import TypoverAccessibility

@MainActor
public protocol BearAnnotationPresenting: AnyObject {
  func show(placements: [AccessibilityBounds])
  func hide()
}

@MainActor
public final class AppKitBearAnnotationPresenter: BearAnnotationPresenting {
  var panels: [BearSquigglePanel] = []

  public init() {}

  public func show(placements: [AccessibilityBounds]) {
    guard !placements.isEmpty else {
      hide()
      return
    }

    while panels.count < placements.count {
      panels.append(BearSquigglePanel())
    }
    for (index, panel) in panels.enumerated() {
      guard index < placements.count else {
        panel.orderOut(nil)
        continue
      }
      let placement = placements[index]
      panel.setFrame(
        NSRect(
          x: placement.x,
          y: placement.y,
          width: placement.width,
          height: placement.height
        ),
        display: false
      )
      panel.orderFrontRegardless()
    }
  }

  public func hide() {
    for panel in panels {
      panel.orderOut(nil)
    }
  }
}

@MainActor
final class BearSquigglePanel: NSPanel {
  init() {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 1, height: 4),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    level = .floating
    ignoresMouseEvents = true
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    collectionBehavior = [
      .transient,
      .ignoresCycle,
      .fullScreenAuxiliary,
    ]
    contentView = BearSquiggleView(frame: contentRect(forFrameRect: frame))
    contentView?.autoresizingMask = [.width, .height]
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

private final class BearSquiggleView: NSView {
  override var isOpaque: Bool { false }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard bounds.width > 0, bounds.height > 0 else {
      return
    }

    let path = NSBezierPath()
    path.lineWidth = 1.15
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    let centerY = bounds.midY
    let amplitude = min(1.15, max(0.7, bounds.height * 0.22))
    let wavelength = 4.2
    let step = 0.7
    path.move(to: NSPoint(x: 0, y: centerY))
    var x = step
    while x < bounds.width {
      let y = centerY + sin((x / wavelength) * .pi * 2) * amplitude
      path.line(to: NSPoint(x: x, y: y))
      x += step
    }
    path.line(to: NSPoint(x: bounds.width, y: centerY))
    NSColor.secondaryLabelColor.withAlphaComponent(0.52).setStroke()
    path.stroke()
  }
}
