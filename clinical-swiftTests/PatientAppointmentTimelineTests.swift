import ClinicalModels
import ClinicalPersistence
import Foundation
import SQLiteData
import Testing

@testable import clinical_swift

struct PatientAppointmentTimelineTests {
    @Test func queryFiltersByPatientAndStatusWithDeterministicLatestFirstOrdering() throws {
        let database = try testDatabase()
        let patientID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000010")
        )
        let otherPatientID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000020")
        )
        let emptyPatientID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000030")
        )
        let earliestCreationID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        )
        let lowerTiedID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")
        )
        let higherTiedID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000003")
        )
        let latestStartID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000004")
        )
        let cancelledID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000005")
        )
        let otherPatientAppointmentID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000006")
        )
        let base = Date(timeIntervalSinceReferenceDate: 10_000)
        let sharedStart = Date(timeIntervalSinceReferenceDate: 20_000)
        let latestStart = Date(timeIntervalSinceReferenceDate: 30_000)

        try database.write { db in
            for (id, name) in [
                (patientID, "Aarav Mehta"),
                (otherPatientID, "Anjali Desai"),
                (emptyPatientID, "Dev Malhotra"),
            ] {
                try PatientRecord.insert {
                    PatientRecord(
                        id: id,
                        name: name,
                        phone: nil,
                        dob: nil,
                        gender: nil,
                        createdAt: base,
                        updatedAt: base
                    )
                }
                .execute(db)
            }

            for fixture in [
                AppointmentFixture(
                    id: earliestCreationID,
                    patientID: patientID,
                    start: sharedStart,
                    status: .scheduled,
                    createdAt: base
                ),
                AppointmentFixture(
                    id: lowerTiedID,
                    patientID: patientID,
                    start: sharedStart,
                    status: .completed,
                    createdAt: base.addingTimeInterval(1)
                ),
                AppointmentFixture(
                    id: higherTiedID,
                    patientID: patientID,
                    start: sharedStart,
                    status: .scheduled,
                    createdAt: base.addingTimeInterval(1)
                ),
                AppointmentFixture(
                    id: latestStartID,
                    patientID: patientID,
                    start: latestStart,
                    status: .completed,
                    createdAt: base
                ),
                AppointmentFixture(
                    id: cancelledID,
                    patientID: patientID,
                    start: latestStart.addingTimeInterval(1),
                    status: .cancelled,
                    createdAt: base
                ),
                AppointmentFixture(
                    id: otherPatientAppointmentID,
                    patientID: otherPatientID,
                    start: latestStart.addingTimeInterval(2),
                    status: .scheduled,
                    createdAt: base
                ),
            ] {
                let record = try AppointmentRecord.persisted(
                    id: fixture.id,
                    patientID: fixture.patientID,
                    start: fixture.start,
                    durationMinutes: 30,
                    status: fixture.status,
                    createdAt: fixture.createdAt,
                    updatedAt: fixture.createdAt
                )
                try AppointmentRecord.insert { record }.execute(db)
            }
        }

        let records = try database.read { db in
            try patientTimelineAppointmentsQuery(patientID: patientID).fetchAll(db)
        }
        let emptyRecords = try database.read { db in
            try patientTimelineAppointmentsQuery(patientID: emptyPatientID).fetchAll(db)
        }

        #expect(
            records.map(\.id) == [
                latestStartID,
                higherTiedID,
                lowerTiedID,
                earliestCreationID,
            ]
        )
        #expect(
            records.map(\.status) == [
                "completed",
                "scheduled",
                "completed",
                "scheduled",
            ]
        )
        #expect(emptyRecords.isEmpty)
    }

    @Test func statusPresentationCoversEveryAppointmentStatus() {
        let scheduled = AppointmentStatusPresentation(status: .scheduled)
        let completed = AppointmentStatusPresentation(status: .completed)
        let draft = AppointmentStatusPresentation(status: .draft)
        let cancelled = AppointmentStatusPresentation(status: .cancelled)

        #expect(scheduled.label == "Scheduled")
        #expect(scheduled.systemImage == "clock")
        #expect(scheduled.statusColor == .accent)
        #expect(scheduled.timeColor == .text)
        #expect(completed.label == "Completed")
        #expect(completed.systemImage == "checkmark.circle")
        #expect(completed.statusColor == .success)
        #expect(completed.timeColor == .secondaryText)
        #expect(draft.label == "Draft")
        #expect(draft.systemImage == "clock")
        #expect(draft.statusColor == .accent)
        #expect(draft.timeColor == .text)
        #expect(cancelled.label == "Cancelled")
        #expect(cancelled.systemImage == "xmark.circle")
        #expect(cancelled.statusColor == .secondaryText)
        #expect(cancelled.timeColor == .secondaryText)
    }

    @Test func navigationTitleChangesWhenThePatientNameLeavesTheViewport() {
        let longName = "A Patient Name That Is Deliberately Long Enough To Truncate"

        #expect(
            PatientDetailsNavigationTitle.text(
                patientDisplayName: longName,
                isNameVisible: true
            ) == "Patient Details"
        )
        #expect(
            PatientDetailsNavigationTitle.text(
                patientDisplayName: longName,
                isNameVisible: false
            ) == longName
        )
        #expect(
            PatientDetailsNavigationTitle.text(
                patientDisplayName: Patient.unknownDisplayName,
                isNameVisible: false
            ) == Patient.unknownDisplayName
        )
    }

    private func testDatabase() throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let database = try DatabaseQueue(configuration: configuration)
        try migrateDatabase(database)
        return database
    }

    private struct AppointmentFixture {
        let id: Appointment.ID
        let patientID: Patient.ID
        let start: Date
        let status: Appointment.Status
        let createdAt: Date
    }
}
