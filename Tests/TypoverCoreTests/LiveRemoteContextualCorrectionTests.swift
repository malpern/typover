import Foundation
import Testing
import TypoverCore
import TypoverRemoteIntelligence

@testable import TypoverApp

@Suite(
  "Live remote contextual correction",
  .serialized,
  .enabled(
    if: ProcessInfo.processInfo.environment[
      "TYPOVER_RUN_LIVE_MODEL_TESTS"
    ] == "1"
  )
)
struct LiveRemoteContextualCorrectionTests {
  @Test("The production OpenAI adapter returns a safe synthetic rewrite")
  func openAIReturnsSafeRewrite() async throws {
    try await expectSafeRewrite(from: .openAI)
  }

  @Test("The production Anthropic adapter returns a safe synthetic rewrite")
  func anthropicReturnsSafeRewrite() async throws {
    try await expectSafeRewrite(from: .anthropic)
  }

  private func expectSafeRewrite(
    from model: ContextualCorrectionModel
  ) async throws {
    let sentence = "Due to the fact that the server was down, we waited."
    let completedSentence = CompletedSentence(
      range: NSRange(location: 0, length: sentence.utf16.count),
      text: sentence
    )
    let credentialStore = SecretsAppCredentialStore()

    let engine = RemoteContextualCorrectionEngine(
      model: model,
      credentialProvider: credentialStore
    )
    let result = try #require(
      try await engine.proposal(
        for: ContextualCorrectionRequest(
          sentence: sentence,
          language: "en_US",
          scope: .comprehensive,
          allowsSentenceRewrite: true
        )
      )
    )
    let resolved = try #require(
      ContextualCorrectionResolver.resolve(
        result,
        in: completedSentence,
        language: "en_US"
      )
    )

    #expect(resolved.count == 1)
    #expect(resolved[0].proposal.source == model.expectedRewriteSource)
  }
}

extension ContextualCorrectionModel {
  fileprivate var expectedRewriteSource: CorrectionSource {
    switch self {
    case .apple:
      .appleIntelligenceRewrite
    case .openAI:
      .openAIRewrite
    case .anthropic:
      .anthropicRewrite
    }
  }
}
