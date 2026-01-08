import Foundation

/// Represents a contact (phone number or email) in the Messages database
struct Handle: Codable, Identifiable, Sendable {
    let id: Int64
    let address: String      // Phone number or email
    let service: String      // "iMessage" or "SMS"

    /// Formatted display string for the address
    var displayAddress: String {
        // Format phone numbers nicely if possible
        if address.hasPrefix("+") || address.allSatisfy({ $0.isNumber || $0 == "-" || $0 == " " }) {
            return address
        }
        return address
    }
}
