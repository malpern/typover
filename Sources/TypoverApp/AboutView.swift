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
  let buildIdentity: TypoverBuildIdentity

  init(buildIdentity: TypoverBuildIdentity = .current) {
    self.buildIdentity = buildIdentity
  }

  var body: some View {
    VStack(spacing: 22) {
      AboutIdentity(buildIdentity: buildIdentity)
      Divider()
      AboutRepositoryLink()
    }
    .padding(30)
    .frame(width: 390)
  }
}

private struct AboutIdentity: View {
  let buildIdentity: TypoverBuildIdentity

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

      AboutBuildIdentity(identity: buildIdentity)
    }
  }
}

private struct AboutBuildIdentity: View {
  let identity: TypoverBuildIdentity

  var body: some View {
    VStack(spacing: 3) {
      if let versionAndBuild = identity.versionAndBuild {
        Text(
          "Version \(versionAndBuild.version) (\(versionAndBuild.build))",
          bundle: #bundle,
          comment: "Typover version and build number in the About window."
        )
      } else {
        Text(
          "Development build",
          bundle: #bundle,
          comment: "Fallback build identity in an unbundled development run."
        )
      }

      if let revision = identity.shortSourceRevision {
        if identity.sourceIsDirty == true {
          Text(
            "Source \(revision) · Modified",
            bundle: #bundle,
            comment: "Short source revision for a build with local changes."
          )
        } else {
          Text(
            "Source \(revision)",
            bundle: #bundle,
            comment: "Short source revision for the current Typover build."
          )
        }
      }
    }
    .font(.caption.monospacedDigit())
    .foregroundStyle(.secondary)
    .textSelection(.enabled)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("typover.about.build-identity")
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
