import Foundation
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
