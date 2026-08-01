import ApplicationServices

/// Serializes Accessibility operations against Bear.
///
/// AX calls are synchronous IPC. Running several correction, geometry, and
/// restoration transactions concurrently increases latency and can interleave
/// mutations against the same editor. This actor gives the Bear integration a
/// single off-main execution lane while preserving the synchronous transaction
/// implementations at the API boundary.
public actor BearAccessibilityOperationLane {
  public static let shared = BearAccessibilityOperationLane()

  public init() {}

  public func run<Result: Sendable>(
    _ operation: @Sendable () -> Result
  ) -> Result {
    operation()
  }
}

let bearAccessibilityMessagingTimeout: Float = 0.75

@discardableResult
func configureBearAccessibilityMessagingTimeout(
  _ element: AXUIElement
) -> AXError {
  AXUIElementSetMessagingTimeout(
    element,
    bearAccessibilityMessagingTimeout
  )
}
