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

// MARK: - Extraction from iMessage payload_data

/// Extracts LinkPreview from iMessage's NSKeyedArchived payload_data blobs.
///
/// The payload_data is an NSKeyedArchiver binary plist whose root object is Apple's
/// private `RichLink` class (not `LPLinkMetadata`). The `RichLink` wraps metadata
/// containing URL, title, summary, and siteName. We parse the raw plist `$objects`
/// array and resolve `CFKeyedArchiverUID` references via KVC to extract the fields.
public enum LinkPreviewExtractor {

  public static func extract(from data: Data) -> LinkPreview? {
    guard !data.isEmpty else { return nil }

    // Parse as raw property list to access $objects array
    guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
      let dict = plist as? [String: Any],
      let objects = dict["$objects"] as? [Any]
    else { return nil }

    // Find the metadata dictionary — it has a "URL" key
    var metadataDict: [String: Any]?
    for obj in objects {
      if let d = obj as? [String: Any], d["URL"] != nil {
        metadataDict = d
        break
      }
    }
    guard let meta = metadataDict else { return nil }

    // Resolve a CFKeyedArchiverUID to an index, then look up in $objects.
    // CFKeyedArchiverUID is opaque (__NSCFType) and not KVC-compliant,
    // but its description is e.g. "<CFKeyedArchiverUID ...>{value = 8}".
    func resolveUID(_ value: Any?) -> Any? {
      guard let value = value else { return nil }
      // Try as dict with CF$UID key (some plist serialization formats)
      if let uidDict = value as? [String: Any],
        let uid = uidDict["CF$UID"] as? Int,
        uid > 0, uid < objects.count
      {
        return objects[uid]
      }
      // Try parsing the description string for opaque CFKeyedArchiverUID
      let desc = "\(value)"
      if desc.contains("CFKeyedArchiverUID"),
        let range = desc.range(of: "value = "),
        let endRange = desc[range.upperBound...].range(of: "}")
      {
        let numStr = desc[range.upperBound..<endRange.lowerBound]
        if let uid = Int(numStr.trimmingCharacters(in: .whitespaces)),
          uid > 0, uid < objects.count
        {
          return objects[uid]
        }
      }
      return value
    }

    func resolveString(_ key: String) -> String? {
      guard let ref = meta[key] else { return nil }
      let resolved = resolveUID(ref)
      if let str = resolved as? String { return str }
      // NSURL archived objects have NS.relative
      if let urlDict = resolved as? [String: Any] {
        if let rel = resolveUID(urlDict["NS.relative"]) as? String { return rel }
        if let base = resolveUID(urlDict["NS.base"]) as? String { return base }
      }
      return nil
    }

    // Extract URL — stored as an archived NSURL with NS.relative
    let urlString: String?
    if let urlRef = resolveUID(meta["URL"]) as? [String: Any] {
      urlString =
        resolveUID(urlRef["NS.relative"]) as? String
        ?? resolveUID(urlRef["NS.base"]) as? String
    } else {
      urlString = resolveUID(meta["URL"]) as? String
    }

    guard let url = urlString, !url.isEmpty else { return nil }

    return LinkPreview(
      url: url,
      title: resolveUID(meta["title"]) as? String,
      summary: resolveUID(meta["summary"]) as? String,
      siteName: resolveUID(meta["siteName"]) as? String
    )
  }
}
