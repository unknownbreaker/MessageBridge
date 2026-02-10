import Foundation
import Vapor

/// Represents a contact (phone number or email) in the Messages database
public struct Handle: Content, Identifiable, Sendable {
  public let id: Int64
  public let address: String  // Phone number or email
  public let service: String  // "iMessage" or "SMS"
  public let contactName: String?  // Name from Contacts app (if found)
  public let photoBase64: String?  // Contact photo as base64-encoded JPEG (if found)

  public init(
    id: Int64, address: String, service: String, contactName: String? = nil,
    photoBase64: String? = nil
  ) {
    self.id = id
    self.address = address
    self.service = service
    self.contactName = contactName
    self.photoBase64 = photoBase64
  }

  /// Display name - prefers contact name, falls back to address
  public var displayName: String {
    contactName ?? address
  }

  /// Formatted display string for the address
  public var displayAddress: String {
    // Format phone numbers nicely if possible
    if address.hasPrefix("+") || address.allSatisfy({ $0.isNumber || $0 == "-" || $0 == " " }) {
      return address
    }
    return address
  }
}
