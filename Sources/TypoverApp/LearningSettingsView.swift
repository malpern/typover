import AppKit
import SwiftUI
import TypoverAccessibility
import TypoverAppleIntelligence
import TypoverBearAdapter
import TypoverCore
import TypoverRemoteIntelligence

struct LearningSettingsView: View {
  static let selectedPaneDefaultsKey = "settings-selected-pane"

  let behaviorSettings: CorrectionBehaviorSettings
  let learningStore: CorrectionLearningStore
  let credentialStore: SecretsAppCredentialStore
  let bearProbe: any BearAccessibilityProbing
  let bearEventMonitor: any BearAccessibilityEventMonitoring
  let bearOverlayPreviewCoordinator: BearOverlayPreviewCoordinator
  let bearAutomaticCorrectionCoordinator: BearAutomaticCorrectionCoordinator

  @State private var isConfirmingResetAll = false
  @State private var isConfirmingStatisticsReset = false
  @State private var bearAccessibilityReport: BearAccessibilityReport?
  @State private var bearEventReport: BearAccessibilityEventReport?
  @State private var isCheckingBear = false
  @State private var isObservingBear = false
  @AppStorage(Self.selectedPaneDefaultsKey) private var selectedPane =
    SettingsPane.general.rawValue

  init(
    behaviorSettings: CorrectionBehaviorSettings,
    learningStore: CorrectionLearningStore,
    credentialStore: SecretsAppCredentialStore = SecretsAppCredentialStore(),
    bearProbe: any BearAccessibilityProbing = BearAccessibilityProbe(),
    bearEventMonitor: any BearAccessibilityEventMonitoring =
      BearAccessibilityEventMonitor(),
    bearCorrectionAdapter: BearCorrectionAdapter = BearCorrectionAdapter(),
    bearOverlayPreviewCoordinator: BearOverlayPreviewCoordinator? = nil,
    bearAutomaticCorrectionCoordinator:
    BearAutomaticCorrectionCoordinator? = nil
  ) {
    self.behaviorSettings = behaviorSettings
    self.learningStore = learningStore
    self.credentialStore = credentialStore
    self.bearProbe = bearProbe
    self.bearEventMonitor = bearEventMonitor
    self.bearOverlayPreviewCoordinator =
      bearOverlayPreviewCoordinator
        ?? BearOverlayPreviewCoordinator(
          bearProbe: bearProbe,
          bearCorrectionAdapter: bearCorrectionAdapter
        )
    self.bearAutomaticCorrectionCoordinator =
      bearAutomaticCorrectionCoordinator
        ?? BearAutomaticCorrectionCoordinator(
          learningStore: learningStore,
          correctionAdapter: bearCorrectionAdapter
        )
  }

