import Dependencies
import Foundation
import SQLiteData
import Testing

@testable import clinical_swift

@MainActor
struct AppointmentBookingModelTests {
    @Test func dateChangePreservesAvailableClockTime() throws {
        let calendar = gregorianCalendar
        let initialDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let newDate = try Date("2026-04-22T00:00:00Z", strategy: .iso8601)

        withDependencies {
            $0.calendar = calendar
        } operation: {
            let model = AppointmentBookingModel(selectedDate: initialDate) { _ in }
            model.selectStart(initialDate.setTime(11, 0, using: calendar))

            model.selectDate(newDate)
            model.updateAppointments([], for: newDate)

            #expect(model.draft.start == newDate.setTime(11, 0, using: calendar))
        }
    }

    @Test func dateChangeFallsBackWhenClockTimeIsUnavailable() throws {
        let calendar = gregorianCalendar
        let initialDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let newDate = try Date("2026-04-22T00:00:00Z", strategy: .iso8601)
        let existingAppointment = Appointment(
            patientName: "Aarav Mehta",
            start: newDate.setTime(11, 0, using: calendar),
            durationMinutes: 30,
            status: .scheduled
        )

        withDependencies {
            $0.calendar = calendar
            $0.date.now = initialDate
        } operation: {
            let model = AppointmentBookingModel(selectedDate: initialDate) { _ in }
            model.selectStart(initialDate.setTime(11, 0, using: calendar))

            model.selectDate(newDate)
            model.updateAppointments([existingAppointment], for: newDate)

            #expect(model.draft.start == newDate.setTime(10, 0, using: calendar))
        }
    }

    @Test func dateChangeFallsBackWhenClockTimeCrossesBreak() throws {
        let calendar = gregorianCalendar
        let selectedDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let now = try Date("2026-04-20T00:00:00Z", strategy: .iso8601)

        withDependencies {
            $0.calendar = calendar
            $0.date.now = now
        } operation: {
            let model = AppointmentBookingModel(selectedDate: selectedDate) { _ in }
            model.selectDuration(60)
            model.selectStart(selectedDate.setTime(12, 30, using: calendar))

            model.updateAppointments([], for: selectedDate)

            #expect(model.draft.start == selectedDate.setTime(10, 0, using: calendar))
        }
    }

    @Test func todayInitialPrefillStartsAtNextFiveMinuteBoundary() throws {
        let calendar = gregorianCalendar
        let selectedDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let examples: [(now: Date, expectedStart: Date)] = [
            (
                try Date("2026-04-21T16:13:00Z", strategy: .iso8601),
                selectedDate.setTime(16, 15, using: calendar)
            ),
            (
                try Date("2026-04-21T16:01:00Z", strategy: .iso8601),
                selectedDate.setTime(16, 5, using: calendar)
            ),
            (
                try Date("2026-04-21T16:15:55Z", strategy: .iso8601),
                selectedDate.setTime(16, 15, using: calendar)
            ),
            (
                try Date("2026-04-21T16:16:00Z", strategy: .iso8601),
                selectedDate.setTime(16, 20, using: calendar)
            ),
        ]

        for example in examples {
            withDependencies {
                $0.calendar = calendar
                $0.date.now = example.now
            } operation: {
                let model = AppointmentBookingModel(selectedDate: selectedDate) { _ in }

                model.prefillFirstAvailableSlot()

                #expect(model.draft.start == example.expectedStart)
            }
        }
    }

    @Test func nonTodayInitialPrefillUsesPreferredDefaultRegardlessOfCurrentTime() throws {
        let calendar = gregorianCalendar
        let tomorrow = try Date("2026-04-22T00:00:00Z", strategy: .iso8601)
        let yesterday = try Date("2026-04-20T00:00:00Z", strategy: .iso8601)
        let now = try Date("2026-04-21T16:13:00Z", strategy: .iso8601)

        withDependencies {
            $0.calendar = calendar
            $0.date.now = now
        } operation: {
            let tomorrowModel = AppointmentBookingModel(selectedDate: tomorrow) { _ in }
            tomorrowModel.prefillFirstAvailableSlot()

            let yesterdayModel = AppointmentBookingModel(selectedDate: yesterday) { _ in }
            yesterdayModel.prefillFirstAvailableSlot()

            #expect(tomorrowModel.draft.start == tomorrow.setTime(10, 0, using: calendar))
            #expect(yesterdayModel.draft.start == yesterday.setTime(10, 0, using: calendar))
        }
    }

