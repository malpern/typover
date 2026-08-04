public enum CorrectionDisposition: Equatable, Sendable {
  case applied
  case restored
  case kept
  case superseded
  case invalidated
}

public struct CorrectionRecord: Equatable, Sendable {
  public let correction: Correction
  public private(set) var disposition: CorrectionDisposition

  public init(
    correction: Correction,
    disposition: CorrectionDisposition = .applied
  ) {
    self.correction = correction
    self.disposition = disposition
  }

  mutating func transition(to disposition: CorrectionDisposition) {
    self.disposition = disposition
  }
}

public struct CorrectionLedger: Sendable {
  private var recordsByID: [Correction.ID: CorrectionRecord] = [:]

  public init() {}

  public mutating func record(_ correction: Correction) {
    recordsByID[correction.id] = CorrectionRecord(correction: correction)
  }

  @discardableResult
  public mutating func transition(
    _ id: Correction.ID,
    to disposition: CorrectionDisposition
  ) -> Bool {
    guard var record = recordsByID[id] else {
      return false
    }

    record.transition(to: disposition)
    recordsByID[id] = record
    return true
  }

  public func record(for id: Correction.ID) -> CorrectionRecord? {
    recordsByID[id]
  }
}
