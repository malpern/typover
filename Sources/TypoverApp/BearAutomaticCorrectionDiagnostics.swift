import Foundation
import Observation

enum BearAutomaticCorrectionDiagnosticOutcome: String, Equatable, Sendable {
  case applied
  case unarmedValueChange
  case contextUnavailable
  case baselineUnavailable
  case staleBoundaryInput
  case contextChanged
  case noSuggestion
  case learnedSuppression
  case proposalMismatch
  case replacementRefused
  case capabilityUnavailable
  case inputMonitoringUnavailable
  case unsupportedEnvironment
}

struct BearAutomaticCorrectionDiagnosticsSnapshot: Equatable, Sendable {
  let boundaryInputs: Int
  let valueChanges: Int
  let correctionsApplied: Int
  let safeSkips: Int
  let refusals: Int
  let correctionToAnnotationSampleCount: Int
  let medianCorrectionToAnnotationMilliseconds: Double
  let p95CorrectionToAnnotationMilliseconds: Double
  let lastOutcome: BearAutomaticCorrectionDiagnosticOutcome?
}

@MainActor
@Observable
final class BearAutomaticCorrectionDiagnostics {
  private(set) var boundaryInputs = 0
  private(set) var valueChanges = 0
  private(set) var correctionsApplied = 0
  private(set) var safeSkips = 0
  private(set) var refusals = 0
  private(set) var lastOutcome: BearAutomaticCorrectionDiagnosticOutcome?

  private var correctionToAnnotationMilliseconds: [Double] = []
  private let maximumLatencySamples = 200

  var snapshot: BearAutomaticCorrectionDiagnosticsSnapshot {
    BearAutomaticCorrectionDiagnosticsSnapshot(
      boundaryInputs: boundaryInputs,
      valueChanges: valueChanges,
      correctionsApplied: correctionsApplied,
      safeSkips: safeSkips,
      refusals: refusals,
      correctionToAnnotationSampleCount:
        correctionToAnnotationMilliseconds.count,
      medianCorrectionToAnnotationMilliseconds: percentile(0.5),
      p95CorrectionToAnnotationMilliseconds: percentile(0.95),
      lastOutcome: lastOutcome
    )
  }

  func recordBoundaryInput() {
    boundaryInputs += 1
  }

  func recordValueChange() {
    valueChanges += 1
  }

  func recordSafeSkip(
    _ outcome: BearAutomaticCorrectionDiagnosticOutcome
  ) {
    safeSkips += 1
    lastOutcome = outcome
  }

  func recordRefusal(
    _ outcome: BearAutomaticCorrectionDiagnosticOutcome
  ) {
    refusals += 1
    lastOutcome = outcome
  }

  func recordApplied(elapsed: Duration?) {
    correctionsApplied += 1
    lastOutcome = .applied
    guard let elapsed else {
      return
    }
    correctionToAnnotationMilliseconds.append(Self.milliseconds(elapsed))
    if correctionToAnnotationMilliseconds.count > maximumLatencySamples {
      correctionToAnnotationMilliseconds.removeFirst(
        correctionToAnnotationMilliseconds.count - maximumLatencySamples
      )
    }
  }

  func reset() {
    boundaryInputs = 0
    valueChanges = 0
    correctionsApplied = 0
    safeSkips = 0
    refusals = 0
    lastOutcome = nil
    correctionToAnnotationMilliseconds.removeAll(keepingCapacity: true)
  }

  private func percentile(_ percentile: Double) -> Double {
    guard !correctionToAnnotationMilliseconds.isEmpty else {
      return 0
    }
    let sorted = correctionToAnnotationMilliseconds.sorted()
    let index = min(
      sorted.count - 1,
      max(0, Int(ceil(percentile * Double(sorted.count))) - 1)
    )
    return sorted[index]
  }

  private static func milliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
  }
}
