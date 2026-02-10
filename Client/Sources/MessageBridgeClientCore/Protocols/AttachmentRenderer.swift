import SwiftUI

/// Protocol for rendering groups of message attachments.
///
/// Implementations handle different attachment configurations (single image,
/// image gallery, video, audio, documents). The AttachmentRendererRegistry
/// selects the highest-priority renderer whose `canRender` returns true.
///
/// Renderers receive all attachments for a message as a group, enabling
/// multi-attachment layouts like image grids.
public protocol AttachmentRenderer: Identifiable, Sendable {
  /// Unique identifier for this renderer
  var id: String { get }

  /// Priority for renderer selection. Higher priority renderers are checked first.
  var priority: Int { get }

  /// Whether this renderer can handle the given attachments.
  func canRender(_ attachments: [Attachment]) -> Bool

  /// Render the attachments.
  @MainActor func render(_ attachments: [Attachment]) -> AnyView
}
