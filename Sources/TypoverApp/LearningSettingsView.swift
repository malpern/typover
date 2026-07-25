import AppKit
import SwiftUI
import TypoverAppleIntelligence
import TypoverCore

struct LearningSettingsView: View {
  let learningStore: CorrectionLearningStore

  @State private var isConfirmingResetAll = false
  @State private var isConfirmingStatisticsReset = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        LearningSettingsHeader()
        ContextualModelStatusSection(
          availability: AppleContextualModelAvailability.current(
            for: NSSpellChecker.shared.userPreferredLanguages.first
          )
        )
        CorrectionStatisticsSection(
          statistics: learningStore.statistics(),
          sourceStatistics: learningStore.statisticsBySource(),
          onReset: {
            isConfirmingStatisticsReset = true
          }
        )
        RememberedRulesSection(
          rules: learningStore.rememberedRules,
          onRemove: learningStore.removeRule
        )
        LearningPrivacySection(
          onResetAll: {
            isConfirmingResetAll = true
          }
        )
      }
      .padding(24)
    }
    .frame(width: 640)
    .frame(minHeight: 560)
    .confirmationDialog(
      String(
        localized: "Reset correction statistics?",
        bundle: #bundle,
        comment:
          "Title of the confirmation shown before clearing Typover correction statistics."
      ),
      isPresented: $isConfirmingStatisticsReset,
      titleVisibility: .visible
    ) {
      Button(role: .destructive) {
        learningStore.resetStatistics()
      } label: {
        Text(
          "Reset Statistics",
          bundle: #bundle,
          comment: "Confirmation button that clears Typover correction statistics."
        )
      }
      Button(role: .cancel) {
      } label: {
        Text(
          "Cancel",
          bundle: #bundle,
          comment: "Button that cancels a Typover statistics reset."
        )
      }
    } message: {
      Text(
        "Remembered correction choices will not be changed.",
        bundle: #bundle,
        comment:
          "Explanation that resetting statistics preserves learned correction preferences."
      )
    }
    .confirmationDialog(
      String(
        localized: "Reset all Typover learning?",
        bundle: #bundle,
        comment:
          "Title of the confirmation shown before clearing all Typover local learning data."
      ),
      isPresented: $isConfirmingResetAll,
      titleVisibility: .visible
    ) {
      Button(role: .destructive) {
        learningStore.resetAllLearning()
      } label: {
        Text(
          "Reset All Learning",
          bundle: #bundle,
          comment:
            "Confirmation button that clears all Typover correction preferences and statistics."
        )
      }
      Button(role: .cancel) {
      } label: {
        Text(
          "Cancel",
          bundle: #bundle,
          comment: "Button that cancels a reset of all Typover learning."
        )
      }
    } message: {
      Text(
        "This removes every remembered correction choice and all correction statistics from this Mac.",
        bundle: #bundle,
        comment:
          "Explanation of the data removed by resetting all Typover learning."
      )
    }
  }
}

private struct ContextualModelStatusSection: View {
  let availability: ContextualCorrectionAvailability

  var body: some View {
    GroupBox {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: availability.systemImage)
          .font(.title2)
          .foregroundStyle(availability.tint)
          .frame(width: 28)

        VStack(alignment: .leading, spacing: 4) {
          Text(availability.title)
            .font(.headline)

          Text(availability.explanation)
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        Spacer()
      }
      .padding(4)
    } label: {
      Label {
        Text(
          "Context-aware corrections",
          bundle: #bundle,
          comment:
            "Heading for the availability of Typover contextual corrections."
        )
      } icon: {
        Image(systemName: "apple.intelligence")
      }
    }
  }
}

extension ContextualCorrectionAvailability {
  fileprivate var title: LocalizedStringResource {
    switch self {
    case .available:
      "Ready on this Mac"
    case .unavailable(.appleIntelligenceNotEnabled):
      "Apple Intelligence is turned off"
    case .unavailable(.deviceNotEligible):
      "Unavailable on this Mac"
    case .unavailable(.modelNotReady):
      "The on-device model is preparing"
    case .unavailable(.unsupportedLanguage):
      "The current language is unsupported"
    }
  }

