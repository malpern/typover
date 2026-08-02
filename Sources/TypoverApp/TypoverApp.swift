import AppKit
import SwiftUI
import TypoverCore

@main
struct TypoverApp: App {
  @NSApplicationDelegateAdaptor(TypoverApplicationDelegate.self)
  private var applicationDelegate
  @AppStorage("typover-onboarding-pending")
  private var isShowingOnboarding = true
  @State private var behaviorSettings: CorrectionBehaviorSettings
  @State private var learningStore: CorrectionLearningStore
  @State private var bearOverlayPreviewCoordinator: BearOverlayPreviewCoordinator
  @State private var bearAutomaticCorrectionCoordinator: BearAutomaticCorrectionCoordinator

  init() {
    let behaviorSettings = CorrectionBehaviorSettings()
    let learningStore = CorrectionLearningStore()
    let automaticCoordinator = BearAutomaticCorrectionCoordinator(
      learningStore: learningStore
    )
    automaticCoordinator.setEnabled(
      behaviorSettings.bearAutomaticCorrectionEnabled
    )
    _behaviorSettings = State(initialValue: behaviorSettings)
    _learningStore = State(initialValue: learningStore)
    _bearOverlayPreviewCoordinator = State(
      initialValue: BearOverlayPreviewCoordinator()
    )
    _bearAutomaticCorrectionCoordinator = State(
      initialValue: automaticCoordinator
    )
    NSApplication.shared.applicationIconImage = TypoverBrand.appIcon
  }

  var body: some Scene {
    Window("Typover", id: "main") {
      ContentView(
        behaviorSettings: behaviorSettings,
        learningStore: learningStore
      )
      .sheet(isPresented: $isShowingOnboarding) {
        TypoverOnboardingView {
          isShowingOnboarding = false
        }
        .interactiveDismissDisabled()
      }
    }
    .defaultSize(width: 760, height: 540)
    .defaultLaunchBehavior(.presented)
    .windowResizability(.contentMinSize)
    .commands {
      AboutCommands()
      BearPreviewCommands(
        coordinator: bearOverlayPreviewCoordinator
      )
    }

    Window("About Typover", id: "about") {
      AboutView()
    }
    .defaultPosition(.center)
    .windowResizability(.contentSize)

    Settings {
      LearningSettingsView(
        behaviorSettings: behaviorSettings,
        learningStore: learningStore,
        bearOverlayPreviewCoordinator: bearOverlayPreviewCoordinator,
        bearAutomaticCorrectionCoordinator:
          bearAutomaticCorrectionCoordinator
      )
    }
  }
}

@MainActor
final class TypoverApplicationDelegate: NSObject, NSApplicationDelegate {
  static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("main")

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      restoreMainWindow(in: sender.windows.map { $0 })
    }
    return true
  }

  @discardableResult
  func restoreMainWindow(
    in windows: [any TypoverWindowPresenting]
  ) -> Bool {
    guard
      let mainWindow = windows.first(where: {
        $0.identifier == Self.mainWindowIdentifier
      })
    else {
      return false
    }
    mainWindow.presentForApplicationReopen()
    return true
  }
}

@MainActor
protocol TypoverWindowPresenting: AnyObject {
  var identifier: NSUserInterfaceItemIdentifier? { get }
  func presentForApplicationReopen()
}

extension NSWindow: TypoverWindowPresenting {
  func presentForApplicationReopen() {
    makeKeyAndOrderFront(nil)
  }
}

private struct BearPreviewCommands: Commands {
  let coordinator: BearOverlayPreviewCoordinator

  var body: some Commands {
    CommandGroup(after: .appSettings) {
      Button {
        coordinator.previewSelectedTypo()
      } label: {
        Text(
          "Preview Selected Bear Typo",
          bundle: #bundle,
          comment:
            "App menu command that previews Typover on the selected Bear typo."
        )
      }
      .keyboardShortcut("p", modifiers: [.control, .option, .command])
    }
  }
}

private struct AboutCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(replacing: .appInfo) {
      Button {
        openWindow(id: "about")
      } label: {
        Text(
          "About Typover",
          bundle: #bundle,
          comment: "App menu command that opens the Typover About window."
        )
      }
    }
  }
}
