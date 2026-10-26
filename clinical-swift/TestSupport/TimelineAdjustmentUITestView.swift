#if DEBUG
    import ClinicalModels
    import ClinicalPersistence
    import SQLiteData
    import SwiftUI

    /// Exercise the real schedule, toolbar, and tabs with an isolated database.
    struct TimelineAdjustmentUITestView: View {
        @State private var router = Router()
        static func makeDatabase() throws -> DatabaseQueue {
            let database = try DatabaseQueue(configuration: clinicalDatabaseConfiguration())
            try migrateDatabase(database)
            try database.write { db in
                let patientID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
                try PatientRecord.insert {
                    PatientRecord(
                        id: patientID, name: "Test Patient", phone: nil, dob: nil,
                        gender: nil, createdAt: .now, updatedAt: .now)
                }.execute(db)
                for (suffix, day, hour, minute) in [
                    (10, 0, 12, 0), (11, 0, 12, 15), (12, 1, 12, 0),
                ] {
                    let id = UUID(
                        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, UInt8(suffix)))
                    let start = Date.now.date(byAddingDays: day).setTime(hour, minute)
                    let record = try AppointmentRecord.persisted(
                        id: id, patientID: patientID, start: start, durationMinutes: 30,
                        status: .scheduled, createdAt: .now, updatedAt: .now)
                    try AppointmentRecord.insert { record }.execute(db)
                }
                try UnavailableTimeRecord.insert {
                    UnavailableTimeRecord(
                        id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 20)),
                        label: "Travel", start: Date.now.setTime(11, 0), durationMinutes: 30,
                        createdAt: .now, updatedAt: .now)
                }.execute(db)
            }
            return database
        }

        var body: some View {
            TabView(selection: $router.selectedTab) {
                Tab("Schedule", systemImage: "calendar", value: AppTab.schedule) {
                    NavigationStack { ScheduleView() }
                }
                Tab("Patients", systemImage: "person.2", value: AppTab.patients) {
                    Text("Patients")
                }
            }
            .environment(router)
            .overlay(alignment: .bottom) {
                if router.detailsPresentation != nil {
                    Text("Appointment details").accessibilityIdentifier("details-opened")
                }
            }
        }
    }
#endif
