import Foundation

struct TypoverBuildIdentity: Equatable, Sendable {
  static var current: TypoverBuildIdentity {
    TypoverBuildIdentity(infoDictionary: Bundle.main.infoDictionary ?? [:])
  }

  let version: String?
  let build: String?
  let sourceRevision: String?
  let sourceIsDirty: Bool?

  init(infoDictionary: [String: Any]) {
    version = Self.nonemptyString(
      infoDictionary["CFBundleShortVersionString"]
    )
    build = Self.nonemptyString(infoDictionary["CFBundleVersion"])
    sourceRevision = Self.nonemptyString(
      infoDictionary["TypoverSourceRevision"]
    )
    sourceIsDirty = Self.booleanValue(
      infoDictionary["TypoverSourceDirty"]
    )
  }

  var versionAndBuild: (version: String, build: String)? {
    guard let version, let build else {
      return nil
    }
    return (version, build)
  }

  var shortSourceRevision: String? {
    sourceRevision.map { String($0.prefix(10)) }
  }

  private static func nonemptyString(_ value: Any?) -> String? {
    guard let value = value as? String else {
      return nil
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func booleanValue(_ value: Any?) -> Bool? {
    if let value = value as? Bool {
      return value
    }
    guard let value = nonemptyString(value)?.lowercased() else {
      return nil
    }
    switch value {
    case "true", "yes", "1":
      return true
    case "false", "no", "0":
      return false
    default:
      return nil
    }
  }
}
