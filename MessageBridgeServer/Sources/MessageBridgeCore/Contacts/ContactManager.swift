import Contacts
import Foundation

/// Contact information including name and photo
public struct ContactInfo: Sendable {
  public let name: String?
  public let photoData: Data?

  public init(name: String?, photoData: Data?) {
    self.name = name
    self.photoData = photoData
  }
}

/// Manages contact lookups from the macOS Contacts app
public actor ContactManager {
  public static let shared = ContactManager()

  private let store = CNContactStore()
  private var nameCache: [String: String] = [:]  // address -> contact name
  private var photoCache: [String: Data] = [:]  // address -> photo data
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
    if let cached = nameCache[address] {
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
      CNContactEmailAddressesKey as CNKeyDescriptor,
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
          let predicate = CNContact.predicateForContactsInContainer(
            withIdentifier: container.identifier)
          let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)

          for contact in contacts {
            for phoneNumber in contact.phoneNumbers {
              let contactNumber = normalizePhoneNumber(phoneNumber.value.stringValue)
              if contactNumber == normalizedAddress || contactNumber.hasSuffix(normalizedAddress)
                || normalizedAddress.hasSuffix(contactNumber)
              {
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
          nameCache[address] = name
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
      if let cached = nameCache[address] {
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
      CNContactEmailAddressesKey as CNKeyDescriptor,
    ]

    do {
      // Fetch contacts from ALL containers (iCloud, local, Exchange, etc.)
      var allContacts: [CNContact] = []
      let containers = try store.containers(matching: nil)
      for container in containers {
        let predicate = CNContact.predicateForContactsInContainer(
          withIdentifier: container.identifier)
        let contactsInContainer = try store.unifiedContacts(
          matching: predicate, keysToFetch: keysToFetch)
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
                nameCache[address] = name
              }
            }
          }
        }

        // Check phone numbers
        for phoneNumber in contact.phoneNumbers {
          let contactNumber = normalizePhoneNumber(phoneNumber.value.stringValue)
          for phoneAddr in phoneAddresses {
            if contactNumber == phoneAddr || contactNumber.hasSuffix(phoneAddr)
              || phoneAddr.hasSuffix(contactNumber)
            {
              if let name = formatContactName(contact) {
                // Find original address
                for address in uncached where normalizePhoneNumber(address) == phoneAddr {
                  results[address] = name
                  nameCache[address] = name
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

  /// Look up contact info (name and photo) for multiple addresses at once
  public func lookupContactInfo(for addresses: [String]) async -> [String: ContactInfo] {
    var results: [String: ContactInfo] = [:]

    // First check caches
    var uncached: [String] = []
    for address in addresses {
      let cachedName = nameCache[address]
      let cachedPhoto = photoCache[address]
      if cachedName != nil || cachedPhoto != nil {
        results[address] = ContactInfo(name: cachedName, photoData: cachedPhoto)
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

    // Fetch all contacts with photos
    let keysToFetch: [CNKeyDescriptor] = [
      CNContactGivenNameKey as CNKeyDescriptor,
      CNContactFamilyNameKey as CNKeyDescriptor,
      CNContactNicknameKey as CNKeyDescriptor,
      CNContactOrganizationNameKey as CNKeyDescriptor,
      CNContactPhoneNumbersKey as CNKeyDescriptor,
      CNContactEmailAddressesKey as CNKeyDescriptor,
      CNContactThumbnailImageDataKey as CNKeyDescriptor,
    ]

    do {
      // Fetch contacts from ALL containers
      var allContacts: [CNContact] = []
      let containers = try store.containers(matching: nil)
      for container in containers {
        let predicate = CNContact.predicateForContactsInContainer(
          withIdentifier: container.identifier)
        let contactsInContainer = try store.unifiedContacts(
          matching: predicate, keysToFetch: keysToFetch)
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
            let name = formatContactName(contact)
            let photo = contact.thumbnailImageData
            // Find original address (preserve case)
            for address in uncached where address.lowercased() == email {
              if let name = name {
                nameCache[address] = name
              }
              if let photo = photo {
                photoCache[address] = photo
              }
              results[address] = ContactInfo(name: name, photoData: photo)
            }
          }
        }

        // Check phone numbers
        for phoneNumber in contact.phoneNumbers {
          let contactNumber = normalizePhoneNumber(phoneNumber.value.stringValue)
          for phoneAddr in phoneAddresses {
            if contactNumber == phoneAddr || contactNumber.hasSuffix(phoneAddr)
              || phoneAddr.hasSuffix(contactNumber)
            {
              let name = formatContactName(contact)
              let photo = contact.thumbnailImageData
              // Find original address
              for address in uncached where normalizePhoneNumber(address) == phoneAddr {
                if let name = name {
                  nameCache[address] = name
                }
                if let photo = photo {
                  photoCache[address] = photo
                }
                results[address] = ContactInfo(name: name, photoData: photo)
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
    nameCache.removeAll()
    photoCache.removeAll()
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
