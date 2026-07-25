import SwiftUI

@main
struct TypoverApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    .defaultSize(width: 760, height: 540)
    .windowResizability(.contentMinSize)
  }
}