  fileprivate var explanation: LocalizedStringResource {
    switch self {
    case .available:
      "Completed sentences can be checked privately with Apple’s on-device model. Text is not sent to the cloud."
    case .unavailable(.appleIntelligenceNotEnabled):
      "Turn on Apple Intelligence in System Settings to check context-dependent word choices."
    case .unavailable(.deviceNotEligible):
      "Typover will continue using Apple’s spelling checker without contextual model corrections."
    case .unavailable(.modelNotReady):
      "Typover will use the model automatically after macOS finishes making it available."
    case .unavailable(.unsupportedLanguage):
      "Typover will continue using Apple’s spelling checker for the current language."
    }
  }

  fileprivate var systemImage: String {
    switch self {
    case .available:
      "checkmark.circle.fill"
    case .unavailable(.modelNotReady):
      "clock.fill"
    case .unavailable:
      "exclamationmark.circle.fill"
    }
  }

  fileprivate var tint: Color {
    switch self {
    case .available:
      .green
    case .unavailable(.modelNotReady):
      .orange
    case .unavailable:
      .secondary
    }
  }
}

private struct LearningSettingsHeader: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(
        "Statistics & Preferences",
        bundle: #bundle,
        comment: "Title of the Typover learning settings window."
      )
      .font(.largeTitle)
      .fontWeight(.semibold)

      Text(
        "See how Typover is performing and manage the choices it remembers.",
        bundle: #bundle,
        comment: "Introductory explanation in the Typover learning settings window."
      )
      .font(.body)
      .foregroundStyle(.secondary)
    }
  }
}

private struct CorrectionStatisticsSection: View {
  let statistics: CorrectionStatistics
  let sourceStatistics: [CorrectionSourceStatistics]
  let onReset: () -> Void

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 14) {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
          GridRow {
            StatisticCard(
              title: "Corrections",
              value: statistics.correctionsApplied.formatted(),
              systemImage: "text.badge.checkmark"
            )
            StatisticCard(
              title: "Override rate",
              value: statistics.overrideRate.formatted(
                .percent.precision(.fractionLength(0))
              ),
              systemImage: "arrow.uturn.backward"
            )
          }
          GridRow {
            StatisticCard(
              title: "Changed back",
              value: statistics.reverted.formatted(),
              systemImage: "arrow.counterclockwise"
            )
            StatisticCard(
              title: "Other choices",
              value: (statistics.alternativesChosen
                + statistics.manuallyEdited).formatted(),
              systemImage: "slider.horizontal.3"
            )
          }
        }

        if !sourceStatistics.isEmpty {
          Divider()

          VStack(spacing: 8) {
            ForEach(sourceStatistics) { source in
              CorrectionSourceStatisticsRow(statistics: source)
            }
          }
        }

        HStack {
          Text(
            "Statistics never contain document text.",
            bundle: #bundle,
            comment: "Privacy note below Typover correction statistics."
          )
          .font(.caption)
          .foregroundStyle(.secondary)

          Spacer()

          Button(role: .destructive, action: onReset) {
            Text(
              "Reset Statistics…",
              bundle: #bundle,
              comment: "Button that begins clearing Typover correction statistics."
            )
          }
          .accessibilityIdentifier("typover.settings.statistics.reset")
        }
      }
      .padding(4)
    } label: {
      Label {
        Text(
          "Correction activity",
          bundle: #bundle,
          comment: "Heading for the Typover correction-statistics section."
        )
      } icon: {
        Image(systemName: "chart.bar.xaxis")
      }
    }
  }
}

private struct CorrectionSourceStatisticsRow: View {
  let statistics: CorrectionSourceStatistics

  var body: some View {
    HStack(spacing: 10) {
      Label(statistics.source.title, systemImage: statistics.source.systemImage)
        .frame(maxWidth: .infinity, alignment: .leading)

      Text(
        "\(statistics.correctionsApplied.formatted()) corrections"
      )
      .foregroundStyle(.secondary)

      Text(
        statistics.overrideRate.formatted(
          .percent.precision(.fractionLength(0))
        )
      )
      .monospacedDigit()
      .frame(width: 42, alignment: .trailing)
      .help(
        Text(
          "Percentage changed back or overridden",
          bundle: #bundle,
          comment:
            "Tooltip explaining a source-specific Typover override percentage."
        )
      )

      if statistics.medianLookupMilliseconds > 0 {
        Text(
          "\(statistics.medianLookupMilliseconds.formatted(.number.precision(.fractionLength(0)))) ms"
        )
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: 66, alignment: .trailing)
        .help(
          Text(
            "Typical correction time",
            bundle: #bundle,
            comment:
              "Tooltip explaining source-specific Typover correction latency."
          )
        )
      }
    }
    .font(.callout)
  }
}

