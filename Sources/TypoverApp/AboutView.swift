import AppKit
import SwiftUI

enum TypoverBrand {
  static let repositoryURL = URL(
    string: "https://github.com/malpern/typover"
  )!

  static let appIcon: NSImage = {
    guard
      let iconURL = Bundle.module.url(
        forResource: "TypoverAppIcon",
        withExtension: "png"
      ),
      let icon = NSImage(contentsOf: iconURL)
    else {
      return NSImage(
        systemSymbolName: "text.badge.checkmark",
        accessibilityDescription: "Typover"
      ) ?? NSImage(size: NSSize(width: 128, height: 128))
    }
    return icon
  }()
}

struct AboutView: View {
  var body: some View {
    VStack(spacing: 22) {
      AboutIdentity()
      Divider()
      AboutRepositoryLink()
    }
    .padding(30)
    .frame(width: 390)
  }
}

private struct AboutIdentity: View {
  var body: some View {
    VStack(spacing: 12) {
      Image(nsImage: TypoverBrand.appIcon)
        .resizable()
        .scaledToFit()
        .frame(width: 176, height: 176)
        .accessibilityLabel(
          Text(
            "Typover app icon",
            bundle: #bundle,
            comment: "Accessibility label for the app icon in the About window."
          )
        )

      Text(
        "Typover",
        bundle: #bundle,
        comment: "Product name in the About window."
      )
      .font(.largeTitle)
      .fontWeight(.semibold)

      Text(
        "Automatic, visible, reversible spell correction for macOS.",
        bundle: #bundle,
        comment: "One-sentence product description in the About window."
      )
      .font(.body)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)

      Text(
        "Created by Micah Alpern",
        bundle: #bundle,
        comment: "Creator credit in the About window."
      )
      .font(.callout)
    }
  }
}

private struct AboutRepositoryLink: View {
  var body: some View {
    Link(destination: TypoverBrand.repositoryURL) {
      Label {
        Text(
          "View Typover on GitHub",
          bundle: #bundle,
          comment: "Link from the About window to the Typover GitHub repository."
        )
      } icon: {
        Image(systemName: "arrow.up.right.square")
      }
    }
    .accessibilityIdentifier("typover.about.github")
  }
}
