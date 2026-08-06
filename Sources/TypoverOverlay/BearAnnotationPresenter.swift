import AppKit
import TypoverAccessibility
import TypoverCore

@MainActor
public protocol BearAnnotationPresenting: AnyObject {
  func show(
    placements: [AccessibilityBounds],
    interaction: BearAnnotationInteraction
  )
  func setMarkVisible(_ visible: Bool, animated: Bool)
  func containsReviewPoint(_ point: NSPoint) -> Bool
  func containsMarkPoint(_ point: NSPoint) -> Bool
  func showMenu()
  func hide()
}

@MainActor
public final class AppKitBearAnnotationPresenter: BearAnnotationPresenting {
  static let reviewHorizontalReach: CGFloat = 180
  static let reviewVerticalReach: CGFloat = 18

  var panels: [BearSquigglePanel] = []
  private var marksAreVisible = true

  public init() {}

  public func show(
    placements: [AccessibilityBounds],
    interaction: BearAnnotationInteraction
  ) {
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
      let horizontalInset = 4.0
      let lowerInset = 3.0
      let upperInset = 5.0
      let panelFrame = NSRect(
        x: placement.x - horizontalInset,
        y: placement.y - lowerInset,
        width: placement.width + horizontalInset * 2,
        height: placement.height + lowerInset + upperInset
      )
      if panel.frame != panelFrame {
        panel.setFrame(panelFrame, display: false)
      }
      panel.configure(
        squiggleFrame: NSRect(
          x: horizontalInset,
          y: lowerInset,
          width: placement.width,
          height: placement.height
        ),
        interaction: interaction,
        isPrimaryAccessibilityElement: index == 0
      )
      if !panel.isVisible {
        panel.alphaValue = marksAreVisible ? 1 : 0
        panel.ignoresMouseEvents = !marksAreVisible
        panel.orderFrontRegardless()
      }
    }
  }

  public func setMarkVisible(_ visible: Bool, animated: Bool) {
    guard marksAreVisible != visible else {
      return
    }
    marksAreVisible = visible
    for panel in panels where panel.isVisible {
      panel.ignoresMouseEvents = !visible
      if animated
        && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
      {
        NSAnimationContext.runAnimationGroup { context in
          context.duration = CorrectionMarkTiming.fadeTimeInterval
          context.allowsImplicitAnimation = true
          panel.animator().alphaValue = visible ? 1 : 0
        }
      } else {
        panel.alphaValue = visible ? 1 : 0
      }
    }
  }

  public func containsReviewPoint(_ point: NSPoint) -> Bool {
    panels.contains { panel in
      panel.isVisible
        && panel.frame.insetBy(
          dx: -Self.reviewHorizontalReach,
          dy: -Self.reviewVerticalReach
        ).contains(point)
    }
  }

  public func containsMarkPoint(_ point: NSPoint) -> Bool {
    panels.contains { $0.isVisible && $0.frame.contains(point) }
  }

  public func showMenu() {
    panels.first(where: \.isVisible)?.showMenu()
  }

  public func hide() {
    for panel in panels where panel.isVisible {
      panel.orderOut(nil)
    }
  }
}

@MainActor
final class BearSquigglePanel: NSPanel {
  private let squiggleView: BearSquiggleView

  init() {
    squiggleView = BearSquiggleView(
      frame: NSRect(x: 0, y: 0, width: 1, height: 4)
    )
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
    ignoresMouseEvents = false
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    collectionBehavior = [
      .transient,
      .ignoresCycle,
      .fullScreenAuxiliary,
    ]
    contentView = squiggleView
    contentView?.autoresizingMask = [.width, .height]
  }

  func configure(
    squiggleFrame: NSRect,
    interaction: BearAnnotationInteraction,
    isPrimaryAccessibilityElement: Bool
  ) {
    squiggleView.squiggleFrame = squiggleFrame
    squiggleView.interaction = interaction
    squiggleView.setAccessibilityElement(isPrimaryAccessibilityElement)
    squiggleView.setAccessibilityRole(.button)
    squiggleView.setAccessibilityLabel(interaction.accessibilityLabel)
    squiggleView.setAccessibilityIdentifier(
      "typover.bear.correction-options"
    )
    squiggleView.setAccessibilityHelp(
      "Opens correction options. Accessibility actions can revert the correction or choose another suggestion without moving focus."
    )
    setAccessibilityElement(isPrimaryAccessibilityElement)
    setAccessibilityRole(.window)
    setAccessibilitySubrole(.floatingWindow)
    setAccessibilityLabel(interaction.accessibilityLabel)
    setAccessibilityIdentifier("typover.bear.correction-overlay")
    setAccessibilityChildren(
      isPrimaryAccessibilityElement ? [squiggleView] : []
    )
    squiggleView.needsDisplay = true
  }

