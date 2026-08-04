import AppKit
import ApplicationServices
import OSLog
import Observation
import TypoverAccessibility
import TypoverBearAdapter
import TypoverOverlay

@MainActor
@Observable
final class BearOverlayPreviewCoordinator {
  private(set) var status: BearOverlayPreviewStatus = .idle

  private let bearProbe: any BearAccessibilityProbing
  private let bearCorrectionAdapter: BearCorrectionAdapter
  private let bearOverlayController: BearAnnotationOverlayController
  private let logger = Logger(
    subsystem: "com.malpern.typover",
    category: "BearOverlayPreview"
  )

  init(
    bearProbe: any BearAccessibilityProbing = BearAccessibilityProbe(),
    bearCorrectionAdapter: BearCorrectionAdapter = BearCorrectionAdapter()
  ) {
    self.bearProbe = bearProbe
    self.bearCorrectionAdapter = bearCorrectionAdapter
    bearOverlayController = BearAnnotationOverlayController(
      adapter: bearCorrectionAdapter
    )
  }

  func previewSelectedTypo() {
    switch status.previewRequestAction {
    case .ignore:
      logger.notice("Preview ignored because another preview is preparing")
      return
    case .supersede:
      bearOverlayController.stop()
      status = .idle
      logger.notice("Preview superseded the existing interaction")
    case .start:
      break
    }
    guard AXIsProcessTrusted() else {
      let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
      _ = AXIsProcessTrustedWithOptions(options)
      status = .accessibilityPermissionRequired
      logger.error("Preview refused: accessibility_permission_required")
      return
    }

    let startedAt = Date()
    status = .preparing
    logger.notice("Preview started")
    let returnApplication = NSRunningApplication.current
    let bearApplication = NSRunningApplication.runningApplications(
      withBundleIdentifier: BearAccessibilityProbe.bearBundleIdentifier
    ).first
    bearApplication?.activate(options: [.activateAllWindows])

    Task { [self] in
      guard bearApplication != nil else {
        status = .bearUnavailable
        logger.error("Preview refused: bear_unavailable")
        return
      }
      try? await Task.sleep(for: .milliseconds(400))
      let probe = bearProbe
      let report = await Task.detached(priority: .userInitiated) {
        probe.run()
      }.value
      if let failure = BearOverlayPreviewStatus.failure(for: report) {
        returnApplication.activate(options: [.activateAllWindows])
        status = failure
        logger.error(
          "Preview refused after probe: \(failure.diagnosticCode, privacy: .public)"
        )
        return
      }
      guard let selectedRange = report.selectedRange else {
        returnApplication.activate(options: [.activateAllWindows])
        status = .selectExactTypo
        logger.error("Preview refused after probe: selection_unavailable")
        return
      }
      logger.notice(
        "Preview probe ready with selection length \(selectedRange.length, privacy: .public)"
      )

      let adapter = bearCorrectionAdapter
      let application = await Task.detached(priority: .userInitiated) {
        adapter.apply(
          original: "teh",
          replacement: "the",
          at: selectedRange
        )
      }.value
      if !application.isReversibleApplication,
        let failure = BearOverlayPreviewStatus.failure(for: application.report)
      {
        returnApplication.activate(options: [.activateAllWindows])
        status = failure
        logger.error(
          "Preview refused after correction: \(failure.diagnosticCode, privacy: .public); transaction=\(application.report.status.rawValue, privacy: .public)"
        )
        return
      }

      let spellChecker = NSSpellChecker.shared
      let wordRange = NSRange(location: 0, length: "teh".utf16.count)
      let language = spellChecker.userPreferredLanguages.first
      let alternatives =
        spellChecker.guesses(
          forWordRange: wordRange,
          in: "teh",
          language: language,
          inSpellDocumentWithTag: 0
        ) ?? []
      bearOverlayController.track(
        application,
        alternatives: alternatives,
        onFinished: { [weak self] in
          self?.status = .idle
          self?.logger.notice("Preview interaction finished")
        }
      )
      status = .active
      let elapsedMilliseconds = Int(
        Date().timeIntervalSince(startedAt) * 1_000
      )
      logger.notice(
        "Preview active after \(elapsedMilliseconds, privacy: .public) ms"
      )
    }
  }

  func stopPreview() {
    bearOverlayController.stop()
    status = .idle
    logger.notice("Preview stopped")
  }
}

enum BearOverlayPreviewRequestAction: Equatable {
  case start
  case supersede
  case ignore
}

extension BearOverlayPreviewStatus {
  var previewRequestAction: BearOverlayPreviewRequestAction {
    switch self {
    case .preparing:
      .ignore
    case .active:
      .supersede
    default:
      .start
    }
  }

  fileprivate var diagnosticCode: String {
    switch self {
    case .idle:
      "idle"
    case .preparing:
      "preparing"
    case .active:
      "active"
    case .accessibilityPermissionRequired:
      "accessibility_permission_required"
    case .bearUnavailable:
      "bear_unavailable"
    case .editorUnavailable:
      "editor_unavailable"
    case .selectExactTypo:
      "select_exact_typo"
    case .selectionDidNotMatch:
      "selection_did_not_match"
    case .correctionFailed(let status):
      "correction_\(status.rawValue)"
    }
  }
}
