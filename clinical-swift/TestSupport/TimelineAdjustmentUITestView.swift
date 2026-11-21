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
                        onFinished: { router.finishScheduleEditor(request.id, date: $0.date) })
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

        static func makeDatabase() throws -> any DatabaseWriter {
            let database = try DatabaseQueue(configuration: clinicalDatabaseConfiguration())
            try migrateDatabase(database)
            let patient = patient
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
            }
            if CommandLine.arguments.contains("--ui-testing-gated-save") {
                // Pause the test writer so the UI can swipe while the real save is pending.
                // The test releases it after its checks, so runner speed cannot end it early.
                // Suspend async writes before entering DatabaseQueue so main-thread @FetchAll setups cannot deadlock.
                return GatedDatabaseWriter(base: database, gate: saveGate)
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
    final class UITestSaveGate {
        private(set) var isWaiting = false
        private var isReleased = false
        private var continuations: [CheckedContinuation<Void, Never>] = []

        /// Suspends async writes without blocking the DatabaseQueue serial queue.
        func waitAsync() async {
            guard !isReleased else { return }
            isWaiting = true
            await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
        }

        func release() {
            isReleased = true
            isWaiting = false
            let pending = continuations
            continuations.removeAll()
            for continuation in pending {
                continuation.resume()
            }
        }
    }

    /// Delays async database writes until the UI test releases the save gate.
    nonisolated final class GatedDatabaseWriter: DatabaseWriter {
        let base: DatabaseQueue
        let gate: UITestSaveGate

        init(base: DatabaseQueue, gate: UITestSaveGate) {
            self.base = base
            self.gate = gate
        }

        var configuration: Configuration { base.configuration }
        var path: String { base.path }
        func close() throws { try base.close() }
        func interrupt() { base.interrupt() }

        func read<T>(_ value: (Database) throws -> T) throws -> T {
            try base.read(value)
        }

        func read<T: Sendable>(_ value: @Sendable (Database) throws -> T) async throws -> T {
            try await base.read(value)
        }

        func asyncRead(_ value: @escaping @Sendable (Result<Database, Error>) -> Void) {
            base.asyncRead(value)
        }

        func unsafeRead<T>(_ value: (Database) throws -> T) throws -> T {
            try base.unsafeRead(value)
        }

        func unsafeRead<T: Sendable>(_ value: @Sendable (Database) throws -> T) async throws -> T {
            try await base.unsafeRead(value)
        }

        func asyncUnsafeRead(_ value: @escaping @Sendable (Result<Database, Error>) -> Void) {
            base.asyncUnsafeRead(value)
        }

        func unsafeReentrantRead<T>(_ value: (Database) throws -> T) throws -> T {
            try base.unsafeReentrantRead(value)
        }

        func _add<Reducer: ValueReducer>(
            observation: ValueObservation<Reducer>,
            scheduling scheduler: some ValueObservationScheduler,
            onChange: @escaping @Sendable (Reducer.Value) -> Void
        ) -> AnyDatabaseCancellable {
            base._add(observation: observation, scheduling: scheduler, onChange: onChange)
        }

        func writeWithoutTransaction<T>(_ updates: (Database) throws -> T) rethrows -> T {
            try base.writeWithoutTransaction(updates)
        }

        func writeWithoutTransaction<T: Sendable>(
            _ updates: @Sendable (Database) throws -> T
        ) async throws -> T {
            await gate.waitAsync()
            return try await base.writeWithoutTransaction(updates)
        }

        func barrierWriteWithoutTransaction<T>(_ updates: (Database) throws -> T) throws -> T {
            try base.barrierWriteWithoutTransaction(updates)
        }

        func barrierWriteWithoutTransaction<T: Sendable>(
            _ updates: @Sendable (Database) throws -> T
        ) async throws -> T {
            try await base.barrierWriteWithoutTransaction(updates)
        }

        func asyncBarrierWriteWithoutTransaction(
            _ updates: @escaping @Sendable (Result<Database, Error>) -> Void
        ) {
            base.asyncBarrierWriteWithoutTransaction(updates)
        }

        func asyncWriteWithoutTransaction(_ updates: @escaping @Sendable (Database) -> Void) {
            base.asyncWriteWithoutTransaction(updates)
        }

        func unsafeReentrantWrite<T>(_ updates: (Database) throws -> T) rethrows -> T {
            try base.unsafeReentrantWrite(updates)
        }

        func spawnConcurrentRead(_ value: @escaping @Sendable (Result<Database, Error>) -> Void) {
            base.spawnConcurrentRead(value)
        }
    }
#endif
