import SwiftUI

struct ContentView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      TypoverHeader()
      EditorLabSection()
      EditorPrinciples()
    }
    .padding(32)
    .frame(minWidth: 720, minHeight: 620)
    .background {
      LinearGradient(
        colors: [
          Color(nsColor: .windowBackgroundColor),
          Color.accentColor.opacity(0.035),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    }
  }
}

private struct TypoverHeader: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label {
        Text(
          "TYPOVER",
          bundle: #bundle,
          comment: "Product name displayed above the main headline."
        )
      } icon: {
        Image(systemName: "text.badge.checkmark")
      }
      .font(.headline)
      .foregroundStyle(.secondary)

      Text(
        "Corrections you can trust—and take back.",
        bundle: #bundle,
        comment: "Main product proposition on the concept screen."
      )
      .font(.largeTitle)
      .fontWeight(.semibold)

      Text(
        "This first lab proves the interaction in an editor we control before we attempt compatibility with Bear.",
        bundle: #bundle,
        comment: "Explanation of why Typover begins with its own editor."
      )
      .font(.title3)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct EditorLabSection: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(
          "CONTROLLED EDITOR LAB",
          bundle: #bundle,
          comment: "Heading above the interactive Typover editor."
        )
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)

        Spacer()

        Label {
          Text(
            "Try: teh + space",
            bundle: #bundle,
            comment: "Compact instruction for triggering the demo correction."
          )
        } icon: {
          Image(systemName: "keyboard")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
      }

      EditorLabView()
        .frame(minHeight: 240)
        .padding(1)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
          RoundedRectangle(cornerRadius: 14)
            .stroke(.separator.opacity(0.65))
        }

      Text(
        "The word changes automatically. Its light-gray squiggle remains clickable so you can change it back or keep the correction.",
        bundle: #bundle,
        comment:
          "Instructions below the Typover editor explaining the reversible correction interaction."
      )
      .font(.callout)
      .foregroundStyle(.secondary)
    }
  }
}

private struct EditorPrinciples: View {
  var body: some View {
    ViewThatFits {
      HStack(spacing: 22) {
        PrincipleLabel(
          icon: "selection.pin.in.out",
          title: "Word-range edits"
        )
        PrincipleLabel(
          icon: "scribble.variable",
          title: "Visible corrections"
        )
        PrincipleLabel(
          icon: "arrow.uturn.backward.circle",
          title: "Immediate restoration"
        )
      }

      VStack(alignment: .leading, spacing: 10) {
        PrincipleLabel(
          icon: "selection.pin.in.out",
          title: "Word-range edits"
        )
        PrincipleLabel(
          icon: "scribble.variable",
          title: "Visible corrections"
        )
        PrincipleLabel(
          icon: "arrow.uturn.backward.circle",
          title: "Immediate restoration"
        )
      }
    }
  }
}

private struct PrincipleLabel: View {
  let icon: String
  let title: LocalizedStringResource

  var body: some View {
    Label(title, systemImage: icon)
      .font(.callout)
      .foregroundStyle(.secondary)
  }
}
