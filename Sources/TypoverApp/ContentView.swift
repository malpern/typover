import SwiftUI
import TypoverCore

struct ContentView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      TypoverHeader()
      CorrectionPreview()
      ResearchStatus()
      Spacer(minLength: 0)
    }
    .padding(36)
    .frame(minWidth: 640, minHeight: 460)
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
        "Typover quietly fixes high-confidence mistakes while keeping every automatic change visible and reversible.",
        bundle: #bundle,
        comment: "One-sentence explanation of Typover."
      )
      .font(.title3)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct CorrectionPreview: View {
  private let correction = Correction(
    original: "teh",
    replacement: "the",
    confidence: 0.99
  )

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(
        "A CORRECTION IN CONTEXT",
        bundle: #bundle,
        comment: "Heading above the correction interaction preview."
      )
      .font(.caption)
      .fontWeight(.semibold)
      .foregroundStyle(.secondary)

      HStack(spacing: 5) {
        Text(
          "I sent",
          bundle: #bundle,
          comment: "Beginning of a demonstration sentence."
        )
        CorrectionToken(text: correction.replacement)
        Text(
          "note yesterday.",
          bundle: #bundle,
          comment: "End of a demonstration sentence."
        )
      }
      .font(.title2)

      HStack(spacing: 8) {
        Image(systemName: "arrow.uturn.backward")
        Text(
          "Change back to “teh”",
          bundle: #bundle,
          comment: "Example action for restoring the originally typed word."
        )
      }
      .font(.callout)
      .foregroundStyle(.secondary)
    }
    .padding(22)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    .overlay {
      RoundedRectangle(cornerRadius: 18)
        .stroke(.separator.opacity(0.5))
    }
  }
}

private struct CorrectionToken: View {
  let text: String

  var body: some View {
    VStack(spacing: 1) {
      Text(text)
      Squiggle()
        .stroke(.secondary.opacity(0.65), lineWidth: 1)
        .frame(height: 3)
        .accessibilityHidden(true)
    }
    .fixedSize()
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      Text(
        "Automatically corrected to \(text)",
        bundle: #bundle,
        comment: "Accessibility description for automatically corrected text."
      )
    )
  }
}

private struct Squiggle: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let wavelength: CGFloat = 5
    let amplitude = rect.height / 2
    let centerY = rect.midY

    path.move(to: CGPoint(x: rect.minX, y: centerY))

    var x = rect.minX
    var rises = true
    while x < rect.maxX {
      let nextX = min(x + wavelength / 2, rect.maxX)
      path.addQuadCurve(
        to: CGPoint(x: nextX, y: centerY),
        control: CGPoint(
          x: (x + nextX) / 2,
          y: centerY + (rises ? -amplitude : amplitude)
        )
      )
      rises.toggle()
      x = nextX
    }

    return path
  }
}

private struct ResearchStatus: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(
        "FIRST QUESTIONS",
        bundle: #bundle,
        comment: "Heading above the initial research areas."
      )
      .font(.caption)
      .fontWeight(.semibold)
      .foregroundStyle(.secondary)

      ResearchItem(
        icon: "text.cursor",
        title: "Incremental replacement",
        detail: "Change only the affected word or sentence range."
      )
      ResearchItem(
        icon: "scribble.variable",
        title: "Persistent annotation",
        detail: "Keep each automatic correction quietly visible."
      )
      ResearchItem(
        icon: "arrow.uturn.backward.circle",
        title: "Per-change restoration",
        detail: "Recover the original without disturbing later edits."
      )
    }
  }
}

private struct ResearchItem: View {
  let icon: String
  let title: LocalizedStringResource
  let detail: LocalizedStringResource

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Image(systemName: icon)
        .frame(width: 20)
        .foregroundStyle(.secondary)

      Text(title)
        .fontWeight(.medium)

      Text(detail)
        .foregroundStyle(.secondary)
    }
    .font(.body)
  }
}
