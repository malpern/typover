import Foundation
import Testing
import TypoverRemoteIntelligence

@testable import TypoverApp

struct SecretsAppCredentialStoreTests {
  @Test("Environment credentials are read without touching the encrypted store")
  func readsEnvironmentCredential() async throws {
    let missingURL = URL(fileURLWithPath: "/does-not-exist")
    let store = SecretsAppCredentialStore(
      configuration: .init(
        sopsURL: missingURL,
        secretsURL: missingURL,
        ageKeyURL: missingURL
      ),
      environment: ["OPENAI_API_KEY": "test-credential"]
    )

    let credential = try await store.credential(named: "OPENAI_API_KEY")

    #expect(credential == "test-credential")
    #expect(await store.hasCredential(named: "OPENAI_API_KEY"))
  }

  @Test("Only known provider credential names can be requested")
  func rejectsUnknownCredentialName() async {
    let store = SecretsAppCredentialStore(environment: [:])

    await #expect(throws: SecretsAppCredentialError.invalidCredentialName) {
      try await store.credential(named: "UNRELATED_SECRET")
    }
  }
}
