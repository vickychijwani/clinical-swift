#if DEBUG
    import ClinicalModels
    import ClinicalPersistence
    import GRDB
    import SQLiteData
    import SwiftUI

    /// Exercise the real schedule, toolbar, and tabs with an isolated database.
    struct TimelineAdjustmentUITestView: View {
        @State private var router: Router
        @State private var initialEditorSession: ScheduleEditorSession?
        private static let patient = Patient(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)),
            name: "Test Patient")
        private static let saveGate = UITestSaveGate()

        init() {
            let router = Router()
            _router = State(initialValue: router)
            if CommandLine.arguments.contains("--ui-testing-selected-draft") {
                router.requestScheduleCreation()
                guard let request = router.activePresentation,
                    let session = ScheduleEditorSession(
                        request: request, selectedDate: router.selectedScheduleDate,
                        appointments: [],
                        onFinished: { router.finishScheduleEditor(request.id, date: $0) })
                else { preconditionFailure("The fixture must create a schedule editor.") }
                session.selectPatient(Self.patient)
                guard case .appointment(let model) = session.editor else {
                    preconditionFailure("The fixture must create an appointment draft.")
                }
                let minute = CommandLine.arguments.contains("--ui-testing-draft-at-1215") ? 15 : 0
                model.draft.selectStart(router.selectedScheduleDate.setTime(12, minute))
                session.isShowingSheet = false
                _initialEditorSession = State(initialValue: session)
            } else {
                _initialEditorSession = State(initialValue: nil)
            }
        }

        static func makeDatabase() throws -> DatabaseQueue {
            let database = try DatabaseQueue(configuration: clinicalDatabaseConfiguration())
            try migrateDatabase(database)
            let patient = patient
            let gate = saveGate
            try database.write { db in
                try PatientRecord.insert {
                    PatientRecord(patient, now: .now)
                }.execute(db)
                for (suffix, day, hour, minute) in [
                    (10, 0, 12, 0), (11, 0, 12, 15), (12, 1, 12, 0),
                ] {
                    let id = UUID(
                        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, UInt8(suffix)))
                    let start = Date.now.date(byAddingDays: day).setTime(hour, minute)
                    let record = try AppointmentRecord.persisted(
                        id: id, patientID: patient.id, start: start, durationMinutes: 30,
                        status: .scheduled, createdAt: .now, updatedAt: .now)
                    try AppointmentRecord.insert { record }.execute(db)
                }
                try UnavailableTimeRecord.insert {
                    UnavailableTimeRecord(
                        id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 20)),
                        label: "Travel", start: Date.now.setTime(11, 0), durationMinutes: 30,
                        createdAt: .now, updatedAt: .now)
                }.execute(db)
                if CommandLine.arguments.contains("--ui-testing-gated-save") {
                    // Pause the test writer so the UI can swipe while the real save is pending.
                    // The test releases it after its checks, so runner speed cannot end it early.
                    db.add(
                        function: GRDB.DatabaseFunction("ui_test_save_gate", argumentCount: 0) {
                            _ in
                            gate.wait()
                            return 0
                        })
                    try db.execute(
                        sql: """
                            CREATE TEMP TRIGGER gate_appointment_save BEFORE INSERT ON appointments
                            BEGIN SELECT ui_test_save_gate(); END
                            """)
                }
            }
            return database
        }

        var body: some View {
            ContentView(router: router, initialEditorSession: initialEditorSession)
                .overlay(alignment: .top) {
                    if Self.saveGate.isWaiting {
                        Button("Finish test save") { Self.saveGate.release() }
                            .accessibilityIdentifier("release-test-save")
                    }
                }
                .overlay(alignment: .bottom) {
                    if router.detailsPresentation != nil {
                        Text("Appointment details").accessibilityIdentifier("details-opened")
                    }
                }
        }
    }

    @MainActor @Observable
    private final class UITestSaveGate {
        private(set) var isWaiting = false
        private nonisolated let condition = NSConditionLock(condition: 0)

        nonisolated func wait() {
            Task { @MainActor in isWaiting = true }
            // GRDB requires a synchronous callback. Block only its writer, until release sets 1.
            condition.lock(whenCondition: 1)
            condition.unlock(withCondition: 1)
        }

        func release() {
            condition.lock()
            condition.unlock(withCondition: 1)
            isWaiting = false
        }
    }
#endif
