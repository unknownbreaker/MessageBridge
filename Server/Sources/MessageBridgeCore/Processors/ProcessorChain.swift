import Foundation

/// Central chain for processing messages through registered processors.
///
/// The ProcessorChain manages a collection of `MessageProcessor` instances and
/// runs messages through them in priority order (highest first). Each processor
/// can enrich the message with additional metadata like detected codes,
/// highlights, or mentions.
///
/// ## Usage
///
/// ```swift
/// // At app startup, register processors
/// ProcessorChain.shared.register(CodeDetector())
/// ProcessorChain.shared.register(MentionExtractor())
///
/// // Process a message
/// let processed = ProcessorChain.shared.process(message)
/// // processed.detectedCodes, processed.mentions, etc. now populated
/// ```
///
/// ## Thread Safety
///
/// All methods are thread-safe and can be called from any thread.
public final class ProcessorChain: @unchecked Sendable {
  /// Shared singleton instance
  public static let shared = ProcessorChain()

  private var processors: [any MessageProcessor] = []
  private let lock = NSLock()

  private init() {}

  /// Register a processor.
  ///
  /// Processors are automatically sorted by priority (highest first) after registration.
  ///
  /// - Parameter processor: The processor to register
  public func register(_ processor: any MessageProcessor) {
    lock.lock()
    defer { lock.unlock() }
    processors.append(processor)
    processors.sort { $0.priority > $1.priority }
  }

  /// Process a message through all registered processors.
  ///
  /// Processors run in priority order (highest first). Each processor receives
  /// the output of the previous one, allowing enrichments to accumulate.
  ///
  /// - Note: Takes a snapshot of processors before processing. If new processors
  ///   are registered during processing, they won't affect the current message.
  ///   Register all processors at app startup for consistent behavior.
  ///
  /// - Parameter message: The original message to process
  /// - Returns: A ProcessedMessage with all enrichments applied
  public func process(_ message: Message) -> ProcessedMessage {
    // Take snapshot under lock, then release before processing
    // This minimizes lock scope and prevents blocking during slow processors
    let sortedProcessors: [any MessageProcessor] = {
      lock.lock()
      defer { lock.unlock() }
      return processors
    }()

    var result = ProcessedMessage(message: message)
    for processor in sortedProcessors {
      result = processor.process(result)
    }
    return result
  }

  /// All registered processors (for inspection).
  ///
  /// Returns processors in priority order (highest first).
  public var all: [any MessageProcessor] {
    lock.lock()
    defer { lock.unlock() }
    return processors
  }

  /// Reset the chain by removing all registered processors.
  ///
  /// Primarily useful for testing.
  public func reset() {
    lock.lock()
    defer { lock.unlock() }
    processors.removeAll()
  }
}