extension CorrectionSource {
  fileprivate var title: LocalizedStringResource {
    switch self {
    case .demo:
      "Demo"
    case .appleIntelligence:
      "Apple Intelligence"
    case .appleSpelling:
      "Apple Spelling"
    case .rememberedPreference:
      "Remembered choice"
    }
  }

  fileprivate var systemImage: String {
    switch self {
    case .demo:
      "hammer"
    case .appleIntelligence:
      "apple.intelligence"
    case .appleSpelling:
      "character.book.closed"
    case .rememberedPreference:
      "brain"
    }
  }
}

private struct StatisticCard: View {
  let title: LocalizedStringResource
  let value: String
  let systemImage: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.title2)
        .foregroundStyle(.tint)
        .frame(width: 28)

      VStack(alignment: .leading, spacing: 2) {
        Text(value)
          .font(.title2)
          .fontWeight(.semibold)
          .contentTransition(.numericText())

        Text(title)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
  }
}

private struct RememberedRulesSection: View {
  let rules: [RememberedCorrectionRule]
  let onRemove: (RememberedCorrectionRule.ID) -> Void

  var body: some View {
    GroupBox {
      VStack(spacing: 0) {
        if rules.isEmpty {
          RememberedRulesEmptyState()
        } else {
          ForEach(rules) { rule in
            RememberedRuleRow(
              rule: rule,
              onRemove: {
                onRemove(rule.id)
              }
            )

            if rule.id != rules.last?.id {
              Divider()
            }
          }
        }
      }
    } label: {
      Label {
        Text(
          "Remembered choices",
          bundle: #bundle,
          comment: "Heading for Typover's remembered correction choices."
        )
      } icon: {
        Image(systemName: "brain")
      }
    }
  }
}

private struct RememberedRuleRow: View {
  let rule: RememberedCorrectionRule
  let onRemove: () -> Void

  @Environment(\.locale) private var locale

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 7) {
          Text(rule.original)
            .font(.body.monospaced())

          Image(systemName: "arrow.right")
            .font(.caption)
            .foregroundStyle(.tertiary)

          switch rule.preference {
          case .preferred(let replacement):
            Text(replacement)
              .font(.body.monospaced())
          case .suppressed:
            Text(
              "Don’t correct",
              bundle: #bundle,
              comment:
                "Label for a remembered Typover preference that suppresses automatic correction."
            )
            .foregroundStyle(.secondary)
          }
        }

        if let language = rule.language {
          Text(locale.localizedString(forIdentifier: language) ?? language)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Spacer()

      Button(role: .destructive, action: onRemove) {
        Label {
          Text(
            "Forget",
            bundle: #bundle,
            comment: "Button that removes one remembered Typover correction choice."
          )
        } icon: {
          Image(systemName: "trash")
        }
      }
      .labelStyle(.iconOnly)
      .help(
        Text(
          "Forget this choice",
          bundle: #bundle,
          comment: "Tooltip for removing one remembered Typover correction choice."
        )
      )
      .accessibilityIdentifier("typover.settings.rule.remove")
    }
    .padding(.vertical, 10)
    .padding(.horizontal, 4)
  }
}

private struct RememberedRulesEmptyState: View {
  var body: some View {
    ContentUnavailableView {
      Label {
        Text(
          "No Remembered Choices",
          bundle: #bundle,
          comment: "Empty-state title when Typover has no learned correction choices."
        )
      } icon: {
        Image(systemName: "text.badge.checkmark")
      }
    } description: {
      Text(
        "Changing a correction or changing it back will create a choice here.",
        bundle: #bundle,
        comment:
          "Empty-state explanation of how Typover learns correction preferences."
      )
    }
    .frame(maxWidth: .infinity, minHeight: 120)
  }
}

private struct LearningPrivacySection: View {
  let onResetAll: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Label {
        Text(
          "Preferences and statistics stay on this Mac.",
          bundle: #bundle,
          comment: "Privacy assurance in the Typover learning settings window."
        )
      } icon: {
        Image(systemName: "lock.shield")
      }
      .font(.callout)
      .foregroundStyle(.secondary)

      Spacer()

      Button(role: .destructive, action: onResetAll) {
        Text(
          "Reset All Learning…",
          bundle: #bundle,
          comment:
            "Button that begins clearing every Typover preference and correction statistic."
        )
      }
      .accessibilityIdentifier("typover.settings.learning.reset-all")
    }
  }
}
