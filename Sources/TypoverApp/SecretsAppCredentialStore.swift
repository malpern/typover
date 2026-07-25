import AppKit
import Foundation
import TypoverCore
import TypoverRemoteIntelligence

actor SecretsAppCredentialStore: RemoteCredentialProvider {
  struct Configuration: Sendable {
    let sopsURL: URL
    let secretsURL: URL
    let ageKeyURL: URL

    static var currentUser: Configuration {
      let home = FileManager.default.homeDirectoryForCurrentUser
      return Configuration(
        sopsURL: URL(fileURLWithPath: "/opt/homebrew/bin/sops"),
        secretsURL:
          home.appending(path: "dotfiles/secrets.env"),
        ageKeyURL:
          home.appending(path: ".config/sops/age/keys.txt")
      )
    }
  }

  private let configuration: Configuration
  private let environment: [String: String]

  init(
    configuration: Configuration = .currentUser,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.configuration = configuration
    self.environment = environment
  }

  func credential(named name: String) async throws -> String {
    guard Self.isAllowedCredentialName(name) else {
      throw SecretsAppCredentialError.invalidCredentialName
    }
    if let value = environment[name], !value.isEmpty {
      return value
    }

    let configuration = configuration
    return try await Task.detached(priority: .userInitiated) {
      try Self.decrypt(name: name, configuration: configuration)
    }.value
  }

  func hasCredential(named name: String) async -> Bool {
    guard
      let credential = try? await credential(named: name),
      !credential.isEmpty
    else {
      return false
    }
    return true
  }

  private static func decrypt(
    name: String,
    configuration: Configuration
  ) throws -> String {
    let fileManager = FileManager.default
    guard
      fileManager.isExecutableFile(
        atPath: configuration.sopsURL.path
      ),
      fileManager.fileExists(
        atPath: configuration.secretsURL.path
      ),
      fileManager.fileExists(
        atPath: configuration.ageKeyURL.path
      )
    else {
      throw SecretsAppCredentialError.storeUnavailable
    }

    let process = Process()
    process.executableURL = configuration.sopsURL
    process.arguments = [
      "--decrypt",
      "--extract",
      "[\"\(name)\"]",
      configuration.secretsURL.path,
    ]
    var processEnvironment = ProcessInfo.processInfo.environment
    processEnvironment["SOPS_AGE_KEY_FILE"] = configuration.ageKeyURL.path
    process.environment = processEnvironment

    let output = Pipe()
    let errors = Pipe()
    process.standardOutput = output
    process.standardError = errors

    do {
      try process.run()
    } catch {
      throw SecretsAppCredentialError.storeUnavailable
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    _ = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw SecretsAppCredentialError.missingCredential
    }
    guard
      let value = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      throw SecretsAppCredentialError.missingCredential
    }
    return value
  }

  private static func isAllowedCredentialName(_ name: String) -> Bool {
    name == ContextualCorrectionModel.openAI.credentialName
      || name == ContextualCorrectionModel.anthropic.credentialName
  }
}

enum SecretsAppCredentialError: Error, Equatable {
  case invalidCredentialName
  case missingCredential
  case storeUnavailable
}

@MainActor
enum SecretsAppLauncher {
  static func open(
    for model: ContextualCorrectionModel,
    completion: @escaping @MainActor (Error?) -> Void = { _ in }
  ) {
    guard model != .apple else {
      completion(SecretsAppCredentialError.invalidCredentialName)
      return
    }
    let applicationURL = URL(
      fileURLWithPath: "/Applications/Add Secret.app"
    )
    guard FileManager.default.fileExists(atPath: applicationURL.path) else {
      completion(SecretsAppCredentialError.storeUnavailable)
      return
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.arguments = ["--key", model.credentialName]
    configuration.activates = true
    NSWorkspace.shared.openApplication(
      at: applicationURL,
      configuration: configuration
    ) { _, error in
      Task { @MainActor in
        completion(error)
      }
    }
  }
}
