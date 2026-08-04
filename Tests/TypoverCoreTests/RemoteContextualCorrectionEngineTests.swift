import Foundation
import Testing
import TypoverCore
import TypoverRemoteIntelligence

@Suite(.serialized)
struct RemoteContextualCorrectionEngineTests {
  @Test("OpenAI produces a provider-attributed careful correction")
  func openAICarefulCorrection() async throws {
    let session = makeSession { request in
      guard
        request.value(forHTTPHeaderField: "Authorization")
          == "Bearer test-credential"
      else {
        return Self.response(status: 401, object: [:], for: request)
      }
      return Self.response(
        status: 200,
        object: [
          "choices": [
            [
              "message": [
                "content":
                  #"{"edits":[{"original":"Their","replacement":"They're"}],"rewrittenSentence":""}"#
              ]
            ]
          ]
        ],
        for: request
      )
    }
    let engine = RemoteContextualCorrectionEngine(
      model: .openAI,
      credentialProvider: TestCredentialProvider(),
      session: session
    )

    let result = try #require(
      try await engine.proposal(
        for: ContextualCorrectionRequest(
          sentence: "Their going now.",
          language: "en_US"
        )
      )
    )
    let candidate = try #require(result.candidates.first)

    #expect(candidate.original == "Their")
    #expect(candidate.replacement == "They're")
    #expect(candidate.source == .openAI)
  }

  @Test("Anthropic rewrites retain provider attribution through resolution")
  func anthropicSentenceRewrite() async throws {
    let session = makeSession { request in
      guard
        request.value(forHTTPHeaderField: "x-api-key")
          == "test-credential"
      else {
        return Self.response(status: 401, object: [:], for: request)
      }
      return Self.response(
        status: 200,
        object: [
          "content": [
            [
              "type": "tool_use",
              "name": "submit_correction",
              "input": [
                "edits": [],
                "rewrittenSentence": "We analyzed the results.",
              ],
            ]
          ]
        ],
        for: request
      )
    }
    let engine = RemoteContextualCorrectionEngine(
      model: .anthropic,
      credentialProvider: TestCredentialProvider(),
      session: session
    )
    let sentence = "We conducted an analysis of the results."
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
    let completedSentence = CompletedSentence(
      range: NSRange(location: 0, length: sentence.utf16.count),
      text: sentence
    )
    let resolved = try #require(
      ContextualCorrectionResolver.resolve(
        result,
        in: completedSentence,
        language: "en_US"
      )
    )

    #expect(resolved.count == 1)
    #expect(
      resolved[0].proposal.source == CorrectionSource.anthropicRewrite
    )
  }

  private func makeSession(
    handler:
      @escaping @Sendable (URLRequest) ->
      (
        HTTPURLResponse,
        Data
      )
  ) -> URLSession {
    MockURLProtocol.handler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
  }

  private static func response(
    status: Int,
    object: [String: Any],
    for request: URLRequest
  ) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: status,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    return (
      response,
      try! JSONSerialization.data(withJSONObject: object)
    )
  }
}

private actor TestCredentialProvider: RemoteCredentialProvider {
  func credential(named _: String) -> String {
    "test-credential"
  }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler:
    (
      @Sendable (URLRequest) ->
        (HTTPURLResponse, Data)
    )?

  override class func canInit(with _: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let handler = Self.handler else {
      client?.urlProtocol(
        self,
        didFailWithError: RemoteContextualCorrectionError.invalidResponse
      )
      return
    }
    let (response, data) = handler(request)
    client?.urlProtocol(
      self,
      didReceive: response,
      cacheStoragePolicy: .notAllowed
    )
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