    @Test func dateChangeToTodayPreservesAvailableClockTimeEvenWhenPastCurrentTime() throws {
        let calendar = gregorianCalendar
        let today = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let tomorrow = try Date("2026-04-22T00:00:00Z", strategy: .iso8601)
        let now = try Date("2026-04-21T16:13:00Z", strategy: .iso8601)

        withDependencies {
            $0.calendar = calendar
            $0.date.now = now
        } operation: {
            let model = AppointmentBookingModel(selectedDate: tomorrow) { _ in }
            model.selectStart(tomorrow.setTime(11, 0, using: calendar))

            model.selectDate(today)
            model.updateAppointments([], for: today)

            #expect(model.draft.start == today.setTime(11, 0, using: calendar))
        }
    }

    @Test func durationChangePreservesStartWhenAppointmentStillFits() throws {
        let calendar = gregorianCalendar
        let selectedDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let existingAppointment = Appointment(
            patientName: "Aarav Mehta",
            start: selectedDate.setTime(13, 0, using: calendar),
            durationMinutes: 30,
            status: .scheduled
        )

        withDependencies {
            $0.calendar = calendar
        } operation: {
            let model = AppointmentBookingModel(selectedDate: selectedDate) { _ in }
            model.updateAppointments([existingAppointment], for: selectedDate)
            model.selectStart(selectedDate.setTime(11, 0, using: calendar))

            model.selectDuration(60)

            #expect(model.draft.start == selectedDate.setTime(11, 0, using: calendar))
        }
    }

    @Test func availabilityFallbackRequestsDraftPreviewScroll() throws {
        let calendar = gregorianCalendar
        let initialDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let newDate = try Date("2026-04-22T00:00:00Z", strategy: .iso8601)
        let existingAppointment = Appointment(
            patientName: "Aarav Mehta",
            start: newDate.setTime(11, 0, using: calendar),
            durationMinutes: 30,
            status: .scheduled
        )

        withDependencies {
            $0.calendar = calendar
            $0.date.now = initialDate
        } operation: {
            let model = AppointmentBookingModel(selectedDate: initialDate) { _ in }
            model.selectStart(initialDate.setTime(11, 0, using: calendar))
            let scrollRequestBeforeFallback = model.draftPreviewScrollRequest

            model.selectDate(newDate)
            model.updateAppointments([existingAppointment], for: newDate)

            #expect(model.draft.start == newDate.setTime(10, 0, using: calendar))
            #expect(model.draftPreviewScrollRequest == scrollRequestBeforeFallback + 1)
        }
    }

    @Test func manualStartSelectionRequestsDraftPreviewScroll() throws {
        let calendar = gregorianCalendar
        let selectedDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)

