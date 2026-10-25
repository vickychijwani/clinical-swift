#if DEBUG
    import ClinicalModels
    import ClinicalPersistence
    import Dependencies
    import Foundation
    import SQLiteData
    import Testing

    @testable import clinical_swift

    @MainActor
    struct BookingSnippetTests {
        @Test func patientSearchUsesNameAutocompleteAndStableIDs() async throws {
            let database = try database()
            let patient = Patient(name: "Monica Mulchandani")
            let other = Patient(name: "Aarav Mehta")
            try await insert([patient, other], into: database)

            try await withDependencies {
                $0.date.now = try date("2026-10-25T04:00:00Z")
            } operation: {
                let store = BookingSnippetStore(database: database)
                let matches = try await store.patients(matching: "mon mul")
                #expect(matches.map(\.id) == [patient.id])
                #expect(try await store.patients(identifiedBy: [other.id]).map(\.id) == [other.id])
            }
        }

        @Test func bookingIsTemporaryIdempotentAndIncludedInTheNextDemo() async throws {
            let database = try database()
            let patient = Patient(name: "Aarav Mehta")
            try await insert([patient], into: database)
            let day = try date("2026-10-26T06:00:00Z")

            try await withDependencies {
                $0.calendar = .autoupdatingCurrent
                $0.date.now = try date("2026-10-25T04:00:00Z")
            } operation: {
                let store = BookingSnippetStore(database: database)
                let session = try await store.begin(patient: patient, date: day)
                let booked = try store.book(session.id)
                #expect(try store.book(session.id).id == booked.id)
                #expect(store.bookings.count == 1)
                #expect(session.booked?.id == booked.id)
                #expect(booked.status == .scheduled)
                let records = try await database.read { db in try AppointmentRecord.fetchAll(db) }
                #expect(records.isEmpty)

                let next = try await store.begin(patient: patient, date: day)
                #expect(next.model.appointments.map(\.id) == [booked.id])
                #expect(next.model.draft.start >= booked.end)
            }
        }

        @Test func scheduleContainsTheFullDayAndAllowsManualOverlaps() async throws {
            let database = try database()
            let patient = Patient(name: "Aarav Mehta")
            try await insert([patient], into: database)
            let day = try date("2026-10-26T06:00:00Z")
            let calendar = Calendar.autoupdatingCurrent
            let records = try (9..<15).map { hour in
                try AppointmentRecord.persisted(
                    id: UUID(), patientID: patient.id,
                    start: TimeOfDay(hour, 0).on(date: day, using: calendar), durationMinutes: 30,
                    status: .scheduled, createdAt: day, updatedAt: day)
            }
            try await database.write { db in
                for record in records { try AppointmentRecord.insert { record }.execute(db) }
            }

            try await withDependencies {
                $0.calendar = calendar
                $0.date.now = try date("2026-10-25T04:00:00Z")
            } operation: {
                let store = BookingSnippetStore(database: database)
                let session = try await store.begin(patient: patient, date: day)
                #expect(session.schedule.count == 7)
                let snapshot = BookingSnippetSnapshot(session)
                #expect(snapshot.appointments.count == 7)
                #expect(snapshot.appointments.contains { $0.status == .draft })
                #expect(
                    snapshot.appointments.map(\.start)
                        == snapshot.appointments.map(\.start).sorted())

                // Manual booking may overlap or cross the break. Open times are only suggestions.
                try await store.adjust(session.id, action: .slot, value: 12 * 60 + 45)
                try await store.adjust(session.id, action: .duration, value: 60)
                try await store.adjust(session.id, action: .slot, value: 12 * 60 + 45)
                #expect(session.model.draft.durationMinutes == 60)
                #expect(
                    TimeOfDay(date: session.model.draft.start, calendar: calendar)
                        == TimeOfDay(12, 45))
                #expect(session.schedule.contains { $0.status == .draft })
                #expect(throws: Never.self) { try store.book(session.id) }
            }
        }

        @Test func patientAndDayChangesKeepTheSameDraftAndSnapshotsHaveNoSideEffects() async throws
        {
            let database = try database()
            let first = Patient(name: "Aarav Mehta")
            let second = Patient(name: "Monica Mulchandani")
            try await insert([first, second], into: database)

            try await withDependencies {
                $0.calendar = .autoupdatingCurrent
                $0.date.now = try date("2026-10-25T04:00:00Z")
            } operation: {
                let store = BookingSnippetStore(database: database)
                let session = try await store.begin(patient: first)
                let id = session.model.draftAppointment.id
                let previousStart = session.model.draft.start
                try await store.adjust(session.id, action: .time, value: 15)
                #expect(session.model.draft.start == previousStart.addingTimeInterval(15 * 60))
                let previousDay = session.model.selectedDate
                try store.selectPatient(second, sessionID: session.id)
                try await store.adjust(session.id, action: .day, value: 1)
                #expect(session.model.draftAppointment.id == id)
                #expect(session.model.draft.selectedPatient?.id == second.id)
                #expect(session.model.selectedDate > previousDay)
                let firstSnapshot = BookingSnippetSnapshot(session)
                let secondSnapshot = BookingSnippetSnapshot(session)
                #expect(firstSnapshot.start == secondSnapshot.start)
                #expect(store.bookings.isEmpty)
                #expect(firstSnapshot.patientName == second.displayName)
            }
        }

        private func database() throws -> DatabaseQueue {
            let database = try DatabaseQueue(configuration: clinicalDatabaseConfiguration())
            try migrateDatabase(database)
            return database
        }

        private func insert(_ patients: [Patient], into database: DatabaseQueue) async throws {
            try await database.write { db in
                for patient in patients {
                    try PatientRecord.insert { PatientRecord(patient) }.execute(db)
                }
            }
        }

        private func date(_ string: String) throws -> Date {
            try Date(string, strategy: .iso8601)
        }
    }
#endif
