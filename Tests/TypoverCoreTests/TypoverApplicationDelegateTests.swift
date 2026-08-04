import AppKit
import Testing

@testable import TypoverApp

@MainActor
@Suite(.serialized)
struct TypoverApplicationDelegateTests {
  @Test("Reopens the hidden main window without choosing another scene")
  func restoresMainWindow() {
    let delegate = TypoverApplicationDelegate()
    let aboutWindow = TestWindow(identifier: "about")
    let mainWindow = TestWindow(identifier: "main")

    #expect(delegate.restoreMainWindow(in: [aboutWindow, mainWindow]))
    #expect(mainWindow.presentationCount == 1)
    #expect(aboutWindow.presentationCount == 0)
  }

  @Test("Reports when the main scene is unavailable")
  func refusesAnotherWindow() {
    let delegate = TypoverApplicationDelegate()
    let aboutWindow = TestWindow(identifier: "about")

    #expect(!delegate.restoreMainWindow(in: [aboutWindow]))
    #expect(aboutWindow.presentationCount == 0)
  }
}

@MainActor
private final class TestWindow: TypoverWindowPresenting {
  let identifier: NSUserInterfaceItemIdentifier?
  private(set) var presentationCount = 0

  init(identifier: String) {
    self.identifier = NSUserInterfaceItemIdentifier(identifier)
  }

  func presentForApplicationReopen() {
    presentationCount += 1
  }
}
