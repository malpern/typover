import AppKit
import SwiftUI

@main
struct TypoverApp: App {
  init() {
    NSApplication.shared.applicationIconImage = TypoverBrand.appIcon
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
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
