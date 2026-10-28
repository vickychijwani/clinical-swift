#if DEBUG
    import AppIntents
    import ClinicalModels
    import Foundation
    import SwiftUI

    nonisolated struct BookingPatientEntity: AppEntity {
        static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Patient")
        static let defaultQuery = BookingPatientQuery()
        let id: UUID
        let name: String
        let phone: String?

        init(_ patient: Patient) {
            id = patient.id
            name = patient.displayName
            phone = patient.phone
        }

        var displayRepresentation: DisplayRepresentation {
            DisplayRepresentation(title: "\(name)", subtitle: "\(phone ?? "Bitehaus patient")")
        }
    }

    struct BookingPatientQuery: EntityStringQuery {
        @AppDependency private var store: BookingSnippetStore

        nonisolated init() {}

        func entities(for identifiers: [UUID]) async throws -> [BookingPatientEntity] {
            try await store.patients(identifiedBy: identifiers).map(BookingPatientEntity.init)
        }

        func entities(matching string: String) async throws -> [BookingPatientEntity] {
            try await store.patients(matching: string).map(BookingPatientEntity.init)
        }

        func suggestedEntities() async throws -> [BookingPatientEntity] {
            try await store.patients().map(BookingPatientEntity.init)
        }
    }

    struct TrySnippetBookingIntent: AppIntent {
        nonisolated static let title: LocalizedStringResource = "Try Snippet Booking"
        nonisolated static let description = IntentDescription(
            "Try booking with patient search and an interactive day schedule. Demo bookings stay in memory."
        )
        nonisolated static let supportedModes: IntentModes = .background

        @Parameter(title: "Patient", requestValueDialog: "Who is the appointment for?")
        var patient: BookingPatientEntity

        @AppDependency private var store: BookingSnippetStore

        nonisolated static var parameterSummary: some ParameterSummary {
            Summary("Try booking for \(\.$patient)")
        }

        @MainActor
        func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetIntent {
            guard let patient = try await store.patients(identifiedBy: [patient.id]).first else {
                throw BookingSnippetError.expired
            }
            let session = try await store.begin(patient: patient)
            try await requestConfirmation(
                actionName: .book,
                dialog: "Choose a time for \(patient.displayName). This is a demo booking.",
                showDialogAsPrompt: false,
                snippetIntent: BookingDaySnippetIntent(sessionID: session.id)
            )
            let appointment = try store.book(session.id)
            return .result(
                dialog:
                    "Demo booked for \(appointment.patientName) at \(appointment.start.formatted(date: .abbreviated, time: .shortened)).",
                snippetIntent: BookingDaySnippetIntent(sessionID: session.id)
            )
        }
    }

    struct BookingDaySnippetIntent: SnippetIntent {
        nonisolated static let title: LocalizedStringResource = "Booking Day"
        nonisolated static let isDiscoverable = false
        @Parameter(title: "Session") var sessionID: String
        @AppDependency private var store: BookingSnippetStore

        init() {}
        init(sessionID: String) { self.sessionID = sessionID }

        @MainActor
        func perform() async throws -> some IntentResult & ShowsSnippetView {
            let session = try store.session(sessionID)
            // Render a value snapshot. The system reruns this intent after each button action.
            return .result(view: BookingSnippetView(snapshot: BookingSnippetSnapshot(session)))
        }
    }

    nonisolated enum BookingSnippetAction: String, AppEnum {
        case day, time, duration, slot
        static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Booking adjustment")
        static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
            .day: "Day", .time: "Time", .duration: "Duration", .slot: "Suggested time",
        ]
    }

    struct AdjustBookingSnippetIntent: AppIntent {
        nonisolated static let title: LocalizedStringResource = "Adjust Demo Booking"
        nonisolated static let isDiscoverable = false
        @Parameter(title: "Session") var sessionID: String
        @Parameter(title: "Adjustment") var action: BookingSnippetAction
        @Parameter(title: "Value") var value: Int
        @AppDependency private var store: BookingSnippetStore

        init() {}
        init(sessionID: String, action: BookingSnippetAction, value: Int) {
            self.sessionID = sessionID
            self.action = action
            self.value = value
        }

        @MainActor
        func perform() async throws -> some IntentResult {
            try await store.adjust(sessionID, action: action, value: value)
            return .result()
        }
    }

#endif