  var body: some View {
    Group {
      switch currentPane {
      case .general:
        GeneralSettingsPane(
          behaviorSettings: behaviorSettings,
          credentialStore: credentialStore
        )
      case .bear:
        BearSettingsPane(
          behaviorSettings: behaviorSettings,
          accessibilityReport: bearAccessibilityReport,
          eventReport: bearEventReport,
          isChecking: isCheckingBear,
          isObserving: isObservingBear,
          automaticCorrectionCoordinator:
          bearAutomaticCorrectionCoordinator,
          overlayPreviewCoordinator: bearOverlayPreviewCoordinator,
          onCheck: checkBearCompatibility,
          onObserve: observeBearEvents
        )
      case .learning:
        LearningSettingsPane(
          learningStore: learningStore,
          onResetStatistics: { isConfirmingStatisticsReset = true }
        )
      case .privacy:
        PrivacySettingsPane(
          onResetAll: { isConfirmingResetAll = true }
        )
      }
    }
    .frame(width: 680, height: 540)
    .background(
      SettingsWindowConfigurationView(
        title: "Typover Settings",
        selection: $selectedPane
      )
    )
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
      Button(role: .cancel) {} label: {
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
      Button(role: .cancel) {} label: {
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

  private var currentPane: SettingsPane {
    SettingsPane(rawValue: selectedPane) ?? .general
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
}

private enum SettingsPane: String, CaseIterable, Identifiable {
  case general
  case bear
  case learning
  case privacy

  var id: String { rawValue }

  var title: String {
    switch self {
    case .general: "General"
    case .bear: "Bear"
    case .learning: "Learning"
    case .privacy: "Privacy"
    }
  }

  var systemImage: String {
    switch self {
    case .general: "gearshape"
    case .bear: "pawprint"
    case .learning: "brain"
    case .privacy: "hand.raised"
    }
  }

  var toolbarIdentifier: NSToolbarItem.Identifier {
    NSToolbarItem.Identifier("typover.settings.pane.\(rawValue)")
  }
}

private struct SettingsWindowConfigurationView: NSViewRepresentable {
  let title: String

  @Binding var selection: String

  func makeCoordinator() -> Coordinator {
    Coordinator(selection: $selection)
  }

  func makeNSView(context: Context) -> ConfigurationView {
    ConfigurationView(coordinator: context.coordinator)
  }

  func updateNSView(_ nsView: ConfigurationView, context: Context) {
    context.coordinator.selection = $selection
    context.coordinator.updateSelection()
    nsView.title = title
    nsView.configureWindow()
  }

  final class ConfigurationView: NSView {
    var title: String
    let coordinator: Coordinator

    init(coordinator: Coordinator) {
      title = ""
      self.coordinator = coordinator
      super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      configureWindow()
    }

    override func viewWillDraw() {
      super.viewWillDraw()
      configureWindow()
    }

    func configureWindow() {
      guard let window else { return }
      coordinator.installToolbar(on: window)
      window.title = title
      window.titleVisibility = .visible
      window.toolbarStyle = .preference
      window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
      window.standardWindowButton(.zoomButton)?.isEnabled = false
    }
  }

  @MainActor
  final class Coordinator: NSObject, NSToolbarDelegate {
    private static let toolbarIdentifier = NSToolbar.Identifier(
      "typover.settings.toolbar"
    )

    var selection: Binding<String>
    let toolbar: NSToolbar

    init(selection: Binding<String>) {
      self.selection = selection
      toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
      super.init()
      toolbar.delegate = self
      toolbar.displayMode = .iconAndLabel
      toolbar.sizeMode = .regular
      toolbar.allowsUserCustomization = false
      toolbar.autosavesConfiguration = false
    }

    func installToolbar(on window: NSWindow) {
      if window.toolbar !== toolbar {
        window.toolbar = toolbar
      }
      updateSelection()
    }

    @objc func selectPane(_ sender: NSToolbarItem) {
      guard let pane = SettingsPane.allCases.first(where: {
        $0.toolbarIdentifier == sender.itemIdentifier
      }) else { return }
      selection.wrappedValue = pane.rawValue
      updateSelection()
    }

    func updateSelection() {
      let pane = SettingsPane(rawValue: selection.wrappedValue) ?? .general
      toolbar.selectedItemIdentifier = pane.toolbarIdentifier
    }

    func toolbar(
      _: NSToolbar,
      itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
      willBeInsertedIntoToolbar _: Bool
    ) -> NSToolbarItem? {
      guard let pane = SettingsPane.allCases.first(where: {
        $0.toolbarIdentifier == itemIdentifier
      }) else { return nil }

      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      item.label = pane.title
      item.paletteLabel = pane.title
      item.toolTip = pane.title
      item.image = NSImage(
        systemSymbolName: pane.systemImage,
        accessibilityDescription: pane.title
      )
      item.target = self
      item.action = #selector(selectPane(_:))
      item.visibilityPriority = .high
      return item
    }

    func toolbarDefaultItemIdentifiers(
      _: NSToolbar
    ) -> [NSToolbarItem.Identifier] {
      SettingsPane.allCases.map(\.toolbarIdentifier)
    }

    func toolbarAllowedItemIdentifiers(
      _: NSToolbar
    ) -> [NSToolbarItem.Identifier] {
      SettingsPane.allCases.map(\.toolbarIdentifier)
    }

    func toolbarSelectableItemIdentifiers(
      _: NSToolbar
    ) -> [NSToolbarItem.Identifier] {
      SettingsPane.allCases.map(\.toolbarIdentifier)
    }

    func toolbarImmovableItemIdentifiers(
      _: NSToolbar
    ) -> Set<NSToolbarItem.Identifier> {
      Set(SettingsPane.allCases.map(\.toolbarIdentifier))
    }
  }
}

private struct GeneralSettingsPane: View {
  let behaviorSettings: CorrectionBehaviorSettings
  let credentialStore: SecretsAppCredentialStore

  var body: some View {
    Form {
      CorrectionBehaviorSection(behaviorSettings: behaviorSettings)
      ContextualModelSection(
        behaviorSettings: behaviorSettings,
        credentialStore: credentialStore
      )
    }
    .formStyle(.grouped)
  }
}

private struct BearSettingsPane: View {
  let behaviorSettings: CorrectionBehaviorSettings
  let accessibilityReport: BearAccessibilityReport?
  let eventReport: BearAccessibilityEventReport?
  let isChecking: Bool
  let isObserving: Bool
  let automaticCorrectionCoordinator: BearAutomaticCorrectionCoordinator
  let overlayPreviewCoordinator: BearOverlayPreviewCoordinator
  let onCheck: () -> Void
  let onObserve: () -> Void

  var body: some View {
    Form {
      BearCompatibilitySection(
        report: accessibilityReport,
        eventReport: eventReport,
        isChecking: isChecking,
        isObserving: isObserving,
        automaticCorrectionEnabled:
        behaviorSettings.bearAutomaticCorrectionEnabled,
        automaticCorrectionStatus: automaticCorrectionCoordinator.status,
        automaticCorrectionDiagnostics: automaticCorrectionCoordinator.diagnostics,
        overlayPreviewStatus: overlayPreviewCoordinator.status,
        onAutomaticCorrectionChanged: { enabled in
          behaviorSettings.bearAutomaticCorrectionEnabled = enabled
          automaticCorrectionCoordinator.setEnabled(enabled)
        },
        onCheck: onCheck,
        onObserve: onObserve,
        onPreviewOverlay: overlayPreviewCoordinator.previewSelectedTypo,
        onStopOverlayPreview: overlayPreviewCoordinator.stopPreview
      )
      TypoverPermissionsSettingsSection()
    }
    .formStyle(.grouped)
  }
}

private struct LearningSettingsPane: View {
  let learningStore: CorrectionLearningStore
  let onResetStatistics: () -> Void

  var body: some View {
    Form {
      CorrectionStatisticsSection(
        statistics: learningStore.statistics(),
        sourceStatistics: learningStore.statisticsBySource(),
        onReset: onResetStatistics
      )
      RememberedRulesSection(
        rules: learningStore.rememberedRules,
        onAdd: learningStore.addManualMapping,
        onRemove: learningStore.removeRule
      )
    }
    .formStyle(.grouped)
  }
}

private struct PrivacySettingsPane: View {
  let onResetAll: () -> Void

  var body: some View {
    Form {
      Section {
        Label {
          Text(
            "Spelling checks, remembered choices, and correction statistics stay on this Mac when Apple Intelligence is selected.",
            bundle: #bundle,
            comment: "Local-first privacy summary in Typover Settings."
          )
        } icon: {
          Image(systemName: "lock.shield")
            .foregroundStyle(.green)
        }

        Text(
          "Choosing OpenAI or Anthropic sends completed sentences to that provider only when contextual checking runs.",
          bundle: #bundle,
          comment: "Cloud model privacy summary in Typover Settings."
        )
        .foregroundStyle(.secondary)
      } header: {
        Text("Writing Privacy", bundle: #bundle)
      }

      BearDiagnosticsPrivacySection()

      Section {
        Button(role: .destructive, action: onResetAll) {
          Text("Reset All Learning…", bundle: #bundle)
        }
        .accessibilityIdentifier("typover.settings.learning.reset-all")
      } footer: {
        Text(
          "Removes remembered correction choices and correction statistics from this Mac.",
          bundle: #bundle
        )
      }
    }
    .formStyle(.grouped)
  }
}

enum BearOverlayPreviewStatus: Equatable {
  case idle
  case preparing
  case active
  case accessibilityPermissionRequired
  case bearUnavailable
  case editorUnavailable
  case selectExactTypo
  case selectionDidNotMatch
  case correctionFailed(BearExactRangeReplacementStatus)

  static func failure(
    for report: BearAccessibilityReport
  ) -> BearOverlayPreviewStatus? {
    switch report.status {
    case .ready:
      guard report.selectedRange?.length == 3 else {
        return .selectExactTypo
      }
      return nil
    case .accessibilityPermissionRequired:
      return .accessibilityPermissionRequired
    case .bearNotRunning:
      return .bearUnavailable
    case .focusedEditorUnavailable, .focusedElementIsNotTextArea,
         .editorAvailableButNotFocused:
      return .editorUnavailable
    }
  }

  static func failure(
    for report: BearExactRangeReplacementReport
  ) -> BearOverlayPreviewStatus? {
    guard !report.isVerifiedApplication else {
      return nil
    }
    switch report.status {
    case .accessibilityPermissionRequired:
      return .accessibilityPermissionRequired
    case .bearNotRunning:
      return .bearUnavailable
    case .focusedEditorUnavailable, .selectedRangeUnavailable:
      return .editorUnavailable
    case .preconditionFailed:
      return .selectionDidNotMatch
    default:
      return .correctionFailed(report.status)
    }
  }
}

private struct CorrectionBehaviorSection: View {
  let behaviorSettings: CorrectionBehaviorSettings

  var body: some View {
    @Bindable var behaviorSettings = behaviorSettings

    Section {
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
          comment: "Conservative Typover correction-scope option."
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
      .pickerStyle(.segmented)
      .accessibilityIdentifier("typover.settings.correction-scope")

      LabeledContent {
        Picker(
          String(
            localized: "Correction marks",
            bundle: #bundle,
            comment:
            "Accessibility label for the Typover correction-mark visibility picker."
          ),
          selection: $behaviorSettings.correctionMarkVisibility
        ) {
          ForEach(CorrectionMarkVisibility.allCases, id: \.self) { visibility in
            Text(visibility.title)
              .tag(visibility)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .accessibilityIdentifier("typover.settings.correction-mark-visibility")
      } label: {
        Text(
          "Correction marks",
          bundle: #bundle,
          comment: "Label beside the correction-mark visibility setting."
        )
      }

      Toggle(
        isOn: $behaviorSettings.allowsSentenceRewrites
      ) {
        VStack(alignment: .leading, spacing: 2) {
          Text(
            "Allow sentence rewrites",
            bundle: #bundle,
            comment:
            "Setting that permits Typover's selected model to rephrase a completed sentence."
          )
          Text(
            "Rephrase one completed sentence for clarity while preserving meaning and tone.",
            bundle: #bundle,
            comment: "Concise explanation for Typover sentence rewrites."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }
      .disabled(behaviorSettings.contextualScope != .comprehensive)
      .accessibilityIdentifier("typover.settings.allow-sentence-rewrites")
    } header: {
      Text(
        "Automatic Correction",
        bundle: #bundle,
        comment: "Heading for Typover's automatic-correction behavior settings."
      )
    } footer: {
      VStack(alignment: .leading, spacing: 4) {
        Text(behaviorSettings.contextualScope.explanation)
        Text(behaviorSettings.correctionMarkVisibility.explanation)
      }
    }
  }
}

private extension CorrectionMarkVisibility {
  var title: LocalizedStringResource {
    switch self {
    case .briefAndContextual:
      "Brief + contextual"
    case .alwaysVisible:
      "Always visible"
    }
  }

  var explanation: LocalizedStringResource {
    switch self {
    case .briefAndContextual:
      "Marks fade quickly and return when you review or move the insertion point into that sentence."
    case .alwaysVisible:
      "Every unresolved automatic correction remains marked."
    }
  }
}

private extension ContextualCorrectionScope {
  var explanation: LocalizedStringResource {
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

    Section {
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
    } header: {
      Text(
        "Writing Model",
        bundle: #bundle,
        comment: "Heading for Typover's contextual writing-model settings."
      )
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
        .accessibilityHidden(true)

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
          .accessibilityHidden(true)

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

private extension ContextualCorrectionModel {
  var title: LocalizedStringResource {
    switch self {
    case .apple:
      "Apple Intelligence (On Device)"
    case .openAI:
      "GPT-5.6 Terra (OpenAI)"
    case .anthropic:
      "Claude Sonnet 5 (Anthropic)"
    }
  }

  var remoteExplanation: LocalizedStringResource {
    switch self {
    case .apple:
      ""
    case .openAI:
      "Uses GPT-5.6 Terra for contextual corrections and optional sentence rewrites. An OpenAI API key is required."
    case .anthropic:
      "Uses Claude Sonnet 5 for contextual corrections and optional sentence rewrites. An Anthropic API key is required."
    }
  }

  var privacyNotice: LocalizedStringResource {
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

private extension ProviderCredentialStatus {
  var title: LocalizedStringResource {
    switch self {
    case .checking:
      "Checking API key…"
    case .available:
      "API key available"
    case .missing:
      "API key required"
    }
  }

  var systemImage: String {
    switch self {
    case .checking:
      "clock.fill"
    case .available:
      "checkmark.circle.fill"
    case .missing:
      "exclamationmark.circle.fill"
    }
  }

  var tint: Color {
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

private extension ContextualCorrectionAvailability {
  var title: LocalizedStringResource {
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

  var explanation: LocalizedStringResource {
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

  var systemImage: String {
    switch self {
    case .available:
      "checkmark.circle.fill"
    case .unavailable(.modelNotReady):
      "clock.fill"
    case .unavailable:
      "exclamationmark.circle.fill"
    }
  }

  var tint: Color {
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

private struct CorrectionStatisticsSection: View {
  let statistics: CorrectionStatistics
  let sourceStatistics: [CorrectionSourceStatistics]
  let onReset: () -> Void

  var body: some View {
    Section {
      LabeledContent("Corrections") {
        Text(statistics.correctionsApplied, format: .number)
          .monospacedDigit()
      }
      LabeledContent("Changed back") {
        Text(statistics.reverted, format: .number)
          .monospacedDigit()
      }
      LabeledContent("Other choices") {
        Text(
          statistics.alternativesChosen + statistics.manuallyEdited,
          format: .number
        )
        .monospacedDigit()
      }
      LabeledContent("Override rate") {
        Text(
          statistics.overrideRate,
          format: .percent.precision(.fractionLength(0))
        )
        .monospacedDigit()
      }

      if !sourceStatistics.isEmpty {
        DisclosureGroup("By Source") {
          ForEach(sourceStatistics) { source in
            CorrectionSourceStatisticsRow(statistics: source)
          }
        }
      }

      Button(role: .destructive, action: onReset) {
        Text(
          "Reset Statistics…",
          bundle: #bundle,
          comment: "Button that begins clearing Typover correction statistics."
        )
      }
      .accessibilityIdentifier("typover.settings.statistics.reset")
    } header: {
      Text(
        "Correction Activity",
        bundle: #bundle,
        comment: "Heading for the Typover correction-statistics section."
      )
    } footer: {
      Text(
        "Statistics never contain document text.",
        bundle: #bundle,
        comment: "Privacy note below Typover correction statistics."
      )
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
        correctionCountLabel(statistics.correctionsApplied)
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

func correctionCountLabel(_ count: Int) -> LocalizedStringResource {
  if count == 1 {
    return LocalizedStringResource(
      "\(count) correction",
      bundle: #bundle,
      comment: "A source-specific count containing exactly one correction."
    )
  }

  return LocalizedStringResource(
    "\(count) corrections",
    bundle: #bundle,
    comment: "A source-specific count containing zero or multiple corrections."
  )
}

private extension CorrectionSource {
  var title: LocalizedStringResource {
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

  var systemImage: String {
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

private struct RememberedRulesSection: View {
  let rules: [RememberedCorrectionRule]
  let onAdd: (ManualCorrectionMapping) -> Void
  let onRemove: (RememberedCorrectionRule.ID) -> Void
  @State private var isAddingMapping = false
  @State private var forgottenRuleConfirmation:
    ForgottenRuleConfirmation?

  var body: some View {
    Group {
      Section {
        HStack {
          Text(
            "Create a correction Typover applies whenever the typed text matches.",
            bundle: #bundle,
            comment: "Short description beside the button for manually adding a Typover correction mapping."
          )
          .foregroundStyle(.secondary)

          Spacer()

          Button {
            isAddingMapping = true
          } label: {
            Label {
              Text(
                "Add Mapping…",
                bundle: #bundle,
                comment: "Button that opens the form for adding a manual Typover correction mapping."
              )
            } icon: {
              Image(systemName: "plus")
            }
          }
          .accessibilityIdentifier("typover.settings.rule.add")
        }

        if rules.isEmpty {
          RememberedRulesEmptyState()
        } else {
          ForEach(rules) { rule in
            RememberedRuleRow(
              rule: rule,
              onRemove: {
                onRemove(rule.id)
                withAnimation(.easeOut(duration: 0.18)) {
                  forgottenRuleConfirmation =
                    ForgottenRuleConfirmation(original: rule.original)
                }
              }
            )
          }
        }
      } header: {
        Text(
          "Remembered Corrections",
          bundle: #bundle,
          comment: "Heading for Typover's remembered correction preferences."
        )
      } footer: {
        Text(
          "Learned choices come only from edits tied to one marked correction. Manual mappings can contain words or phrases.",
          bundle: #bundle,
          comment:
          "Safety explanation for Typover's local correction preference learning."
        )
      }

      if let forgottenRuleConfirmation {
        Section {
          ForgottenRuleConfirmationView(
            original: forgottenRuleConfirmation.original
          )
          .transition(.move(edge: .top).combined(with: .opacity))
        }
      }
    }
    .task(id: forgottenRuleConfirmation?.id) {
      guard let confirmationID = forgottenRuleConfirmation?.id else {
        return
      }
      do {
        try await Task.sleep(for: .seconds(4))
      } catch {
        return
      }
      guard forgottenRuleConfirmation?.id == confirmationID else {
        return
      }
      withAnimation(.easeOut(duration: 0.2)) {
        forgottenRuleConfirmation = nil
      }
    }
    .sheet(isPresented: $isAddingMapping) {
      AddCorrectionMappingView(onAdd: onAdd)
    }
  }
}

private struct AddCorrectionMappingView: View {
  private static let availableLanguages =
    NSSpellChecker.shared.availableLanguages

  let onAdd: (ManualCorrectionMapping) -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.locale) private var locale
  @FocusState private var focusedField: Field?
  @State private var original = ""
  @State private var replacement = ""
  @State private var language = ""
  @State private var validationError:
    ManualCorrectionMapping.ValidationError?

  private enum Field {
    case original
    case replacement
  }

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section {
          TextField(
            "When I type",
            text: $original,
            prompt: Text("teh", bundle: #bundle)
          )
          .focused($focusedField, equals: .original)
          .accessibilityIdentifier("typover.settings.mapping.original")

          TextField(
            "Replace it with",
            text: $replacement,
            prompt: Text("the", bundle: #bundle)
          )
          .focused($focusedField, equals: .replacement)
          .accessibilityIdentifier("typover.settings.mapping.replacement")
        } header: {
          Text("Correction", bundle: #bundle)
        } footer: {
          Text(
            "Words, phrases, capitalization, accents, and punctuation are supported.",
            bundle: #bundle,
            comment: "Supported content explanation in the manual correction mapping form."
          )
        }

        Section {
          Picker("Language", selection: $language) {
            Text(
              "Any Language",
              bundle: #bundle,
              comment: "Option that makes a manual Typover mapping apply regardless of writing language."
            )
            .tag("")

            ForEach(localizedLanguages, id: \.identifier) { option in
              Text(option.name)
                .tag(option.identifier)
            }
          }
          .accessibilityIdentifier("typover.settings.mapping.language")
        } header: {
          Text("Scope", bundle: #bundle)
        } footer: {
          Text(
            "Any Language is useful for names, abbreviations, and personal shorthand.",
            bundle: #bundle,
            comment: "Explanation of the language scope for a manual correction mapping."
          )
        }

        if let validationError {
          Section {
            Label {
              Text(validationError.message)
            } icon: {
              Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            }
            .accessibilityIdentifier("typover.settings.mapping.error")
          }
        }
      }
      .formStyle(.grouped)

      Divider()

      HStack {
        Spacer()

        Button("Cancel", role: .cancel) {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        .accessibilityIdentifier("typover.settings.mapping.cancel")

        Button {
          addMapping()
        } label: {
          Text(
            "Add Mapping",
            bundle: #bundle,
            comment: "Default button that saves a manual Typover correction mapping."
          )
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!hasRequiredValues)
        .accessibilityIdentifier("typover.settings.mapping.save")
      }
      .padding(16)
    }
    .frame(width: 500, height: 320)
    .navigationTitle("Add Mapping")
    .onAppear {
      focusedField = .original
    }
  }

  private var hasRequiredValues: Bool {
    !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var localizedLanguages: [(identifier: String, name: String)] {
    Self.availableLanguages
      .map { identifier in
        (
          identifier: identifier,
          name: locale.localizedString(forIdentifier: identifier) ?? identifier
        )
      }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  private func addMapping() {
    do {
      let mapping = try ManualCorrectionMapping(
        original: original,
        replacement: replacement,
        language: language
      )
      onAdd(mapping)
      dismiss()
    } catch let error as ManualCorrectionMapping.ValidationError {
      validationError = error
    } catch {
      assertionFailure("Unexpected manual mapping validation error: \(error)")
    }
  }
}

private struct ForgottenRuleConfirmation: Equatable, Identifiable {
  let id = UUID()
  let original: String
}

private struct ForgottenRuleConfirmationView: View {
  let original: String

  var body: some View {
    Label {
      Text(
        "Forgot “\(original)”. Future occurrences will use Typover’s normal correction rules; existing text won’t change.",
        bundle: #bundle,
        comment:
        "Temporary confirmation after forgetting a correction choice. The variable is the original typed word."
      )
    } icon: {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
    }
    .font(.callout)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      .quaternary.opacity(0.45),
      in: RoundedRectangle(cornerRadius: 8)
    )
    .accessibilityIdentifier("typover.settings.rule-forgotten")
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
            .accessibilityHidden(true)

          switch rule.preference {
          case let .preferred(replacement):
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

        HStack(spacing: 5) {
          Text(rule.origin.title)

          if let language = rule.language {
            Text(
              "·",
              bundle: #bundle,
              comment: "Separator between remembered-rule metadata."
            )
            .accessibilityHidden(true)
            Text(locale.localizedString(forIdentifier: language) ?? language)
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
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
          .accessibilityHidden(true)
      }
    } description: {
      Text(
        "Add a mapping, choose another correction, change it back, or directly edit the marked word to create a remembered correction.",
        bundle: #bundle,
        comment:
        "Empty-state explanation of how Typover learns correction preferences."
      )
    }
    .frame(maxWidth: .infinity, minHeight: 120)
  }
}

private extension RememberedCorrectionOrigin {
  var title: LocalizedStringResource {
    switch self {
    case .explicitChoice:
      "Chosen correction"
    case .implicitLocalEdit:
      "Learned from a local edit"
    case .changedBack:
      "Changed back"
    case .manualEntry:
      "Added manually"
    case .legacy:
      "Remembered by an earlier version"
    }
  }
}

private extension ManualCorrectionMapping.ValidationError {
  var message: LocalizedStringResource {
    switch self {
    case .emptyOriginal:
      "Enter the text Typover should recognize."
    case .emptyReplacement:
      "Enter the replacement text."
    case .unchanged:
      "The replacement must differ from the typed text."
    case .originalTooLong:
      "The text to recognize is too long."
    case .replacementTooLong:
      "The replacement is too long."
    case .unsupportedLineBreak:
      "Mappings can’t contain line breaks or control characters."
    }
  }
}
