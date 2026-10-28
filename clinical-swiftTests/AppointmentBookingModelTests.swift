import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import SQLiteData
import Testing

@testable import clinical_swift

@MainActor
struct AppointmentBookingModelTests {
    @Test(arguments: [
        (TimeOfDay(9, 0), TimeOfDay(9, 0)),
        (TimeOfDay(9, 5), TimeOfDay(9, 0)),
        (TimeOfDay(12, 0), TimeOfDay(11, 45)),
        (TimeOfDay(12, 22), TimeOfDay(12, 0)),
        (TimeOfDay(12, 23), TimeOfDay(12, 15)),
        (TimeOfDay(12, 37), TimeOfDay(12, 15)),
        (TimeOfDay(12, 38), TimeOfDay(12, 30)),
        (TimeOfDay(14, 30), TimeOfDay(14, 15)),
        (TimeOfDay(20, 59), TimeOfDay(20, 30)),
        (TimeOfDay(21, 0), TimeOfDay(20, 30)),
    ])
    func timelineHoldSnapsCenteredStartToQuarterHourAndClampsAtClinicHours(
        center: TimeOfDay, expectedStart: TimeOfDay
    ) throws {
        let date = try Date("2026-10-26T00:00:00Z", strategy: .iso8601)
        withDependencies {
            $0.calendar = gregorianCalendar
            $0.date.now = date
        } operation: {
            let session = ScheduleEditorSession(
                bookingID: UUID(), selectedDate: date, center: center, items: [],
                onFinished: { _ in })
            guard case .appointment(let model) = session.editor else { return }
            #expect(
                model.draftAppointment.start
                    == expectedStart.on(date: date, using: gregorianCalendar))
            #expect(model.draftAppointment.start.timeOfDay.totalMinutes % 15 == 0)
            #expect(model.draftAppointment.durationMinutes == 30)
            #expect(model.adjustment.isDragging)
            #expect(!model.isSelectingPatient)
            session.updateAdjustment(translation: 0, items: [])
            #expect(
                model.draftAppointment.start
                    == expectedStart.on(date: date, using: gregorianCalendar))
        }
    }

    @Test func timelineBookingKeepsDraggedTimeThroughPatientSelectionAndSavesOnlyWithDone()
        async throws
    {
        let database = try testDatabase()
        let date = try Date("2026-10-26T00:00:00Z", strategy: .iso8601)
        let patient = Patient(name: "Patient", createdDate: date)
        try await database.write { db in
            try PatientRecord.insert { PatientRecord(patient, now: date) }.execute(db)
        }
        try await withDependencies {
            $0.calendar = gregorianCalendar
            $0.date.now = date
            $0.defaultDatabase = database
        } operation: {
            var savedDate: Date?
            let session = ScheduleEditorSession(
                bookingID: UUID(), selectedDate: date, center: TimeOfDay(12, 22), items: []
            ) { savedDate = $0 }
            guard case .appointment(let model) = session.editor else { return }
            let conflict = Appointment(
                patientName: "Other patient", start: date.addingTimeInterval(12 * 3600),
                durationMinutes: 60, status: .scheduled)
            session.updateAdjustment(translation: 7, items: [.appointment(conflict)])
            let id = model.draftAppointment.id
            let start = date.addingTimeInterval(12 * 3600 + 5 * 60)
            #expect(model.draftAppointment.start == start)
            #expect(model.draft.start == start)
            #expect(!model.isSelectingPatient)
            #expect(!(await model.saveAppointment()))
            model.releaseTimelineBooking()
            #expect(model.isSelectingPatient)
            #expect(!model.adjustment.isDragging)
            model.selectPatient(patient)
            model.updateAppointments([conflict], for: date)
            #expect(!model.isSelectingPatient)
            #expect(model.draftAppointment.id == id)
            #expect(model.draftAppointment.start == start)
            #expect(model.draftAppointment.patientName == patient.displayName)
            #expect(savedDate == nil)
            #expect(try await database.read { try AppointmentRecord.fetchAll($0).isEmpty })
            #expect(await model.saveAppointment())
            let records = try await database.read { try AppointmentRecord.fetchAll($0) }
            #expect(records.count == 1)
            #expect(records.first?.id == id)
            #expect(records.first?.start == start)
            #expect(records.first?.durationMinutes == 30)
            #expect(savedDate == start)
        }
    }

    @Test(arguments: [false, true])
    func timelineChangesStayUnsavedUntilDone(editing: Bool) async throws {
        let database = try testDatabase()
        let date = try Date("2026-10-25T12:00:00Z", strategy: .iso8601)
        let nextDate = try Date("2026-10-26T12:00:00Z", strategy: .iso8601)
        let patient = Patient(name: "Patient", createdDate: date)
        let appointment = Appointment(
            patientName: patient.displayName, start: date, durationMinutes: 30, status: .scheduled)
        try await database.write { db in
            try PatientRecord.insert { PatientRecord(patient, now: date) }.execute(db)
            if editing {
                let record = try AppointmentRecord.persisted(
                    id: appointment.id, patientID: patient.id, start: date,
                    durationMinutes: 30, status: .scheduled, createdAt: date, updatedAt: date)
                try AppointmentRecord.insert { record }.execute(db)
            }
        }
        try await withDependencies {
            $0.calendar = gregorianCalendar
            $0.date.now = date
            $0.defaultDatabase = database
        } operation: {
            var savedDate: Date?
            let request: AppPresentation =
                editing
                ? .appointmentEdit(
                    AppointmentEditRequest(
                        details: AppointmentDetails(
                            appointment: appointment, patient: patient)))
                : .appointmentBooking(AppointmentBookingRequest(patient: patient))
            let session = try #require(
                ScheduleEditorSession(
                    request: request, selectedDate: date, appointments: []
                ) { savedDate = $0 })
            guard case .appointment(let model) = session.editor else { return }
            model.selectStart(date)
            let draft = model.draftAppointment
            session.beginAdjustment(.appointment(draft), edge: .move, items: [.appointment(draft)])
            session.updateAdjustment(translation: 15, items: [.appointment(draft)])
            #expect(model.draft.start == date.addingTimeInterval(15 * 60))
            model.adjustment.release()
            session.beginAdjustment(
                .appointment(draft), edge: .duration, items: [.appointment(draft)])
            session.updateAdjustment(translation: -100, items: [.appointment(draft)])
            #expect(model.draft.durationMinutes == 15)
            model.adjustment.release()
            model.selectDate(nextDate)
            let conflict = Appointment(
                patientName: "Other patient", start: nextDate, durationMinutes: 120,
                status: .scheduled)
            model.updateAppointments([conflict], for: nextDate)
            let expectedStart = nextDate.addingTimeInterval(15 * 60)
            #expect(model.draftAppointment.start == expectedStart)
            #expect(model.draftAppointment.durationMinutes == 15)
            #expect(savedDate == nil)
            let before = try await database.read { try AppointmentRecord.fetchAll($0) }
            #expect(before.count == (editing ? 1 : 0))
            #expect(before.first?.start == (editing ? date : nil))
            #expect(before.first?.durationMinutes == (editing ? 30 : nil))

            await session.save()
            #expect(model.saveErrorMessage == nil)
            let after = try await database.read { try AppointmentRecord.fetchAll($0) }
            #expect(after.count == 1)
            #expect(after.first?.start == expectedStart)
            #expect(after.first?.durationMinutes == 15)
            #expect(after.first?.patientID == patient.id)
            #expect(savedDate == expectedStart)
        }
    }

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

    @Test func chargedAppointmentKeepsPatientAndReportsEditFailure() async throws {
        let database = try testDatabase()
        let calendar = gregorianCalendar
        let now = try Date("2026-10-24T09:00:00Z", strategy: .iso8601)
        let patient = Patient(name: "Aarav Mehta", createdDate: now)
        let other = Patient(name: "Anjali Desai", createdDate: now)
        let appointment = Appointment(
            patientName: patient.displayName,
            start: now.setTime(10, 0, using: calendar), durationMinutes: 30, status: .scheduled)
        try await withDependencies {
            $0.date.now = now
            $0.calendar = calendar
            $0.defaultDatabase = database
        } operation: {
            try await database.write { db in
                try PatientRecord.insert { PatientRecord(patient, now: now) }.execute(db)
                try PatientRecord.insert { PatientRecord(other, now: now) }.execute(db)
                let record = try AppointmentRecord.persisted(
                    id: appointment.id, patientID: patient.id,
                    start: appointment.start, durationMinutes: 30, status: .scheduled,
                    createdAt: now, updatedAt: now)
                try AppointmentRecord.insert { record }.execute(db)
                let charge = AccountEntry(
                    details: .charge(patientID: patient.id, appointmentID: appointment.id),
                    amount: 500, entryDate: now, createdDate: now)
                try saveAccountEntries(AccountEntryBatch(inserts: [charge]), in: db)
            }
            var didSave = false
            let model = AppointmentBookingModel(
                editing: AppointmentDetails(appointment: appointment, patient: patient)
            ) { _ in didSave = true }
            model.draft.selectedPatient = other
            #expect(await model.saveAppointment() == false)
            #expect(
                model.saveErrorMessage
                    == "This appointment has charges. Remove its linked charges before changing the patient."
            )
            #expect(!didSave)
            let saved = try await database.read {
                try AppointmentRecord.find(appointment.id).fetchOne($0)
            }
            #expect(saved?.patientID == patient.id)
            // A charge must not prevent a schedule edit for the same patient.
            model.draft.selectedPatient = patient
            model.selectStart(now.setTime(11, 0, using: calendar))
            #expect(await model.saveAppointment())
            #expect(didSave)
        }
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
