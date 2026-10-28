#if DEBUG
    import ClinicalModels
    import ClinicalPersistence
    import Dependencies
    import Foundation
    import SQLiteData

    /// The snippet host keeps the app alive. Demo drafts and bookings can stay in memory.
    // TODO: Replace this demo store only if the snippet flow becomes a production feature.
    @MainActor @Observable
    final class BookingSnippetStore {
        private let database: any DatabaseWriter
        @ObservationIgnored @Dependency(\.date.now) private var now
        private var sessions: [String: BookingSnippetSession] = [:]
        private(set) var bookings: [Appointment] = []

        nonisolated init(database: any DatabaseWriter) {
            self.database = database
        }

        func patients(matching search: String = "") async throws -> [Patient] {
            let cutoff = now
            let patients = try await database.read { db in
                try appointmentBookingPatientRowsQuery(now: cutoff).fetchAll(db)
                    .map { Patient($0.patientRecord) }
            }
            return patients.filter { PatientNameSearch.matches($0.name, searchText: search) }
        }

        func patients(identifiedBy ids: [UUID]) async throws -> [Patient] {
            try await database.read { db in
                try PatientRecord.where { $0.id.in(ids) }.fetchAll(db).map(Patient.init)
            }
        }

        func begin(patient: Patient, date: Date? = nil) async throws -> BookingSnippetSession {
            let session = BookingSnippetSession(patient: patient, date: date ?? now)
            sessions[session.id] = session
            try await loadSchedule(session)
            session.model.prefillFirstAvailableSlot()
            return session
        }

        func session(_ id: String) throws -> BookingSnippetSession {
            guard let session = sessions[id] else { throw BookingSnippetError.expired }
            return session
        }

        func adjust(_ id: String, action: BookingSnippetAction, value: Int) async throws {
            let session = try session(id)
            guard session.booked == nil else { return }
            let model = session.model
            switch action {
            case .day:
                let date = model.selectedDate.date(byAddingDays: value, using: model.calendar)
                model.selectDate(date)
                try await loadSchedule(session)
            case .time:
                model.selectStart(model.draft.start.addingTimeInterval(TimeInterval(value * 60)))
            case .duration:
                model.selectDuration(value)
            case .slot:
                model.selectStart(
                    TimeOfDay(value / 60, value % 60).on(
                        date: model.selectedDate, using: model.calendar))
            }
        }

        func selectPatient(_ patient: Patient, sessionID: String) throws {
            try session(sessionID).model.draft.selectedPatient = patient
        }

        @discardableResult
        func book(_ id: String) throws -> Appointment {
            let session = try session(id)
            if let booked = session.booked { return booked }
            try session.model.draft.validate()
            let draft = session.model.draftAppointment
            let booked = Appointment(
                id: draft.id, patientName: draft.patientName,
                start: draft.start, durationMinutes: draft.durationMinutes, status: .scheduled)
            // This path must not call saveAppointment: trying the prototype must not write clinic data.
            bookings.append(booked)
            session.booked = booked
            return booked
        }

        private func loadSchedule(_ session: BookingSnippetSession) async throws {
            let date = session.model.selectedDate
            let appointments = try await database.read { db in
                try querySchedule(selectedDate: date).fetchAll(db).compactMap(
                    \.details?.appointment)
            }
            let calendar = session.model.calendar
            let demos = bookings.filter { calendar.isDate($0.start, inSameDayAs: date) }
            session.model.updateAppointments(appointments + demos, for: date)
        }
    }

    @MainActor @Observable
    final class BookingSnippetSession: Identifiable {
        let id = UUID().uuidString
        let model: AppointmentBookingModel
        var booked: Appointment?
        @ObservationIgnored @Dependency(\.date.now) private var now

        init(patient: Patient, date: Date) {
            model = AppointmentBookingModel(selectedDate: date, selectedPatient: patient) { _ in }
        }

        var schedule: [Appointment] {
            (model.appointments + [booked ?? model.draftAppointment]).sorted {
                if $0.start == $1.start { return $0.id.uuidString < $1.id.uuidString }
                return $0.start < $1.start
            }
        }

        var suggestedStarts: [Date] {
            let calendar = model.calendar
            let availability = AppointmentAvailability(
                searchDate: model.selectedDate, appointments: model.appointments, calendar: calendar
            )
            var earliest: Date?
            if calendar.isDate(model.selectedDate, inSameDayAs: now) {
                let minutes = TimeOfDay(date: now, calendar: calendar).totalMinutes
                earliest = now.startOfDay(using: calendar).addMinutes(
                    ((minutes + 4) / 5) * 5, using: calendar)
            }
            var starts: [Date] = []
            for _ in 0..<3 {
                guard
                    let start = availability.firstAvailableSlot(
                        neededDurationMinutes: model.draft.durationMinutes, earliestStart: earliest)
                else { break }
                starts.append(start)
                earliest = start.addMinutes(model.draft.durationMinutes, using: calendar)
            }
            return starts
        }

    }

    enum BookingSnippetError: LocalizedError {
        case expired
        var errorDescription: String? { "Start a new demo booking." }
    }
#endif
