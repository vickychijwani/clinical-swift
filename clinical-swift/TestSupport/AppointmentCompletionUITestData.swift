#if DEBUG
    import ClinicalModels
    import ClinicalPersistence
    import Foundation
    import GRDB
    import SQLiteData

    /// Use the real details flow without clinic data, Calendar delivery, or backups.
    enum AppointmentCompletionUITestData {
        static let saveGate = UITestSaveGate()

        static func openForm(router: Router, database: DatabaseQueue) throws {
            let id = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10))
            guard
                let details = try database.read({ db in
                    try appointmentDetailsQuery(id: id).fetchOne(db)?.details
                })
            else { preconditionFailure("The fixture must contain the appointment.") }
            router.openAppointment(id: id)
            guard let presentation = router.detailsPresentation else {
                preconditionFailure("The fixture must open appointment details.")
            }
            router.beginAppointmentCompletion(
                details, visitID: presentation.visitID, presentationID: presentation.id)
        }

        static func makeDatabase() throws -> DatabaseQueue {
            let database = try DatabaseQueue(configuration: clinicalDatabaseConfiguration())
            try migrateDatabase(database)
            let gate = saveGate
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
                if CommandLine.arguments.contains("--completion-gated-save") {
                    // Hold the real transaction while UI tests check its disabled controls.
                    // Only the test can release it, so a slow runner cannot miss the saving state.
                    db.add(
                        function: DatabaseFunction("completion_test_gate", argumentCount: 0) { _ in
                            gate.wait()
                            return 0
                        })
                    try db.execute(
                        sql: """
                            CREATE TEMP TRIGGER gate_completion BEFORE UPDATE OF status ON appointments
                            WHEN NEW.status = 'completed'
                            BEGIN SELECT completion_test_gate(); END
                            """)
                }
            }
            return database
        }
    }
#endif