  func showMenu() {
    squiggleView.showMenu()
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

final class BearSquiggleView: NSView {
  var squiggleFrame = NSRect(x: 0, y: 0, width: 1, height: 4)
  var interaction: BearAnnotationInteraction?
  private var menuSession: BearAnnotationMenuSession?

  override var isOpaque: Bool { false }

  override func mouseDown(with event: NSEvent) {
    showMenu(event: event)
  }

  override func rightMouseDown(with event: NSEvent) {
    showMenu(event: event)
  }

  override func accessibilityPerformPress() -> Bool {
    guard interaction != nil else {
      return false
    }
    Task { @MainActor [weak self] in
      self?.showMenu()
    }
    return true
  }

  override func accessibilityCustomActions()
    -> [NSAccessibilityCustomAction]?
  {
    guard let interaction else {
      return nil
    }
    let interactionID = interaction.id
    return interaction.items.map { item in
      NSAccessibilityCustomAction(name: item.title) { [weak self] in
        guard let self,
          let currentInteraction = self.interaction,
          currentInteraction.id == interactionID,
          currentInteraction.items.contains(where: {
            $0.action == item.action
          })
        else {
          return false
        }
        currentInteraction.handler(item.action)
        return true
      }
    }
  }

  func showMenu() {
    showMenu(event: nil)
  }

  private func showMenu(event: NSEvent?) {
    guard let interaction, !interaction.items.isEmpty else {
      return
    }
    interaction.onMenuVisibilityChanged(true)
    defer {
      interaction.onMenuVisibilityChanged(false)
    }
    let session = BearAnnotationMenuSession(interaction: interaction)
    session.onClose = { [weak self] menu in
      guard self?.menuSession?.menu === menu else {
        return
      }
      self?.menuSession = nil
    }
    menuSession = session
    let menu = session.menu

    if let event {
      NSMenu.popUpContextMenu(menu, with: event, for: self)
    } else {
      menu.popUp(
        positioning: menu.items.first,
        at: NSPoint(x: bounds.midX, y: bounds.maxY + 2),
        in: self
      )
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard squiggleFrame.width > 0, squiggleFrame.height > 0 else {
      return
    }

    let path = NSBezierPath()
    path.lineWidth = 1.15
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    let centerY = squiggleFrame.midY
    let amplitude = min(1.15, max(0.7, squiggleFrame.height * 0.22))
    let wavelength = 4.2
    let step = 0.7
    path.move(to: NSPoint(x: squiggleFrame.minX, y: centerY))
    var x = squiggleFrame.minX + step
    while x < squiggleFrame.maxX {
      let y = centerY + sin((x / wavelength) * .pi * 2) * amplitude
      path.line(to: NSPoint(x: x, y: y))
      x += step
    }
    path.line(to: NSPoint(x: squiggleFrame.maxX, y: centerY))
    NSColor.secondaryLabelColor.withAlphaComponent(0.52).setStroke()
    path.stroke()
  }
}

@MainActor
final class BearAnnotationMenuSession: NSObject, NSMenuDelegate {
  let menu = NSMenu()
  var onClose: ((NSMenu) -> Void)?
  private let target: BearAnnotationMenuTarget

  init(interaction: BearAnnotationInteraction) {
    target = BearAnnotationMenuTarget(handler: interaction.handler)
    super.init()
    menu.delegate = self
    menu.autoenablesItems = false
    for (index, item) in interaction.items.enumerated() {
      if item.beginsAlternativeSection {
        menu.addItem(.separator())
      }
      let menuItem = NSMenuItem(
        title: item.title,
        action: NSSelectorFromString("performMenuItem:"),
        keyEquivalent: ""
      )
      menuItem.target = target
      menuItem.tag = index
      menuItem.isEnabled = true
      menuItem.setAccessibilityLabel(item.title)
      menu.addItem(menuItem)
    }
    target.actions = interaction.items.map(\.action)
  }

  func menuDidClose(_ menu: NSMenu) {
    onClose?(menu)
  }
}

@MainActor
@objc(TypoverBearAnnotationMenuTarget)
final class BearAnnotationMenuTarget: NSObject {
  var actions: [BearAnnotationAction] = []
  private let handler: @MainActor @Sendable (BearAnnotationAction) -> Void

  init(
    handler:
      @escaping @MainActor @Sendable (
        BearAnnotationAction
      ) -> Void
  ) {
    self.handler = handler
  }

  @objc(performMenuItem:)
  dynamic func perform(_ sender: NSMenuItem) {
    guard actions.indices.contains(sender.tag) else {
      return
    }
    handler(actions[sender.tag])
  }
}
