import Foundation

public enum CorrectionDiagnosticKind: String, Codable, Equatable, Sendable {
  case annotationInvalidated
  case contextualCompositionActive
  case contextualModelFailure
  case contextualProposalRejected
  case contextualStaleSentence
  case editRejected
  case pasteSkipped
  case staleRange
  case staleText
}

public struct CorrectionDiagnostic: Codable, Equatable, Sendable {
  public let kind: CorrectionDiagnosticKind
  public let correctionID: Correction.ID?
  public let rangeLocation: Int?
  public let rangeLength: Int?
  public let documentUTF16Length: Int
  public let createdAt: Date

  public init(
    kind: CorrectionDiagnosticKind,
    correctionID: Correction.ID? = nil,
    range: NSRange? = nil,
    documentUTF16Length: Int,
    createdAt: Date = Date()
  ) {
    self.kind = kind
    self.correctionID = correctionID
    rangeLocation = range?.location
    rangeLength = range?.length
    self.documentUTF16Length = documentUTF16Length
    self.createdAt = createdAt
  }
}

public struct CorrectionTransactionSample: Equatable, Sendable {
  public let correctionID: Correction.ID
  public let elapsed: Duration
  public let documentUTF16Length: Int
  public let createdAt: Date

  public init(
    correctionID: Correction.ID,
    elapsed: Duration,
    documentUTF16Length: Int,
    createdAt: Date = Date()
  ) {
    self.correctionID = correctionID
    self.elapsed = elapsed
    self.documentUTF16Length = documentUTF16Length
    self.createdAt = createdAt
  }
}
