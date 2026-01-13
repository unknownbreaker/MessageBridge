import Foundation
import Contacts

/// Manages contact lookups from the macOS Contacts app
public actor ContactManager {
    public static let shared = ContactManager()

    private let store = CNContactStore()
    private var cache: [String: String] = [:]  // address -> contact name
    private var authorizationStatus: CNAuthorizationStatus = .notDetermined

    private init() {}

    /// Request authorization to access contacts
    public func requestAuthorization() async -> Bool {
        authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)

        if authorizationStatus == .authorized {
            return true
        }

        if authorizationStatus == .notDetermined {
            do {
                let granted = try await store.requestAccess(for: .contacts)
                authorizationStatus = granted ? .authorized : .denied
                return granted
            } catch {
                print("ContactManager: Failed to request contacts access: \(error)")
                return false
            }
        }

        return false
    }

    /// Look up a contact name for a phone number or email address
    /// Returns nil if not found or not authorized
    public func lookupContactName(for address: String) async -> String? {
        // Check cache first
        if let cached = cache[address] {
            return cached
        }

        // Ensure we have authorization
        if authorizationStatus != .authorized {
            let authorized = await requestAuthorization()
            if !authorized {
                return nil
            }
        }

        // Determine if this is a phone number or email
        let isEmail = address.contains("@")

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]

        do {
            var matchingContact: CNContact?

            if isEmail {
                // Search by email
                let predicate = CNContact.predicateForContacts(matchingEmailAddress: address)
                let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
                matchingContact = contacts.first
            } else {
                // Search by phone number - need to normalize the number
                let normalizedAddress = normalizePhoneNumber(address)

                // Fetch contacts from ALL containers and check phone numbers manually
                let containers = try store.containers(matching: nil)
                outerLoop: for container in containers {
                    let predicate = CNContact.predicateForContactsInContainer(withIdentifier: container.identifier)
                    let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)

                    for contact in contacts {
                        for phoneNumber in contact.phoneNumbers {
                            let contactNumber = normalizePhoneNumber(phoneNumber.value.stringValue)
                            if contactNumber == normalizedAddress ||
                               contactNumber.hasSuffix(normalizedAddress) ||
                               normalizedAddress.hasSuffix(contactNumber) {
                                matchingContact = contact
                                break outerLoop
                            }
                        }
                    }
                }
            }

            if let contact = matchingContact {
                let name = formatContactName(contact)
                if let name = name {
                    cache[address] = name
                }
                return name
            }
        } catch {
            print("ContactManager: Failed to lookup contact for \(address): \(error)")
        }

        return nil
    }

    /// Look up contact names for multiple addresses at once (more efficient)
    public func lookupContactNames(for addresses: [String]) async -> [String: String] {
        var results: [String: String] = [:]

        // First check cache
        var uncached: [String] = []
        for address in addresses {
            if let cached = cache[address] {
                results[address] = cached
            } else {
                uncached.append(address)
            }
        }

        // If all cached, return early
        if uncached.isEmpty {
            return results
        }

        // Ensure we have authorization
        if authorizationStatus != .authorized {
            let authorized = await requestAuthorization()
            if !authorized {
                return results
            }
        }

        // Fetch all contacts once and match against all uncached addresses
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]

        do {
            // Fetch contacts from ALL containers (iCloud, local, Exchange, etc.)
            var allContacts: [CNContact] = []
            let containers = try store.containers(matching: nil)
            for container in containers {
                let predicate = CNContact.predicateForContactsInContainer(withIdentifier: container.identifier)
                let contactsInContainer = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
                allContacts.append(contentsOf: contactsInContainer)
            }

            // Separate emails and phone numbers
            var emailAddresses = Set<String>()
            var phoneAddresses = Set<String>()

            for address in uncached {
                if address.contains("@") {
                    emailAddresses.insert(address.lowercased())
                } else {
                    phoneAddresses.insert(normalizePhoneNumber(address))
                }
            }

            // Match against all contacts
            for contact in allContacts {
                // Check emails
                for emailValue in contact.emailAddresses {
                    let email = (emailValue.value as String).lowercased()
                    if emailAddresses.contains(email) {
                        if let name = formatContactName(contact) {
                            // Find original address (preserve case)
                            for address in uncached where address.lowercased() == email {
                                results[address] = name
                                cache[address] = name
                            }
                        }
                    }
                }

                // Check phone numbers
                for phoneNumber in contact.phoneNumbers {
                    let contactNumber = normalizePhoneNumber(phoneNumber.value.stringValue)
                    for phoneAddr in phoneAddresses {
                        if contactNumber == phoneAddr ||
                           contactNumber.hasSuffix(phoneAddr) ||
                           phoneAddr.hasSuffix(contactNumber) {
                            if let name = formatContactName(contact) {
                                // Find original address
                                for address in uncached where normalizePhoneNumber(address) == phoneAddr {
                                    results[address] = name
                                    cache[address] = name
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            print("ContactManager: Failed to fetch contacts: \(error)")
        }

        return results
    }

    /// Clear the contact name cache
    public func clearCache() {
        cache.removeAll()
    }

    // MARK: - Private Helpers

    private func normalizePhoneNumber(_ phoneNumber: String) -> String {
        // Remove all non-digit characters except leading +
        var normalized = phoneNumber.filter { $0.isNumber }

        // Handle country codes - keep last 10 digits for comparison
        if normalized.count > 10 {
            normalized = String(normalized.suffix(10))
        }

        return normalized
    }

    private func formatContactName(_ contact: CNContact) -> String? {
        // Prefer nickname if available
        if !contact.nickname.isEmpty {
            return contact.nickname
        }

        // Use given + family name
        let given = contact.givenName
        let family = contact.familyName

        if !given.isEmpty && !family.isEmpty {
            return "\(given) \(family)"
        } else if !given.isEmpty {
            return given
        } else if !family.isEmpty {
            return family
        }

        // Fall back to organization
        if !contact.organizationName.isEmpty {
            return contact.organizationName
        }

        return nil
    }
}
