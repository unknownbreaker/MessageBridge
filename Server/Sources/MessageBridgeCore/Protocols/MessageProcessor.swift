import Foundation

/// A stateless processor that transforms messages through the processing chain.
///
/// Message processors are used to enrich messages with additional metadata
/// such as detected verification codes, phone numbers, mentions, and other
/// highlights. Each processor focuses on a single type of detection or
/// transformation.
///
/// ## Priority
///
/// Processors run in priority order (highest first). Use priority to ensure
/// dependent processors run in the correct order. For example, a code detector
/// that adds highlights should run before a renderer that uses those highlights.
///
/// ## Usage
///
/// ```swift
/// struct CodeDetector: MessageProcessor {
///     let id = "code-detector"
///     let priority = 200  // Run early
///
///     func process(_ message: ProcessedMessage) -> ProcessedMessage {
///         var result = message
///         // Detect codes and add to result.detectedCodes
///         return result
///     }
/// }
///
/// // Register at startup
/// ProcessorChain.shared.register(CodeDetector())
/// ```
///
/// ## Implementation Guidelines
///
/// - Processors should be stateless and idempotent
/// - Return the message unchanged if no processing is needed
/// - Do not modify the original `message` property, only enrichment fields
/// - Keep processing fast; do not perform network requests
public protocol MessageProcessor: Identifiable, Sendable {
  /// Unique identifier for this processor (e.g., "code-detector", "emoji-enlarger")
  var id: String { get }

  /// Processing priority. Higher values run first.
  ///
  /// Recommended ranges:
  /// - 200+: Critical detection (codes, security-related)
  /// - 100-199: Primary enrichment (links, mentions)
  /// - 50-99: Secondary enrichment (emoji, formatting)
  /// - 0-49: Fallback/cleanup processors
  /// - Negative: Post-processing
  var priority: Int { get }

  /// Process the message and return an enriched version.
  ///
  /// - Parameter message: The message to process (may already have enrichments from earlier processors)
  /// - Returns: The processed message with any additional enrichments
  func process(_ message: ProcessedMessage) -> ProcessedMessage
}