        withDependencies {
            $0.calendar = calendar
        } operation: {
            let model = AppointmentBookingModel(selectedDate: selectedDate) { _ in }
            #expect(model.draftPreviewScrollRequest == 0)

            model.selectStart(selectedDate.setTime(12, 0, using: calendar))

            #expect(model.draft.start == selectedDate.setTime(12, 0, using: calendar))
            #expect(model.draftPreviewScrollRequest == 1)
        }
    }

    @Test func staleAppointmentUpdateAfterDateChangeIsIgnored() throws {
        let calendar = gregorianCalendar
        let initialDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let newDate = try Date("2026-04-22T00:00:00Z", strategy: .iso8601)
        let staleAppointment = Appointment(
            patientName: "Aarav Mehta",
            start: initialDate.setTime(11, 0, using: calendar),
            durationMinutes: 30,
            status: .scheduled
        )

        withDependencies {
            $0.calendar = calendar
        } operation: {
            let model = AppointmentBookingModel(selectedDate: initialDate) { _ in }
            model.updateAppointments([staleAppointment], for: initialDate)

            model.selectDate(newDate)
            model.updateAppointments([staleAppointment], for: initialDate)

            #expect(model.appointments.isEmpty)
            #expect(model.draft.selectedDate == newDate)
        }
    }

    @Test func editingPreservesSavedDraftAndExcludesPersistedAppointment() throws {
        let calendar = gregorianCalendar
        let selectedDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let patient = Patient(name: "Aarav Mehta")
        let appointment = Appointment(
            patientName: patient.displayName,
            start: selectedDate.setTime(11, 0, using: calendar),
            durationMinutes: 45,
            status: .scheduled
        )
        let overlappingAppointment = Appointment(
            patientName: "Anjali Desai",
            start: appointment.start,
            durationMinutes: 30,
            status: .scheduled
        )

        withDependencies {
            $0.calendar = calendar
        } operation: {
            let model = AppointmentBookingModel(
                editing: AppointmentDetails(appointment: appointment, patient: patient)
            ) { _ in }

            model.updateAppointments(
                [appointment, overlappingAppointment],
                for: selectedDate
            )
            model.updateAppointments(
                [appointment, overlappingAppointment],
                for: selectedDate
            )

            #expect(model.purpose == .edit(appointment.id))
            #expect(model.draft.selectedPatient == patient)
            #expect(model.draft.start == appointment.start)
            #expect(model.draft.durationMinutes == appointment.durationMinutes)
            #expect(model.draftAppointment.id == appointment.id)
            #expect(model.appointments.map(\.id) == [overlappingAppointment.id])
        }
    }

    @Test func editingUpdatesMutableFieldsAndPreservesRecordIdentityAndStatus() async throws {
        let calendar = gregorianCalendar
        let database = try testDatabase()
        let selectedDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let originalPatient = Patient(name: "Aarav Mehta", createdDate: selectedDate)
        let newPatient = Patient(name: "Anjali Desai", createdDate: selectedDate)
        let appointmentID = UUID()
        let createdAt = selectedDate.setTime(8, 0, using: calendar)
        let updatedAt = selectedDate.setTime(9, 0, using: calendar)
        let originalStart = selectedDate.setTime(10, 0, using: calendar)
        let editedStart = selectedDate.setTime(17, 0, using: calendar)

        try await database.write { db in
            try PatientRecord.insert { PatientRecord(originalPatient) }.execute(db)
            try PatientRecord.insert { PatientRecord(newPatient) }.execute(db)
            let record = try AppointmentRecord.persisted(
                id: appointmentID,
                patientID: originalPatient.id,
                start: originalStart,
                durationMinutes: 30,
                status: .scheduled,
                createdAt: createdAt,
                updatedAt: createdAt
            )
            try AppointmentRecord.insert { record }
                .execute(db)
        }

        var savedDate: Date?
        let didSave = await withDependencies {
            $0.calendar = calendar
            $0.date.now = updatedAt
            $0.defaultDatabase = database
        } operation: {
            let model = AppointmentBookingModel(
                editing: AppointmentDetails(
                    appointment: Appointment(
                        id: appointmentID,
                        patientName: originalPatient.displayName,
                        start: originalStart,
                        durationMinutes: 30,
                        status: .scheduled
                    ),
                    patient: originalPatient
                )
            ) { savedDate = $0 }
            model.draft.selectedPatient = newPatient
            model.selectStart(editedStart)
            model.selectDuration(60)
            return await model.saveAppointment()
        }

        let record = try await database.read { db in
            try AppointmentRecord.find(appointmentID).fetchOne(db)
        }

        #expect(didSave)
        #expect(savedDate == editedStart)
        #expect(record?.id == appointmentID)
        #expect(record?.patientID == newPatient.id)
        #expect(record?.start == editedStart)
        #expect(record?.durationMinutes == 60)
        #expect(record?.status == Appointment.Status.scheduled.rawValue)
        #expect(record?.createdAt == createdAt)
        #expect(record?.updatedAt == updatedAt)
    }

    @Test func editingMissingAppointmentFailsWithoutCallingSaveCallback() async throws {
        let calendar = gregorianCalendar
        let database = try testDatabase()
        let selectedDate = try Date("2026-04-21T00:00:00Z", strategy: .iso8601)
        let patient = Patient(name: "Aarav Mehta", createdDate: selectedDate)
        var didCallSave = false

        let result = await withDependencies {
            $0.calendar = calendar
            $0.date.now = selectedDate
            $0.defaultDatabase = database
        } operation: {
            let model = AppointmentBookingModel(
                editing: AppointmentDetails(
                    appointment: Appointment(
                        patientName: patient.displayName,
                        start: selectedDate.setTime(10, 0, using: calendar),
                        durationMinutes: 30,
                        status: .scheduled
                    ),
                    patient: patient
                )
            ) { _ in didCallSave = true }
            return (await model.saveAppointment(), model.saveErrorMessage)
        }

        #expect(!result.0)
        #expect(result.1 == "This appointment can no longer be edited.")
        #expect(!didCallSave)
    }

    private var gregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func testDatabase() throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let database = try DatabaseQueue(configuration: configuration)
        try migrateDatabase(database)
        return database
    }
}
