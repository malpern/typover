import AppKit
import SwiftUI
import TypoverCore

@main
struct TypoverApp: App {
  @State private var behaviorSettings = CorrectionBehaviorSettings()
  @State private var learningStore = CorrectionLearningStore()
  @State private var bearOverlayPreviewCoordinator =
    BearOverlayPreviewCoordinator()

  init() {
    NSApplication.shared.applicationIconImage = TypoverBrand.appIcon
  }

  var body: some Scene {
    WindowGroup {
      ContentView(
        behaviorSettings: behaviorSettings,
        learningStore: learningStore
      )
    }
    .defaultSize(width: 760, height: 540)
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
        bearOverlayPreviewCoordinator: bearOverlayPreviewCoordinator
      )
    }
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
