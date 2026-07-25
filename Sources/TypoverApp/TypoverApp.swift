import AppKit
import SwiftUI

@main
struct TypoverApp: App {
  init() {
    if let iconURL = Bundle.module.url(
      forResource: "TypoverAppIcon",
      withExtension: "png"
    ), let icon = NSImage(contentsOf: iconURL) {
      NSApplication.shared.applicationIconImage = icon
    }
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    .defaultSize(width: 760, height: 540)
    .windowResizability(.contentMinSize)
  }
}
