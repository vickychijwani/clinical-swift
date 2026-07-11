import Contacts
import Dependencies
import Foundation

nonisolated struct AppointmentContactClient: Sendable {
    var nameForPhone: @MainActor @Sendable (_ phone: String) async -> String?
}

nonisolated extension AppointmentContactClient: DependencyKey {
    nonisolated static let liveValue = Self { phone in
        let store = CNContactStore()

        let hasAccess: Bool
        do {
            hasAccess = try await store.requestAccess(for: .contacts)
        } catch {
            return nil
        }

        guard hasAccess else {
            return nil
        }

        let keys =
            [
                CNContactNamePrefixKey,
                CNContactGivenNameKey,
                CNContactMiddleNameKey,
                CNContactFamilyNameKey,
                CNContactNameSuffixKey,
                CNContactOrganizationNameKey,
            ] as [CNKeyDescriptor]

        let contacts: [CNContact]
        do {
            contacts = try store.unifiedContacts(
                matching: CNContact.predicateForContacts(
                    matching: CNPhoneNumber(stringValue: phone)
                ),
                keysToFetch: keys
            )
        } catch {
            return nil
        }

        return contacts.lazy.compactMap(\.formattedName).first
    }

    nonisolated static let testValue = Self { _ in nil }
}

extension DependencyValues {
    nonisolated var appointmentContactClient: AppointmentContactClient {
        get { self[AppointmentContactClient.self] }
        set { self[AppointmentContactClient.self] = newValue }
    }
}
