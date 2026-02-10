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

    // Try to extract embedded image data from the plist.
    // iMessage stores preview images under "image" or "iconMetadata" keys,
    // which reference a dict containing an "NS.data" key pointing to raw Data.
    let imageBase64 = extractImageData(from: meta, objects: objects, resolveUID: resolveUID)

    return LinkPreview(
      url: url,
      title: resolveUID(meta["title"]) as? String,
      summary: resolveUID(meta["summary"]) as? String,
      siteName: resolveUID(meta["siteName"]) as? String,
      imageBase64: imageBase64
    )
  }

  /// Search metadata and $objects for embedded image data.
  private static func extractImageData(
    from meta: [String: Any],
    objects: [Any],
    resolveUID: (Any?) -> Any?
  ) -> String? {
    // Check common keys that hold image references
    let imageKeys = ["image", "iconMetadata", "icon", "specialization"]
    for key in imageKeys {
      guard let ref = meta[key] else { continue }
      if let imageData = resolveImageFromValue(
        resolveUID(ref), objects: objects, resolveUID: resolveUID)
      {
        return imageData.base64EncodedString()
      }
    }

    return nil
  }

  private static func resolveImageFromValue(
    _ value: Any?,
    objects: [Any],
    resolveUID: (Any?) -> Any?
  ) -> Data? {
    guard let value = value else { return nil }

    // Direct Data
    if let data = value as? Data, looksLikeImage(data) {
      return data
    }

    // Dict with NS.data key (NSData archive)
    if let dict = value as? [String: Any] {
      if let nsData = resolveUID(dict["NS.data"]) as? Data, looksLikeImage(nsData) {
        return nsData
      }
      // Recurse into sub-keys that might hold image data
      for subKey in ["imageData", "data", "NS.data", "resourceData"] {
        if let resolved = resolveUID(dict[subKey]) {
          if let data = resolved as? Data, looksLikeImage(data) {
            return data
          }
          if let subDict = resolved as? [String: Any],
            let data = resolveUID(subDict["NS.data"]) as? Data, looksLikeImage(data)
          {
            return data
          }
        }
      }
    }

    return nil
  }

  /// Check for JPEG (FF D8) or PNG (89 50 4E 47) magic bytes
  private static func looksLikeImage(_ data: Data) -> Bool {
    guard data.count > 4 else { return false }
    let bytes = [UInt8](data.prefix(4))
    // JPEG
    if bytes[0] == 0xFF && bytes[1] == 0xD8 { return true }
    // PNG
    if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 { return true }
    return false
  }
}
