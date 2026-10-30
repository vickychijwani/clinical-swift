#if DEBUG
    import ClinicalModels
    import ClinicalPersistence
    import Foundation
    import GRDB
    import SQLiteData

    /// Use the real details flow without clinic data, Calendar delivery, or backups.
    enum AppointmentCompletionUITestData {
        static func makeDatabase() throws -> DatabaseQueue {
            let database = try DatabaseQueue(configuration: clinicalDatabaseConfiguration())
            try migrateDatabase(database)
            try database.write { db in
                let patientID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
                let unknown = CommandLine.arguments.contains("--completion-unknown-patient")
                try PatientRecord.insert {
                    PatientRecord(
                        id: patientID, name: unknown ? nil : "Test Patient", phone: nil,
                        dob: nil, gender: nil, createdAt: .now, updatedAt: .now)
                }.execute(db)
                let appointmentID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10))
                let appointment = try AppointmentRecord.persisted(
                    id: appointmentID, patientID: patientID, start: Date.now.setTime(12, 0),
                    durationMinutes: 30, status: .scheduled, createdAt: .now, updatedAt: .now)
                try AppointmentRecord.insert { appointment }.execute(db)
                if CommandLine.arguments.contains("--completion-credit-conflict") {
                    try saveAccountEntries(
                        .init(inserts: [
                            AccountEntry(
                                details: .charge(
                                    patientID: patientID, appointmentID: appointmentID),
                                amount: 1500),
                            AccountEntry(
                                details: .receipt(source: .patient(patientID), paymentMethod: nil),
                                amount: 500),
                        ]), in: db)
                }
                if CommandLine.arguments.contains("--completion-delayed-save") {
                    // Hold the real transaction while UI tests check its disabled controls.
                    db.add(
                        function: DatabaseFunction("completion_test_delay", argumentCount: 0) { _ in
                            Thread.sleep(forTimeInterval: 3)
                            return 0
                        })
                    try db.execute(
                        sql: """
                            CREATE TEMP TRIGGER delay_completion BEFORE UPDATE OF status ON appointments
                            WHEN NEW.status = 'completed'
                            BEGIN SELECT completion_test_delay(); END
                            """)
                }
            }
            return database
        }
    }
#endif
