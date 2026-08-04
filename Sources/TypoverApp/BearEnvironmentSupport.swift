import AppKit
import Foundation
import TypoverAccessibility

enum BearEnvironmentSupport: Equatable, Sendable {
  case supported
  case bearNotRunning
  case bearVersionUnavailable
  case unsupportedBearVersion(installed: String)
  case unsupportedMacOSVersion(installed: String)
}

struct BearSupportPolicy: Equatable, Sendable {
  static let current = BearSupportPolicy(
    bearVersions: ["2.8.1", "2.9.1"],
    macOSMajorVersion: 27,
    macOSMinorVersion: 0
  )

  let bearVersions: [String]
  let macOSMajorVersion: Int
  let macOSMinorVersion: Int

  func evaluate(
    bearVersion installedBearVersion: String?,
    operatingSystemVersion: OperatingSystemVersion
  ) -> BearEnvironmentSupport {
    guard
      operatingSystemVersion.majorVersion == macOSMajorVersion,
      operatingSystemVersion.minorVersion == macOSMinorVersion
    else {
      return .unsupportedMacOSVersion(
        installed: Self.displayVersion(operatingSystemVersion)
      )
    }
    guard let installedBearVersion else {
      return .bearVersionUnavailable
    }
    guard bearVersions.contains(installedBearVersion) else {
      return .unsupportedBearVersion(installed: installedBearVersion)
    }
    return .supported
  }

  private static func displayVersion(
    _ version: OperatingSystemVersion
  ) -> String {
    "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
  }
}

@MainActor
protocol BearEnvironmentChecking: Sendable {
  func support() -> BearEnvironmentSupport
}

struct SystemBearEnvironmentChecker: BearEnvironmentChecking, Sendable {
  let policy: BearSupportPolicy

  init(policy: BearSupportPolicy = .current) {
    self.policy = policy
  }

  @MainActor
  func support() -> BearEnvironmentSupport {
    guard
      let application = NSRunningApplication.runningApplications(
        withBundleIdentifier: BearAccessibilityProbe.bearBundleIdentifier
      ).first
    else {
      return .bearNotRunning
    }
    let bearVersion = application.bundleURL
      .flatMap(Bundle.init(url:))?
      .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    return policy.evaluate(
      bearVersion: bearVersion,
      operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersion
    )
  }
}
