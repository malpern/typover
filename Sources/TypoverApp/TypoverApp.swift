import AppKit
import SwiftUI
import TypoverCore

@main
struct TypoverApp: App {
  @State private var behaviorSettings = CorrectionBehaviorSettings()
  @State private var learningStore = CorrectionLearningStore()

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
    }

    Window("About Typover", id: "about") {
      AboutView()
    }
    .defaultPosition(.center)
    .windowResizability(.contentSize)

    Settings {
      LearningSettingsView(
        behaviorSettings: behaviorSettings,
        learningStore: learningStore
      )
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
