import AppIntents
import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import SQLiteData

@MainActor
final class ClinicalAppActions {
    private let router: Router
    private let database: any DatabaseWriter

    nonisolated init(router: Router, database: any DatabaseWriter) {
        self.router = router
        self.database = database
    }

    func bookAppointment() {
        router.requestScheduleCreation()
    }

    func findPatient(phoneNumbers: Set<String>) async throws -> PatientContactMatch {
        let normalizedPhoneNumbers = Set(phoneNumbers.compactMap(PhoneNumber.normalizedE164))
        guard !normalizedPhoneNumbers.isEmpty else { return .none }

        let patients = try await database.read { db in
            var patientsByID: [Patient.ID: Patient] = [:]

            for phoneNumber in normalizedPhoneNumbers {
                let records =
                    try PatientRecord
                    .where { $0.phone.eq(phoneNumber) }
                    .fetchAll(db)

                for record in records {
                    let patient = Patient(record)
                    patientsByID[patient.id] = patient
                }
            }

            return Array(patientsByID.values)
        }

        switch patients.count {
        case 0:
            return .none
        case 1:
            let patient = patients[0]
            router.openExternalDetails(.patient(patient.id))
            return .one(patient)
        default:
            let matchingPhoneNumbers = Set(patients.compactMap(\.phone))
            router.openExternalPatientSearch(phoneNumbers: matchingPhoneNumbers)
            return .multiple(patients.count)
        }
    }
}

nonisolated enum PatientContactMatch: Equatable, Sendable {
    case none
    case one(Patient)
    case multiple(Int)
}

struct BookAppointmentIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Book Appointment"
    nonisolated static let description = IntentDescription(
        "Opens Clinical's appointment booking flow."
    )
    nonisolated static let supportedModes: IntentModes = [.foreground(.immediate)]

    @AppDependency private var appActions: ClinicalAppActions

    @MainActor
    func perform() async throws -> some IntentResult {
        let telemetry = Dependencies.Dependency(\.telemetry).wrappedValue
        telemetry.event(
            category: .intent,
            name: "intent_invoked",
            source: "app_intent",
            action: "book_appointment"
        )
        appActions.bookAppointment()
        return .result()
    }
}

struct FindPatientFromContactIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Find Patient from Contact"
    nonisolated static let description = IntentDescription(
        "Finds Clinical patients linked to a contact's phone numbers."
    )
    nonisolated static let supportedModes: IntentModes = [.foreground(.immediate)]

    @Parameter(title: "Contact", mode: .contact)
    var contact: IntentPerson

    @AppDependency private var appActions: ClinicalAppActions

    nonisolated static var parameterSummary: some ParameterSummary {
        Summary("Find patient from \(\.$contact)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let telemetry = Dependencies.Dependency(\.telemetry).wrappedValue
        let match: PatientContactMatch
        do {
            match = try await appActions.findPatient(
                phoneNumbers: Self.phoneNumbers(from: contact)
            )
        } catch {
            telemetry.log(
                .error,
                category: .intent,
                name: "intent_failed",
                message: "Find patient intent failed",
                error: error,
                source: "app_intent",
                action: "find_patient_from_contact"
            )
            throw error
        }

        let (status, matchCount): (String, Int) =
            switch match {
            case .none: ("none", 0)
            case .one: ("one", 1)
            case .multiple(let count): ("multiple", count)
            }
        telemetry.event(
            category: .intent,
            name: "intent_invoked",
            count: matchCount,
            status: status,
            source: "app_intent",
            action: "find_patient_from_contact"
        )

        let dialog: IntentDialog =
            switch match {
            case .none:
                "No matching patient."
            case .one(let patient):
                "Opening \(patient.displayName)."
            case .multiple(let count):
                "Opening \(count) matching patients."
            }

        return .result(dialog: dialog)
    }

    nonisolated static func phoneNumbers(from person: IntentPerson) -> Set<String> {
        let handles = [person.handle].compactMap(\.self) + person.aliases

        return Set(
            handles.compactMap { handle in
                guard case .phoneNumber(let phoneNumber) = handle.value else { return nil }
                return PhoneNumber.normalizedE164(phoneNumber)
            })
    }
}

struct ClinicalShortcuts: AppShortcutsProvider {
    nonisolated static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: BookAppointmentIntent(),
            phrases: [
                "Book an appointment in \(.applicationName)",
                "Start booking in \(.applicationName)",
            ],
            shortTitle: "Book Appointment",
            systemImageName: "calendar.badge.plus"
        )

        AppShortcut(
            intent: FindPatientFromContactIntent(),
            phrases: [
                "Find a patient in \(.applicationName)",
                "Open a contact in \(.applicationName)",
            ],
            shortTitle: "Find Patient",
            systemImageName: "person.crop.badge.magnifyingglass"
        )
    }

    nonisolated static let shortcutTileColor: ShortcutTileColor = .teal
}
