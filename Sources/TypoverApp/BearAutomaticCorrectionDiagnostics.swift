import Foundation
import Observation

enum BearAutomaticCorrectionDiagnosticOutcome: String, Equatable, Sendable {
  case applied
  case postWriteReconciled
  case postWriteReconciliationFailed
  case rapidTypingDeferred
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
  let correctionsDeferred: Int
  let safeSkips: Int
  let refusals: Int
  let correctionToAnnotationSampleCount: Int
  let medianCorrectionToAnnotationMilliseconds: Double
  let p95CorrectionToAnnotationMilliseconds: Double
  let interactionLatencySampleCount: Int
  let medianInteractionLatencyMilliseconds: Double
  let p95InteractionLatencyMilliseconds: Double
  let lastOutcome: BearAutomaticCorrectionDiagnosticOutcome?
}

@MainActor
@Observable
final class BearAutomaticCorrectionDiagnostics {
  private(set) var boundaryInputs = 0
  private(set) var valueChanges = 0
  private(set) var correctionsApplied = 0
  private(set) var correctionsDeferred = 0
  private(set) var safeSkips = 0
  private(set) var refusals = 0
  private(set) var lastOutcome: BearAutomaticCorrectionDiagnosticOutcome?

  private var correctionToAnnotationMilliseconds: [Double] = []
  private var interactionLatencyMilliseconds: [Double] = []
  private let maximumLatencySamples = 200

  var snapshot: BearAutomaticCorrectionDiagnosticsSnapshot {
    BearAutomaticCorrectionDiagnosticsSnapshot(
      boundaryInputs: boundaryInputs,
      valueChanges: valueChanges,
      correctionsApplied: correctionsApplied,
      correctionsDeferred: correctionsDeferred,
      safeSkips: safeSkips,
      refusals: refusals,
      correctionToAnnotationSampleCount:
        correctionToAnnotationMilliseconds.count,
      medianCorrectionToAnnotationMilliseconds: percentile(
        0.5,
        in: correctionToAnnotationMilliseconds
      ),
      p95CorrectionToAnnotationMilliseconds: percentile(
        0.95,
        in: correctionToAnnotationMilliseconds
      ),
      interactionLatencySampleCount: interactionLatencyMilliseconds.count,
      medianInteractionLatencyMilliseconds: percentile(
        0.5,
        in: interactionLatencyMilliseconds
      ),
      p95InteractionLatencyMilliseconds: percentile(
        0.95,
        in: interactionLatencyMilliseconds
      ),
      lastOutcome: lastOutcome
    )
  }

  func recordBoundaryInput() {
    boundaryInputs += 1
  }

  func recordValueChange() {
    valueChanges += 1
  }

  func recordDeferred() {
    correctionsDeferred += 1
    lastOutcome = .rapidTypingDeferred
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

  func recordPostWriteReconciled() {
    lastOutcome = .postWriteReconciled
  }

  func recordInteractionLatency(_ elapsed: Duration) {
    interactionLatencyMilliseconds.append(Self.milliseconds(elapsed))
    trimSamples(&interactionLatencyMilliseconds)
  }

  func reset() {
    boundaryInputs = 0
    valueChanges = 0
    correctionsApplied = 0
    correctionsDeferred = 0
    safeSkips = 0
    refusals = 0
    lastOutcome = nil
    correctionToAnnotationMilliseconds.removeAll(keepingCapacity: true)
    interactionLatencyMilliseconds.removeAll(keepingCapacity: true)
  }

  private func percentile(
    _ percentile: Double,
    in samples: [Double]
  ) -> Double {
    guard !samples.isEmpty else {
      return 0
    }
    let sorted = samples.sorted()
    let index = min(
      sorted.count - 1,
      max(0, Int(ceil(percentile * Double(sorted.count))) - 1)
    )
    return sorted[index]
  }

  private func trimSamples(_ samples: inout [Double]) {
    if samples.count > maximumLatencySamples {
      samples.removeFirst(samples.count - maximumLatencySamples)
    }
  }

  private static func milliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
  }
}
