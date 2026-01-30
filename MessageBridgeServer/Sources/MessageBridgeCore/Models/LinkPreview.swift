import Foundation
import LinkPresentation
import Vapor

/// Rich link preview metadata extracted from iMessage's payload_data
public struct LinkPreview: Content, Sendable {
  public let url: String
  public let title: String?
  public let summary: String?
  public let siteName: String?
  public let imageBase64: String?

  public init(
    url: String,
    title: String? = nil,
    summary: String? = nil,
    siteName: String? = nil,
    imageBase64: String? = nil
  ) {
    self.url = url
    self.title = title
    self.summary = summary
    self.siteName = siteName
    self.imageBase64 = imageBase64
  }
}

// MARK: - Extraction from iMessage payload_data

/// Extracts LinkPreview from iMessage's NSKeyedArchived payload_data blobs
public enum LinkPreviewExtractor {
  /// Extract link preview from an NSKeyedArchiver-encoded LPLinkMetadata blob
  public static func extract(from data: Data) -> LinkPreview? {
    guard !data.isEmpty else { return nil }

    let metadata: LPLinkMetadata?
    do {
      let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
      unarchiver.requiresSecureCoding = false
      metadata = unarchiver.decodeObject(
        of: LPLinkMetadata.self, forKey: NSKeyedArchiveRootObjectKey
      )
      unarchiver.finishDecoding()
    } catch {
      return nil
    }

    guard let metadata = metadata, let url = metadata.url else {
      return nil
    }

    return LinkPreview(
      url: url.absoluteString,
      title: metadata.title
    )
  }
}
