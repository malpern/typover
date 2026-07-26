import AppKit
import SwiftUI
import TypoverAccessibility
import TypoverAppleIntelligence
import TypoverBearAdapter
import TypoverCore
import TypoverOverlay
import TypoverRemoteIntelligence

struct LearningSettingsView: View {
  let behaviorSettings: CorrectionBehaviorSettings
  let learningStore: CorrectionLearningStore
  let credentialStore: SecretsAppCredentialStore
  let bearProbe: any BearAccessibilityProbing
  let bearEventMonitor: any BearAccessibilityEventMonitoring
  let bearCorrectionAdapter: BearCorrectionAdapter

  @State private var isConfirmingResetAll = false
  @State private var isConfirmingStatisticsReset = false
  @State private var bearAccessibilityReport: BearAccessibilityReport?
  @State private var bearEventReport: BearAccessibilityEventReport?
  @State private var isCheckingBear = false
  @State private var isObservingBear = false
  @State private var bearOverlayPreviewStatus: BearOverlayPreviewStatus = .idle
  @State private var bearOverlayController: BearAnnotationOverlayController

  init(
    behaviorSettings: CorrectionBehaviorSettings,
    learningStore: CorrectionLearningStore,
    credentialStore: SecretsAppCredentialStore = SecretsAppCredentialStore(),
    bearProbe: any BearAccessibilityProbing = BearAccessibilityProbe(),
    bearEventMonitor: any BearAccessibilityEventMonitoring =
      BearAccessibilityEventMonitor(),
    bearCorrectionAdapter: BearCorrectionAdapter = BearCorrectionAdapter()
  ) {
    self.behaviorSettings = behaviorSettings
    self.learningStore = learningStore
    self.credentialStore = credentialStore
    self.bearProbe = bearProbe
    self.bearEventMonitor = bearEventMonitor
    self.bearCorrectionAdapter = bearCorrectionAdapter
    _bearOverlayController = State(
      initialValue: BearAnnotationOverlayController(
        adapter: bearCorrectionAdapter
      )
    )
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        LearningSettingsHeader()
        ContextualModelSection(
          behaviorSettings: behaviorSettings,
          credentialStore: credentialStore
        )
        CorrectionBehaviorSection(
          behaviorSettings: behaviorSettings
        )
        BearCompatibilitySection(
          report: bearAccessibilityReport,
          eventReport: bearEventReport,
          isChecking: isCheckingBear,
          isObserving: isObservingBear,
          overlayPreviewStatus: bearOverlayPreviewStatus,
          onCheck: checkBearCompatibility,
          onObserve: observeBearEvents,
          onPreviewOverlay: previewBearOverlay,
          onStopOverlayPreview: stopBearOverlayPreview
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

  private func checkBearCompatibility() {
    isCheckingBear = true
    let returnApplication = NSRunningApplication.current
    let bearApplication = NSRunningApplication.runningApplications(
      withBundleIdentifier: BearAccessibilityProbe.bearBundleIdentifier
    ).first
    bearApplication?.activate(options: [.activateAllWindows])

    Task {
      if bearApplication != nil {
        try? await Task.sleep(for: .milliseconds(500))
      }
      let report = await Task.detached(priority: .userInitiated) {
        bearProbe.run()
      }.value
      returnApplication.activate(options: [.activateAllWindows])
      bearAccessibilityReport = report
      isCheckingBear = false
    }
  }

  private func observeBearEvents() {
    isObservingBear = true
    bearEventReport = nil
    let returnApplication = NSRunningApplication.current
    let bearApplication = NSRunningApplication.runningApplications(
      withBundleIdentifier: BearAccessibilityProbe.bearBundleIdentifier
    ).first
    bearApplication?.activate(options: [.activateAllWindows])

    Task {
      if bearApplication != nil {
        try? await Task.sleep(for: .milliseconds(500))
      }
      let report = await Task.detached(priority: .userInitiated) {
        bearEventMonitor.observe(for: 5)
      }.value
      returnApplication.activate(options: [.activateAllWindows])
      bearEventReport = report
      isObservingBear = false
    }
  }

  private func previewBearOverlay() {
    bearOverlayPreviewStatus = .preparing
    let returnApplication = NSRunningApplication.current
    let bearApplication = NSRunningApplication.runningApplications(
      withBundleIdentifier: BearAccessibilityProbe.bearBundleIdentifier
    ).first
    bearApplication?.activate(options: [.activateAllWindows])

    Task {
      guard bearApplication != nil else {
        bearOverlayPreviewStatus = .bearUnavailable
        return
      }
      try? await Task.sleep(for: .milliseconds(400))
      let probe = bearProbe
      let report = await Task.detached(priority: .userInitiated) {
        probe.run()
      }.value
      guard let selectedRange = report.selectedRange,
        selectedRange.length == 3
      else {
        returnApplication.activate(options: [.activateAllWindows])
        bearOverlayPreviewStatus = .selectExactTypo
        return
      }

      let adapter = bearCorrectionAdapter
      let application = await Task.detached(priority: .userInitiated) {
        adapter.apply(
          original: "teh",
          replacement: "the",
          at: selectedRange
        )
      }.value
      guard application.report.isVerifiedApplication else {
        returnApplication.activate(options: [.activateAllWindows])
        bearOverlayPreviewStatus = .selectionDidNotMatch
        return
      }

      bearOverlayController.track(application)
      bearOverlayPreviewStatus = .active
    }
  }

  private func stopBearOverlayPreview() {
    bearOverlayController.stop()
    bearOverlayPreviewStatus = .idle
  }
}

enum BearOverlayPreviewStatus: Equatable {
  case idle
  case preparing
  case active
  case bearUnavailable
  case selectExactTypo
  case selectionDidNotMatch
}

private struct CorrectionBehaviorSection: View {
  let behaviorSettings: CorrectionBehaviorSettings

  var body: some View {
    @Bindable var behaviorSettings = behaviorSettings

    GroupBox {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 8) {
          Text(
            "Correction scope",
            bundle: #bundle,
            comment:
              "Label above the Typover contextual-correction scope picker."
          )
          .font(.headline)

          Picker(
            String(
              localized: "Correction scope",
              bundle: #bundle,
              comment:
                "Accessibility label for the Typover correction-scope picker."
            ),
            selection: $behaviorSettings.contextualScope
          ) {
            Text(
              "Careful",
              bundle: #bundle,
              comment:
                "Conservative Typover correction-scope option."
            )
            .tag(ContextualCorrectionScope.careful)

            Text(
              "Comprehensive",
              bundle: #bundle,
              comment:
                "Broader Typover correction-scope option covering grammar and punctuation."
            )
            .tag(ContextualCorrectionScope.comprehensive)
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .accessibilityIdentifier("typover.settings.correction-scope")

          Text(behaviorSettings.contextualScope.explanation)
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        Divider()

        VStack(alignment: .leading, spacing: 5) {
          Toggle(
            isOn: $behaviorSettings.allowsSentenceRewrites
          ) {
            Text(
              "Allow sentence rewrites",
              bundle: #bundle,
              comment:
                "Setting that permits Typover's selected model to rephrase a completed sentence."
            )
          }
          .disabled(
            behaviorSettings.contextualScope != .comprehensive
          )
          .accessibilityIdentifier(
            "typover.settings.allow-sentence-rewrites"
          )

          if behaviorSettings.contextualScope == .comprehensive {
            Text(
              "The selected model may rephrase one completed sentence for clarity while preserving its meaning and tone. The rewrite remains visible, reversible, and undoable.",
              bundle: #bundle,
              comment:
                "Explanation below the enabled sentence-rewrite setting."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.leading, 20)
          } else {
            Text(
              behaviorSettings.allowsSentenceRewrites
                ? "Sentence rewriting is paused in Careful. Choose Comprehensive to use it."
                : "Choose Comprehensive to make sentence rewriting available.",
              bundle: #bundle,
              comment:
                "Explanation below the unavailable sentence-rewrite setting."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.leading, 20)
          }
        }
      }
      .padding(4)
    } label: {
      Label {
        Text(
          "Automatic correction",
          bundle: #bundle,
          comment:
            "Heading for Typover's automatic-correction behavior settings."
        )
      } icon: {
        Image(systemName: "slider.horizontal.3")
      }
    }
  }
}

extension ContextualCorrectionScope {
  fileprivate var explanation: LocalizedStringResource {
    switch self {
    case .careful:
      "Correct spelling, capitalization, apostrophes, and unambiguous contextual mistakes."
    case .comprehensive:
      "Also correct objective punctuation and grammar, with up to three visible changes in a completed sentence."
    }
  }
}

private enum ProviderCredentialStatus: Equatable {
  case checking
  case available
  case missing
}

private struct ContextualModelSection: View {
  let behaviorSettings: CorrectionBehaviorSettings
  let credentialStore: SecretsAppCredentialStore

  @State private var credentialStatus = ProviderCredentialStatus.checking
  @State private var didFailToOpenSecretsApp = false

  var body: some View {
    @Bindable var behaviorSettings = behaviorSettings

    GroupBox {
      VStack(alignment: .leading, spacing: 14) {
        LabeledContent {
          Picker(
            String(
              localized: "Writing model",
              bundle: #bundle,
              comment:
                "Accessibility label for the Typover contextual-model picker."
            ),
            selection: $behaviorSettings.contextualModel
          ) {
            ForEach(ContextualCorrectionModel.allCases, id: \.self) { model in
              Text(model.title)
                .tag(model)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .accessibilityIdentifier("typover.settings.contextual-model")
        } label: {
          Text(
            "Model",
            bundle: #bundle,
            comment: "Label beside Typover's contextual writing-model picker."
          )
        }

        Divider()

        if behaviorSettings.contextualModel == .apple {
          AppleModelStatus(
            availability: AppleContextualModelAvailability.current(
              for: NSSpellChecker.shared.userPreferredLanguages.first
            )
          )
        } else {
          RemoteModelStatus(
            model: behaviorSettings.contextualModel,
            credentialStatus: credentialStatus,
            didFailToOpenSecretsApp: didFailToOpenSecretsApp,
            onManageCredential: manageCredential,
            onRefresh: {
              Task {
                await refreshCredentialStatus()
              }
            }
          )
        }
      }
      .padding(4)
    } label: {
      Label {
        Text(
          "Writing model",
          bundle: #bundle,
          comment:
            "Heading for Typover's contextual writing-model settings."
        )
      } icon: {
        Image(systemName: "cpu")
      }
    }
    .task(id: behaviorSettings.contextualModel) {
      await refreshCredentialStatus()
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: NSApplication.didBecomeActiveNotification
      )
    ) { _ in
      Task {
        await refreshCredentialStatus()
      }
    }
  }

  private func manageCredential() {
    didFailToOpenSecretsApp = false
    SecretsAppLauncher.open(for: behaviorSettings.contextualModel) { error in
      didFailToOpenSecretsApp = error != nil
    }
  }

  private func refreshCredentialStatus() async {
    let model = behaviorSettings.contextualModel
    guard model != .apple else {
      credentialStatus = .checking
      return
    }
    credentialStatus = .checking
    let isAvailable = await credentialStore.hasCredential(
      named: model.credentialName
    )
    guard model == behaviorSettings.contextualModel else {
      return
    }
    credentialStatus = isAvailable ? .available : .missing
  }
}

private struct AppleModelStatus: View {
  let availability: ContextualCorrectionAvailability

  var body: some View {
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
  }
}

private struct RemoteModelStatus: View {
  let model: ContextualCorrectionModel
  let credentialStatus: ProviderCredentialStatus
  let didFailToOpenSecretsApp: Bool
  let onManageCredential: () -> Void
  let onRefresh: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: credentialStatus.systemImage)
          .font(.title2)
          .foregroundStyle(credentialStatus.tint)
          .frame(width: 28)

        VStack(alignment: .leading, spacing: 4) {
          Text(credentialStatus.title)
            .font(.headline)

          Text(model.remoteExplanation)
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        Spacer()
      }

      HStack {
        Button(action: onManageCredential) {
          Text(
            credentialStatus == .available
              ? "Replace API Key…"
              : "Add API Key…",
            bundle: #bundle,
            comment:
              "Button that opens Add Secret to configure the selected cloud model credential."
          )
        }
        .accessibilityIdentifier("typover.settings.model.manage-key")

        Button(action: onRefresh) {
          Text(
            "Refresh",
            bundle: #bundle,
            comment:
              "Button that refreshes the selected cloud model credential status."
          )
        }
        .accessibilityIdentifier("typover.settings.model.refresh-key")

        Spacer()

        Text(
          "Managed by Add Secret",
          bundle: #bundle,
          comment:
            "Note explaining which app securely manages cloud provider credentials."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Label {
        Text(model.privacyNotice)
      } icon: {
        Image(systemName: "network")
      }
      .font(.callout)
      .foregroundStyle(.orange)

      if didFailToOpenSecretsApp {
        Label {
          Text(
            "Add Secret could not be opened. Make sure it is installed in Applications.",
            bundle: #bundle,
            comment:
              "Error shown when Typover cannot launch Add Secret for a provider key."
          )
        } icon: {
          Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.callout)
        .foregroundStyle(.red)
      }
    }
  }
}

extension ContextualCorrectionModel {
  fileprivate var title: LocalizedStringResource {
    switch self {
    case .apple:
      "Apple Intelligence (On Device)"
    case .openAI:
      "GPT-5.6 Terra (OpenAI)"
    case .anthropic:
      "Claude Sonnet 5 (Anthropic)"
    }
  }

  fileprivate var remoteExplanation: LocalizedStringResource {
    switch self {
    case .apple:
      ""
    case .openAI:
      "Uses GPT-5.6 Terra for contextual corrections and optional sentence rewrites. An OpenAI API key is required."
    case .anthropic:
      "Uses Claude Sonnet 5 for contextual corrections and optional sentence rewrites. An Anthropic API key is required."
    }
  }

  fileprivate var privacyNotice: LocalizedStringResource {
    switch self {
    case .apple:
      ""
    case .openAI:
      "Completed sentences are sent to OpenAI when context checking runs. Provider charges may apply."
    case .anthropic:
      "Completed sentences are sent to Anthropic when context checking runs. Provider charges may apply."
    }
  }
}

extension ProviderCredentialStatus {
  fileprivate var title: LocalizedStringResource {
    switch self {
    case .checking:
      "Checking API key…"
    case .available:
      "API key available"
    case .missing:
      "API key required"
    }
  }

  fileprivate var systemImage: String {
    switch self {
    case .checking:
      "clock.fill"
    case .available:
      "checkmark.circle.fill"
    case .missing:
      "exclamationmark.circle.fill"
    }
  }

  fileprivate var tint: Color {
    switch self {
    case .checking:
      .orange
    case .available:
      .green
    case .missing:
      .secondary
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
        "Typover Settings",
        bundle: #bundle,
        comment: "Title of the Typover settings window."
      )
      .font(.largeTitle)
      .fontWeight(.semibold)

      Text(
        "Choose how Typover corrects your writing, see how it is performing, and manage remembered choices.",
        bundle: #bundle,
        comment: "Introductory explanation in the Typover settings window."
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
    case .appleIntelligenceRewrite:
      "Apple Intelligence Rewrite"
    case .appleSpelling:
      "Apple Spelling"
    case .openAI:
      "OpenAI"
    case .openAIRewrite:
      "OpenAI Rewrite"
    case .anthropic:
      "Anthropic"
    case .anthropicRewrite:
      "Anthropic Rewrite"
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
    case .appleIntelligenceRewrite:
      "wand.and.sparkles"
    case .appleSpelling:
      "character.book.closed"
    case .openAI:
      "cloud"
    case .openAIRewrite:
      "wand.and.sparkles"
    case .anthropic:
      "cloud"
    case .anthropicRewrite:
      "wand.and.sparkles"
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
          "Learning preferences and statistics stay on this Mac.",
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
