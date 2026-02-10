import Foundation

@testable import MessageBridgeCore

/// Mock message processor for testing
///
/// This mock allows configuring the processing behavior via a closure,
/// making it easy to test different processing scenarios.
///
/// ## Usage
///
/// ```swift
/// var processor = MockMessageProcessor(id: "test", priority: 100)
///
/// // Configure to add detected codes
/// processor.processHandler = { message in
///     var modified = message
///     modified.detectedCodes = [DetectedCode(value: "123456", confidence: .high)]
///     return modified
/// }
///
/// let result = processor.process(inputMessage)
/// ```
public struct MockMessageProcessor: MessageProcessor {
  public let id: String
  public let priority: Int

  /// Handler called during `process()`. Defaults to returning the message unchanged.
  public var processHandler: @Sendable (ProcessedMessage) -> ProcessedMessage

  /// Creates a mock processor with the given id and priority.
  ///
  /// - Parameters:
  ///   - id: Unique identifier for this processor
  ///   - priority: Processing priority (higher runs first)
  public init(id: String, priority: Int) {
    self.id = id
    self.priority = priority
    self.processHandler = { $0 }
  }

  /// Process the message using the configured handler.
  ///
  /// By default, returns the message unchanged (passthrough).
  /// Configure `processHandler` to customize the behavior.
  public func process(_ message: ProcessedMessage) -> ProcessedMessage {
    processHandler(message)
  }
}
