import Foundation

public enum BearHIDLoadProfile: String, Codable, CaseIterable, Sendable {
  case quiet
  case cpu
  case windowServer = "window-server"
  case accessibility
  case combined

  public var stressesCPU: Bool {
    self == .cpu || self == .combined
  }

  public var stressesWindowServer: Bool {
    self == .windowServer || self == .combined
  }

  public var stressesAccessibility: Bool {
    self == .accessibility || self == .combined
  }
}
