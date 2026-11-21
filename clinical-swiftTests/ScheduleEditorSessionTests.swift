import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import SQLiteData
import Testing

@testable import clinical_swift

@MainActor
struct ScheduleEditorSessionTests {
    @Test(arguments: [false, true])
    func concurrentSavesFinishOnceAndPreventFurtherChanges(unavailable: Bool) async throws {
        let database = try testDatabase()
        let date = try Date("2026-10-02T00:00:00+05:30", strategy: .iso8601)
        let patient = Patient(name: "Patient", createdDate: date)
        try await database.write { db in
            try PatientRecord.insert { PatientRecord(patient, now: date) }.execute(db)
        }
        try await withDependencies {
            $0.date.now = date
            $0.defaultDatabase = database
        } operation: {
            var finishedDates: [Date] = []
            let session = ScheduleEditorSession(
                request: .create(), selectedDate: date,
                appointments: []
            ) { finishedDates.append($0.date) }
            session.selectPatient(patient)
            if unavailable { session.selectType(.unavailableTime) }
            let preview = session.preview
            let first = Task { await session.save() }
            let second = Task { await session.save() }
            let results = await [first.value, second.value]
            #expect(results.filter { $0 }.count == 1)
            #expect(finishedDates == [preview.start])
            #expect(session.didFinish)
            #expect(!session.isWorking)
            #expect(session.errorMessage == nil)
            session.selectType(unavailable ? .appointment : .unavailableTime)
            session.selectDate(date.addingTimeInterval(24 * 3600))
            session.selectPatient(Patient(name: "Other patient", createdDate: date))
            #expect(session.preview.id == preview.id)
            #expect(session.preview.start == preview.start)
            #expect(session.preview.durationMinutes == preview.durationMinutes)
            if case .appointment(let model) = session.editor {
                #expect(model.draft.selectedPatient == patient)
            }
            #expect(!(await session.save()))
            let counts = try await database.read { db in
                (
                    try AppointmentRecord.count().fetchOne(db),
                    try UnavailableTimeRecord.count().fetchOne(db)
                )
            }
            #expect(counts.0 == (unavailable ? 0 : 1))
            #expect(counts.1 == (unavailable ? 1 : 0))
        }
    }

    @Test(arguments: [false, true])
    func dateChangeKeepsManualIntervalAcrossConflictsAndBreaks(hold: Bool) throws {
        let today = try Date("2026-10-02T00:00:00+05:30", strategy: .iso8601)
        let tomorrow = try Date("2026-10-03T00:00:00+05:30", strategy: .iso8601)
        let start = try Date("2026-10-02T12:30:00+05:30", strategy: .iso8601)
        let now = try Date("2026-10-02T16:13:00+05:30", strategy: .iso8601)
        withDependencies {
            $0.date.now = now
        } operation: {
            let session = genericSession(
                request: .create(), date: tomorrow, hold: hold)
            guard case .appointment(let model) = session.editor else {
                Issue.record("The session must contain an appointment editor.")
                return
            }
            session.adjustment.release()
            model.draft.selectStart(tomorrow.setTime(12, 30, using: ClinicDate.calendar))
            model.draft.selectDuration(60)
            let before = session.scrollRequest
            session.selectDate(today)
            let conflict = TimelineItem.appointment(
                Appointment(
                    patientName: "Other patient", start: start, durationMinutes: 120,
                    status: .scheduled))
            #expect(session.visibleItems([conflict], for: today).count == 2)
            #expect(session.preview.start == start)
            #expect(session.preview.durationMinutes == 60)
            #expect(model.draft.selectedDate == today)
            #expect(session.scrollRequest.revision == before.revision + 1)
        }
    }

    @Test(arguments: [false, true])
    func draftIdentityPreventsDraggingAnotherItem(unavailable: Bool) throws {
        let start = try Date("2026-10-02T12:00:00+05:30", strategy: .iso8601)
        let session = editingSession(unavailable: unavailable, start: start)
        let draft = session.preview
        let other: TimelineItem =
            switch draft.id {
            case .appointment(let id):
                .unavailableTime(UnavailableTime(id: id, start: start, durationMinutes: 30))
            case .unavailableTime(let id):
                .appointment(
                    Appointment(
                        id: id, patientName: "Other", start: start, durationMinutes: 30,
                        status: .scheduled))
            }
        session.beginAdjustment(other, edge: .move, items: [draft, other])
        session.updateAdjustment(translation: 15, items: [draft, other])
        #expect(!session.adjustment.isDragging)
        #expect(session.preview.id == draft.id)
        #expect(session.preview.start == start)
    }

    @Test(arguments: [false, true])
    func dateSelectionPreservesDraftAndMovesItBetweenPages(unavailable: Bool) throws {
        let calendar = ClinicDate.calendar
        let start = try Date("2026-10-02T00:00:00+05:30", strategy: .iso8601)
            .setTime(14, 0, using: calendar)
        let nextStart = start.date(byAddingDays: 1, using: calendar).setTime(14, 0, using: calendar)
        let session = editingSession(unavailable: unavailable, start: start)
        let original = session.preview
        session.beginAdjustment(original, edge: .move, items: [original])
        session.adjustment.release()
        session.selectDate(nextStart)
        #expect(session.preview.id == original.id)
        #expect(session.preview.start == nextStart)
        #expect(session.preview.durationMinutes == original.durationMinutes)
        #expect(session.visibleItems([original], for: start).isEmpty)
        #expect(session.visibleItems([], for: nextStart).map(\.id) == [original.id])
        #expect(session.scale([], on: nextStart).isBreakExpanded)
        #expect(!session.scale([], on: start).isBreakExpanded)
    }

    @Test(arguments: [false, true])
    func dateSelectionKeepsClinicClockTimeAcrossUSDaylightSavingChange(unavailable: Bool) throws {
        let start = try Date("2026-10-31T12:00:00+05:30", strategy: .iso8601)
        let nextStart = try Date("2026-11-01T12:00:00+05:30", strategy: .iso8601)
        let session = editingSession(unavailable: unavailable, start: start)
        session.selectDate(nextStart)
        #expect(session.preview.start == nextStart)
        #expect(session.preview.durationMinutes == 45)
    }

    @Test(arguments: [false, true])
    func nextGestureUsesDraftControlAndMetadataChanges(unavailable: Bool) throws {
        let start = try Date("2026-10-02T12:00:00+05:30", strategy: .iso8601)
        let selectedStart = try Date("2026-10-02T16:00:00+05:30", strategy: .iso8601)
        let session = editingSession(unavailable: unavailable, start: start)
        let staleItem = session.preview
        session.beginAdjustment(staleItem, edge: .move, items: [])
        session.updateAdjustment(translation: 15, items: [])
        session.adjustment.release()
        let patient = Patient(name: "Changed patient", createdDate: start)
        switch session.editor {
        case .appointment(let model):
            session.selectPatient(patient)
            model.draft.selectStart(selectedStart)
            model.draft.selectDuration(45)
        case .unavailableTime(let model):
            model.draft.label = "Changed label"
            session.isShowingSheet = false
            model.draft.start = selectedStart
            model.draft.durationMinutes = 45
        }
        #expect(session.preview.start == selectedStart)
        #expect(session.preview.durationMinutes == 45)
        session.beginAdjustment(staleItem, edge: .move, items: [])
        session.updateAdjustment(translation: 15, items: [])
        #expect(session.preview.start == selectedStart.addingTimeInterval(15 * 60))
        #expect(session.preview.durationMinutes == 45)
        switch session.preview {
        case .appointment(let appointment):
            #expect(appointment.patientName == patient.displayName)
        case .unavailableTime(let block):
            #expect(block.label == "Changed label")
        }
    }

    private func editingSession(unavailable: Bool, start: Date) -> ScheduleEditorSession {
        let request: ScheduleEditorRequest =
            unavailable
            ? .editUnavailableTime(
                UnavailableTime(label: "Travel", start: start, durationMinutes: 45))
            : .editAppointment(
                AppointmentDetails(
                    appointment: Appointment(
                        patientName: "Patient", start: start, durationMinutes: 45,
                        status: .scheduled),
                    patient: Patient(name: "Patient", createdDate: start)))
        return ScheduleEditorSession(
            request: request, selectedDate: start, appointments: [], onFinished: { _ in })
    }

    @Test func initialHoldUsesItsOwnAdjustmentAndDoneRequiresPatientSelection() async throws {
        let date = try Date("2026-10-02T00:00:00+05:30", strategy: .iso8601)
        await withDependencies {
            $0.date.now = date
        } operation: {
            var didFinish = false
            let id = UUID()
            let session = ScheduleEditorSession(
                bookingID: id, selectedDate: date, center: TimeOfDay(12, 0), items: []
            ) { _ in didFinish = true }
            #expect(session.id == id)
            #expect(session.adjustment.isDragging)
            #expect(!session.isShowingSheet)
            #expect(!session.canDelete)
            let preview = session.preview
            session.releaseBooking(TimelineAdjustment())
            #expect(session.adjustment.isDragging)
            #expect(!session.isShowingSheet)
            session.adjustment.release()
            session.releaseBooking(session.adjustment)
            #expect(!session.adjustment.isDragging)
            #expect(session.isShowingSheet)
            session.isShowingSheet = false
            await session.save()
            #expect(session.isShowingSheet)
            #expect(session.preview.id == preview.id)
            #expect(session.preview.start == preview.start)
            #expect(session.preview.durationMinutes == preview.durationMinutes)
            #expect(session.errorMessage == nil)
            #expect(!didFinish)
        }
    }

    @Test(arguments: [false, true])
    func saveReleasesDragAndKeepsFailedPreviewForRetry(unavailable: Bool) async throws {
        let database = try testDatabase()
        let date = try Date("2026-10-02T00:00:00+05:30", strategy: .iso8601)
        let patient = Patient(name: "Patient", createdDate: date)
        try await database.write { db in
            try PatientRecord.insert { PatientRecord(patient, now: date) }.execute(db)
        }
        try await withDependencies {
            $0.date.now = date
            $0.defaultDatabase = database
        } operation: {
            var finishedDates: [Date] = []
            let request = ScheduleEditorRequest.create()
            let session = ScheduleEditorSession(
                request: request, selectedDate: date, appointments: []
            ) { finishedDates.append($0.date) }
            session.selectPatient(patient)
            if unavailable { session.selectType(.unavailableTime) }
            session.isShowingSheet = false
            session.beginAdjustment(session.preview, edge: .move, items: [])
            session.updateAdjustment(translation: 15, items: [])
            let preview = session.preview
            let table = unavailable ? "unavailableTimes" : "appointments"
            try await database.write { db in
                try db.execute(
                    sql: """
                        CREATE TRIGGER reject_session_save BEFORE INSERT ON \(table)
                        BEGIN SELECT RAISE(ABORT, 'test failure'); END
                        """)
            }
            await session.save()
            #expect(!session.adjustment.isDragging)
            #expect(session.preview.id == preview.id)
            #expect(session.preview.start == preview.start)
            #expect(session.preview.durationMinutes == preview.durationMinutes)
            #expect(session.errorMessage != nil)
            #expect(
                session.errorTitle
                    == (unavailable
                        ? "Unable to change unavailable time" : "Unable to save appointment"))
            #expect(!session.isWorking)
            #expect(session.allowsDateSelection)
            #expect(finishedDates.isEmpty)
            session.errorMessage = nil
            #expect(session.errorMessage == nil)
            try await database.write { db in try db.execute(sql: "DROP TRIGGER reject_session_save")
            }
            await session.save()
            #expect(finishedDates == [preview.start])
            #expect(session.errorMessage == nil)
            let starts = try await database.read { db in
                if unavailable {
                    return try UnavailableTimeRecord.fetchAll(db).map(\.start)
                }
                return try AppointmentRecord.fetchAll(db).map(\.start)
            }
            #expect(starts == [preview.start])
        }
    }

    @Test(arguments: [Appointment.Status.completed, .cancelled])
    func editingTerminalAppointmentKeepsPreviewAndReportsError(status: Appointment.Status)
        async throws
    {
        let database = try testDatabase()
        let date = try Date("2026-10-02T11:00:00+05:30", strategy: .iso8601)
        let patient = Patient(name: "Patient", createdDate: date)
        let appointment = Appointment(
            patientName: patient.displayName, start: date, durationMinutes: 30, status: .scheduled)
        let record = try AppointmentRecord.persisted(
            id: appointment.id, patientID: patient.id, start: date,
            durationMinutes: 30, status: status, createdAt: date, updatedAt: date)
        try await database.write { db in
            try PatientRecord.insert { PatientRecord(patient, now: date) }.execute(db)
            try AppointmentRecord.insert { record }.execute(db)
        }
        try await withDependencies {
            $0.date.now = date
            $0.defaultDatabase = database
        } operation: {
            var didFinish = false
            let session = ScheduleEditorSession(
                request: .editAppointment(
                    AppointmentDetails(appointment: appointment, patient: patient)),
                selectedDate: date, appointments: [appointment]
            ) { _ in didFinish = true }
            session.beginAdjustment(session.preview, edge: .move, items: [])
            session.updateAdjustment(translation: 15, items: [])
            let preview = session.preview
            await session.save()
            #expect(!didFinish)
            #expect(session.errorMessage == "This appointment can no longer be edited.")
            #expect(session.preview.start == preview.start)
            let record = try #require(
                try await database.read { try AppointmentRecord.find(appointment.id).fetchOne($0) })
            #expect(record.start == date)
            #expect(record.status == status.rawValue)
        }
    }

    @Test func deletingMovedBlockUsesItsSavedIdentity() async throws {
        let database = try testDatabase()
        let date = try Date("2026-10-02T11:00:00+05:30", strategy: .iso8601)
        let nextDate = try Date("2026-10-03T00:00:00+05:30", strategy: .iso8601)
        let block = UnavailableTime(label: "Travel", start: date, durationMinutes: 60)
        try await database.write { db in
            try UnavailableTimeRecord.insert {
                UnavailableTimeRecord(
                    id: block.id, label: block.label, start: block.start,
                    durationMinutes: block.durationMinutes, createdAt: date, updatedAt: date)
            }.execute(db)
        }
        try await withDependencies {
            $0.date.now = date
            $0.defaultDatabase = database
        } operation: {
            var finishedDates: [Date] = []
            let session = ScheduleEditorSession(
                request: .editUnavailableTime(block),
                selectedDate: date, appointments: []
            ) { finishedDates.append($0.date) }
            #expect(session.canDelete)
            session.selectDate(nextDate)
            session.beginAdjustment(session.preview, edge: .move, items: [])
            session.updateAdjustment(translation: 15, items: [])
            await session.delete()
            #expect(!session.adjustment.isDragging)
            #expect(finishedDates == [nextDate])
            let isEmpty = try await database.read { try UnavailableTimeRecord.fetchAll($0).isEmpty }
            #expect(isEmpty)
        }
    }

    @Test func bookingUsesTheRouterIDAndPrefillsBeforePresentation() throws {
        let date = try Date("2026-10-02T00:00:00+05:30", strategy: .iso8601)
        let busyStart = try Date("2026-10-02T09:00:00+05:30", strategy: .iso8601)
        let expectedStart = try Date("2026-10-02T11:00:00+05:30", strategy: .iso8601)
        withDependencies {
            $0.date.now = date
        } operation: {
            let patient = Patient(name: "Patient", createdDate: date)
            let request = ScheduleEditorRequest.bookAppointment(patient)
            let appointment = Appointment(
                patientName: "Other patient", start: busyStart, durationMinutes: 120,
                status: .scheduled)
            let session = ScheduleEditorSession(
                request: request, selectedDate: date,
                appointments: [appointment], onFinished: { _ in })
            guard case .appointment(let model) = session.editor else {
                Issue.record("The session must contain an appointment editor.")
                return
            }
            #expect(session.id == request.id)
            #expect(model.draft.selectedPatient == patient)
            #expect(session.preview.start == expectedStart)
            #expect(session.visibleItems([], for: date).map(\.id) == [session.preview.id])
        }
    }

    @Test(arguments: [false, true])
    func editingReplacesOnlyTheMatchingItemType(unavailable: Bool) throws {
        let start = try Date("2026-10-02T11:00:00+05:30", strategy: .iso8601)
        let nextDate = try Date("2026-10-03T00:00:00+05:30", strategy: .iso8601)
        withDependencies {
            $0.date.now = start
        } operation: {
            let id = UUID()
            let appointment = Appointment(
                id: id, patientName: "Patient", start: start, durationMinutes: 60,
                status: .scheduled)
            let block = UnavailableTime(id: id, label: "Travel", start: start, durationMinutes: 60)
            let request: ScheduleEditorRequest =
                unavailable
                ? .editUnavailableTime(block)
                : .editAppointment(
                    AppointmentDetails(
                        appointment: appointment,
                        patient: Patient(name: "Patient", createdDate: start)))
            let session = ScheduleEditorSession(
                request: request, selectedDate: start, appointments: [appointment],
                onFinished: { _ in })
            let items: [TimelineItem] = [.appointment(appointment), .unavailableTime(block)]
            let siblingID: TimelineItem.ID = unavailable ? .appointment(id) : .unavailableTime(id)
            #expect(session.preview.start == start)
            #expect(
                session.visibleItems(items, for: start).map(\.id) == [
                    siblingID, session.preview.id,
                ])

            session.selectDate(nextDate)
            // Each editor hides the stored version while its draft is on another date.
            let oldPageIDs = session.visibleItems(items, for: start).map(\.id)
            #expect(oldPageIDs == [siblingID])
            #expect(session.visibleItems([], for: nextDate).map(\.id) == [session.preview.id])
        }
    }

    @Test(arguments: [false, true])
    func scrollRequestsIncludeDateAndTypeChanges(unavailable: Bool) throws {
        let date = try Date("2026-10-02T00:00:00+05:30", strategy: .iso8601)
        let nextDate = try Date("2026-10-03T00:00:00+05:30", strategy: .iso8601)
        try withDependencies {
            $0.date.now = date
        } operation: {
            let router = Router(selectedScheduleDate: date)
            router.requestScheduleCreation()
            let request = try #require(router.scheduleEditorRequest)
            let session = ScheduleEditorSession(
                request: request, selectedDate: date,
                appointments: [], onFinished: { _ in })
            if unavailable { session.selectType(.unavailableTime) }
            let initial = session.scrollRequest
            session.selectDate(nextDate)
            let moved = session.scrollRequest
            #expect(moved != initial)
            #expect(moved.sessionID == initial.sessionID)
            #expect(moved.date == nextDate)
            session.selectType(unavailable ? .appointment : .unavailableTime)
            #expect(session.scrollRequest != moved)
            #expect(session.scrollRequest.date == moved.date)
            #expect(session.scrollRequest.revision == moved.revision + 1)
        }
    }

    @Test(arguments: [false, true], [false, true])
    func completionRejectsAnOldSessionAndKeepsTheNewestReplacement(
        unavailable: Bool, editing: Bool
    ) throws {
        let start = try Date("2026-10-02T11:00:00+05:30", strategy: .iso8601)
        let savedDate = try Date("2026-10-03T11:00:00+05:30", strategy: .iso8601)
        try withDependencies {
            $0.date.now = start
        } operation: {
            let router = Router(selectedScheduleDate: start)
            if unavailable {
                if editing {
                    router.requestUnavailableTimeEdit(
                        UnavailableTime(start: start, durationMinutes: 60))
                } else {
                    router.requestScheduleCreation()
                }
            } else if editing {
                router.requestAppointmentEdit(
                    AppointmentDetails(
                        appointment: Appointment(
                            patientName: "Patient", start: start,
                            durationMinutes: 60, status: .scheduled),
                        patient: Patient(name: "Patient", createdDate: start)))
            } else {
                router.requestScheduleCreation()
            }
            let request = try #require(router.scheduleEditorRequest)
            let session = ScheduleEditorSession(
                request: request, selectedDate: start,
                appointments: [], onFinished: { _ in })
            if unavailable && !editing { session.selectType(.unavailableTime) }
            router.presentationDidAppear(session.id)
            let completion: ScheduleEditorSession.Completion =
                unavailable
                ? .unavailableTimeChanged(date: savedDate)
                : .appointmentSaved(
                    AppointmentBookingModel.SavedAppointment(
                        id: UUID(), start: savedDate, kind: .booked))
            #expect(session.finish(using: router, completion: completion))
            #expect(router.selectedScheduleDate == ClinicDate.day(savedDate))
            #expect(router.activePresentation == nil)
            router.requestScheduleCreation()
            router.requestScheduleCreation()
            #expect(!session.finish(using: router, completion: .discarded(date: start)))
            router.presentationDidDismiss(session.id)
            let replacementID = try #require(router.activePresentation?.id)
            #expect(!session.finish(using: router, completion: .discarded(date: start)))
            #expect(router.activePresentation?.id == replacementID)
            #expect(router.selectedScheduleDate == ClinicDate.day(savedDate))
        }
    }

    @Test(arguments: [false, true])
    func genericCreationSwitchesKeepIntervalAndClearFields(hold: Bool) throws {
        let date = try Date("2026-10-02T00:00:00+05:30", strategy: .iso8601)
        let nextDate = try Date("2026-10-03T00:00:00+05:30", strategy: .iso8601)
        try withDependencies {
            $0.date.now = date
        } operation: {
            let router = Router(selectedScheduleDate: date)
            router.requestScheduleCreation()
            let request = try #require(router.scheduleEditorRequest)
            let session = genericSession(request: request, date: date, hold: hold)
            #expect(session.allowsTypeSelection)
            #expect(session.itemType == .appointment)
            #expect(session.preview.durationMinutes == 30)
            #expect(session.isShowingSheet == !hold)
            if hold { session.releaseBooking(session.adjustment) }
            guard case .appointment(let appointment) = session.editor else {
                Issue.record("Generic creation must start with Appointment.")
                return
            }
            let patient = Patient(name: "Chosen patient", createdDate: date)
            session.selectPatient(patient)
            appointment.searchText = "Retained search"
            session.isShowingSheet = true
            session.isShowingSheet = false
            session.isShowingSheet = true
            #expect(appointment.draft.selectedPatient == patient)
            #expect(appointment.searchText == "Retained search")
            session.beginAdjustment(session.preview, edge: .move, items: [])
            session.updateAdjustment(translation: 25, items: [])
            session.adjustment.release()
            session.beginAdjustment(session.preview, edge: .duration, items: [])
            session.updateAdjustment(translation: 20, items: [])
            session.adjustment.release()
            session.selectDate(nextDate)
            let interval = session.preview
            session.errorMessage = "Previous error"
            session.selectType(.unavailableTime)
            #expect(session.id == request.id)
            #expect(router.activePresentation?.id == request.id)
            #expect(session.isShowingSheet)
            #expect(session.errorMessage == nil)
            #expect(!session.adjustment.isDragging)
            #expect(session.preview.start == interval.start)
            #expect(session.preview.durationMinutes == interval.durationMinutes)
            #expect(session.selectedDate == nextDate)
            #expect(session.visibleItems([], for: nextDate).count == 1)
            #expect(session.visibleItems([], for: date).isEmpty)
            guard case .unavailableTime(let block) = session.editor else {
                Issue.record("The active draft must be unavailable time.")
                return
            }
            // Reopening the label step must keep the dragged interval and remain unsaved.
            block.draft.label = "Travel"
            session.isShowingSheet = false
            session.isShowingSheet = true
            session.selectType(.unavailableTime)
            #expect(block.draft.label == "Travel")
            #expect(session.preview.start == interval.start)
            #expect(session.preview.durationMinutes == interval.durationMinutes)
            session.selectType(.appointment)
            guard case .appointment(let returned) = session.editor else {
                Issue.record("The active draft must be an appointment.")
                return
            }
            #expect(returned.draft.selectedPatient == nil)
            #expect(returned.searchText.isEmpty)
            #expect(session.preview.start == interval.start)
            #expect(session.preview.durationMinutes == interval.durationMinutes)
            session.selectType(.unavailableTime)
            guard case .unavailableTime(let returnedBlock) = session.editor else {
                Issue.record("Expected an unavailable-time editor")
                return
            }
            #expect(returnedBlock.draft.label.isEmpty)
            #expect(session.visibleItems([], for: nextDate).count == 1)
            let fresh = genericSession(
                request: .create(), date: date, hold: hold)
            #expect(fresh.itemType == .appointment)
            #expect(fresh.preview.durationMinutes == 30)
        }
    }

    @Test(arguments: [false, true], [false, true])
    func switchingSavesOnlyActiveTypeAndKeepsPatientRecord(hold: Bool, unavailable: Bool)
        async throws
    {
        let database = try testDatabase()
        let date = try Date("2026-10-02T00:00:00+05:30", strategy: .iso8601)
        let patient = Patient(name: "Patient", createdDate: date)
        try await database.write { db in
            try PatientRecord.insert { PatientRecord(patient, now: date) }.execute(db)
        }
        try await withDependencies {
            $0.defaultDatabase = database
            $0.date.now = date
        } operation: {
            let session = genericSession(
                request: .create(), date: date, hold: hold)
            if hold { session.releaseBooking(session.adjustment) }
            session.selectPatient(patient)
            let interval = session.preview
            session.selectType(.unavailableTime)
            if !unavailable {
                session.selectType(.appointment)
                session.isShowingSheet = false
                await session.save()
                #expect(session.isShowingSheet)
                #expect(!session.didFinish)
                session.selectPatient(patient)
            }
            let before = try await database.read { db in
                (
                    try AppointmentRecord.count().fetchOne(db),
                    try UnavailableTimeRecord.count().fetchOne(db)
                )
            }
            #expect(before.0 == 0)
            #expect(before.1 == 0)
            await session.save()
            await session.save()
            let records = try await database.read { db in
                (
                    try AppointmentRecord.fetchAll(db), try UnavailableTimeRecord.fetchAll(db),
                    try PatientRecord.count().fetchOne(db)
                )
            }
            #expect(records.0.count == (unavailable ? 0 : 1))
            #expect(records.1.count == (unavailable ? 1 : 0))
            #expect(records.2 == 1)
            #expect(
                (unavailable ? records.1.first?.start : records.0.first?.start) == interval.start)
            #expect(
                (unavailable ? records.1.first?.durationMinutes : records.0.first?.durationMinutes)
                    == 30)
            if unavailable { #expect(records.1.first?.label == nil) }
        }
    }

    @Test func typeChangeIsBlockedForSavedItemsAndPatientBooking() throws {
        let date = try Date("2026-10-02T12:00:00+05:30", strategy: .iso8601)
        withDependencies {
            $0.date.now = date
        } operation: {
            for unavailable in [false, true] {
                let session = editingSession(unavailable: unavailable, start: date)
                let preview = session.preview
                #expect(!session.allowsTypeSelection)
                #expect(!session.isShowingSheet)
                session.selectType(unavailable ? .appointment : .unavailableTime)
                #expect(session.preview.id == preview.id)
            }
            let patient = Patient(name: "Patient", createdDate: date)
            let booking = ScheduleEditorSession(
                request: .bookAppointment(patient),
                selectedDate: date, appointments: [], onFinished: { _ in })
            #expect(!booking.allowsTypeSelection)
            #expect(!booking.isShowingSheet)
            booking.selectType(.unavailableTime)
            #expect(booking.itemType == .appointment)
            let generic = genericSession(
                request: .create(), date: date, hold: false)
            let preview = generic.preview
            generic.beginAdjustment(preview, edge: .move, items: [])
            generic.selectType(.unavailableTime)
            #expect(!generic.adjustment.isDragging)
            #expect(generic.itemType == .unavailableTime)
        }
    }

    private func genericSession(request: ScheduleEditorRequest, date: Date, hold: Bool)
        -> ScheduleEditorSession
    {
        if hold {
            return ScheduleEditorSession(
                bookingID: request.id, selectedDate: date, center: TimeOfDay(12, 0), items: [],
                onFinished: { _ in })
        }
        return ScheduleEditorSession(
            request: request, selectedDate: date, appointments: [], onFinished: { _ in })
    }
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
        let date = try Date("2026-10-26T00:00:00+05:30", strategy: .iso8601)
        withDependencies {
            $0.date.now = date
        } operation: {
            let session = ScheduleEditorSession(
                bookingID: UUID(), selectedDate: date, center: center, items: [],
                onFinished: { _ in })
            guard case .appointment(let model) = session.editor else {
                Issue.record("Expected an appointment editor")
                return
            }
            #expect(
                model.draftAppointment.start
                    == expectedStart.on(date: date, using: ClinicDate.calendar))
            #expect(model.draftAppointment.start.timeOfDay.totalMinutes % 15 == 0)
            #expect(model.draftAppointment.durationMinutes == 30)
            #expect(session.adjustment.isDragging)
            #expect(!session.isShowingSheet)
            session.updateAdjustment(translation: 0, items: [])
            #expect(
                model.draftAppointment.start
                    == expectedStart.on(date: date, using: ClinicDate.calendar))
        }
    }

    @Test func timelineBookingKeepsDraggedTimeThroughPatientSelectionAndSavesOnlyWithDone()
        async throws
    {
        let database = try testDatabase()
        let date = try Date("2026-10-26T00:00:00+05:30", strategy: .iso8601)
        let patient = Patient(name: "Patient", createdDate: date)
        try await database.write { db in
            try PatientRecord.insert { PatientRecord(patient, now: date) }.execute(db)
        }
        try await withDependencies {
            $0.date.now = date
            $0.defaultDatabase = database
        } operation: {
            var savedDate: Date?
            let session = ScheduleEditorSession(
                bookingID: UUID(), selectedDate: date, center: TimeOfDay(12, 22), items: []
            ) { savedDate = $0.date }
            guard case .appointment(let model) = session.editor else {
                Issue.record("Expected an appointment editor")
                return
            }
            let conflict = Appointment(
                patientName: "Other patient", start: date.addingTimeInterval(12 * 3600),
                durationMinutes: 60, status: .scheduled)
            session.updateAdjustment(translation: 7, items: [.appointment(conflict)])
            let id = model.draftAppointment.id
            let start = date.addingTimeInterval(12 * 3600 + 5 * 60)
            #expect(model.draftAppointment.start == start)
            #expect(model.draft.start == start)
            #expect(!session.isShowingSheet)
            session.releaseBooking(session.adjustment)
            #expect(session.isShowingSheet)
            #expect(!session.adjustment.isDragging)
            session.selectPatient(patient)
            #expect(!session.isShowingSheet)
            #expect(model.draftAppointment.id == id)
            #expect(model.draftAppointment.start == start)
            #expect(model.draftAppointment.patientName == patient.displayName)
            #expect(savedDate == nil)
            #expect(try await database.read { try AppointmentRecord.fetchAll($0).isEmpty })
            await session.save()
            let records = try await database.read { try AppointmentRecord.fetchAll($0) }
            #expect(records.count == 1)
            #expect(records.first?.id == id)
            #expect(records.first?.start == start)
            #expect(records.first?.durationMinutes == 30)
            #expect(savedDate == start)
        }
    }

    @Test(arguments: [false, true], [false, true])
    func timelineChangesStayUnsavedUntilDone(unavailable: Bool, editing: Bool) async throws {
        let database = try testDatabase()
        let date = try Date("2026-10-25T12:00:00+05:30", strategy: .iso8601)
        let nextDate = try Date("2026-10-26T12:00:00+05:30", strategy: .iso8601)
        let patient = Patient(name: "Patient", createdDate: date)
        let appointment = Appointment(
            patientName: patient.displayName, start: date, durationMinutes: 30, status: .scheduled)
        let block = UnavailableTime(label: "Travel", start: date, durationMinutes: 30)
        try await database.write { db in
            try PatientRecord.insert { PatientRecord(patient, now: date) }.execute(db)
            if editing {
                if unavailable {
                    try UnavailableTimeRecord.insert {
                        UnavailableTimeRecord(
                            id: block.id, label: block.label, start: date, durationMinutes: 30,
                            createdAt: date, updatedAt: date)
                    }.execute(db)
                } else {
                    let record = try AppointmentRecord.persisted(
                        id: appointment.id, patientID: patient.id, start: date, durationMinutes: 30,
                        status: .scheduled, createdAt: date, updatedAt: date)
                    try AppointmentRecord.insert { record }.execute(db)
                }
            }
        }
        try await withDependencies {
            $0.date.now = date
            $0.defaultDatabase = database
        } operation: {
            var savedDate: Date?
            let request: ScheduleEditorRequest
            if editing {
                request =
                    unavailable
                    ? .editUnavailableTime(block)
                    : .editAppointment(
                        AppointmentDetails(appointment: appointment, patient: patient))
            } else {
                request = .create()
            }
            let session = ScheduleEditorSession(
                request: request, selectedDate: date, appointments: []
            ) {
                savedDate = $0.date
            }
            if !editing {
                session.selectPatient(patient)
                if unavailable { session.selectType(.unavailableTime) }
            }
            session.isShowingSheet = false
            session.beginAdjustment(session.preview, edge: .move, items: [])
            session.updateAdjustment(translation: 15, items: [])
            let movedStart = session.preview.start
            session.adjustment.release()
            session.beginAdjustment(session.preview, edge: .duration, items: [])
            session.updateAdjustment(translation: -100, items: [])
            session.adjustment.release()
            session.selectDate(nextDate)
            let expectedStart = TimeOfDay(date: movedStart, calendar: ClinicDate.calendar).on(
                date: nextDate, using: ClinicDate.calendar)
            #expect(session.preview.start == expectedStart)
            #expect(session.preview.durationMinutes == 15)
            #expect(savedDate == nil)
            let before = try await database.read { db in
                if unavailable { return try UnavailableTimeRecord.fetchAll(db).map(\.start) }
                return try AppointmentRecord.fetchAll(db).map(\.start)
            }
            #expect(before == (editing ? [date] : []))
            await session.save()
            #expect(session.errorMessage == nil)
            let after = try await database.read { db in
                if unavailable {
                    return try UnavailableTimeRecord.fetchAll(db).map {
                        ($0.start, $0.durationMinutes, $0.createdAt)
                    }
                }
                return try AppointmentRecord.fetchAll(db).map {
                    ($0.start, $0.durationMinutes, $0.createdAt)
                }
            }
            #expect(after.count == 1)
            #expect(after.first?.0 == expectedStart)
            #expect(after.first?.1 == 15)
            #expect(after.first?.2 == date)
            #expect(savedDate == expectedStart)
        }
    }

    @Test func dateChangeDuringBookingInitializationUsesNewDateAndSavesIt() async throws {
        let database = try testDatabase()
        let today = try Date("2026-10-02T00:00:00+05:30", strategy: .iso8601)
        let day1 = try Date("2026-10-03T00:00:00+05:30", strategy: .iso8601)
        let day2 = try Date("2026-10-05T00:00:00+05:30", strategy: .iso8601)
        let day3 = try Date("2026-10-06T00:00:00+05:30", strategy: .iso8601)
        let patient = Patient(name: "Follow-up Patient", createdDate: today)
        try await database.write { db in
            try PatientRecord.insert { PatientRecord(patient, now: today) }.execute(db)
        }

        try await withDependencies {
            $0.date.now = today
            $0.defaultDatabase = database
        } operation: {
            let router = Router(selectedScheduleDate: today)
            let store = ScheduleEditorStore()
            router.requestAppointmentBooking(for: patient, on: day1)
            let request = try #require(router.scheduleEditorRequest)

            var resumeFirstRead: CheckedContinuation<[Appointment], Never>?
            var firstReadStarted: CheckedContinuation<Void, Never>?
            let firstTask = Task {
                await store.prepare(
                    request: request,
                    router: router,
                    appointmentsForBooking: { _ in
                        firstReadStarted?.resume()
                        firstReadStarted = nil
                        return await withCheckedContinuation { continuation in
                            resumeFirstRead = continuation
                        }
                    },
                    onFinished: { id, completion in
                        router.finishScheduleEditor(id, date: completion.date)
                    }
                )
            }
            await withCheckedContinuation { continuation in
                if resumeFirstRead != nil {
                    continuation.resume()
                } else {
                    firstReadStarted = continuation
                }
            }

            // Change the selected date while the first day's appointment read is still in flight.
            router.selectScheduleDate(day2)
            resumeFirstRead?.resume(returning: [])
            await firstTask.value
            #expect(store.session == nil)

            let day2Busy = Appointment(
                patientName: "Other patient",
                start: day2.setTime(10, 0, using: ClinicDate.calendar),
                durationMinutes: 30,
                status: .scheduled
            )
            await store.prepare(
                request: request,
                router: router,
                appointmentsForBooking: { date in
                    #expect(date == day2)
                    return [day2Busy]
                },
                onFinished: { id, completion in
                    router.finishScheduleEditor(id, date: completion.date)
                }
            )

            let session = try #require(store.session)
            let expectedStart = day2.setTime(10, 30, using: ClinicDate.calendar)
            #expect(session.selectedDate == day2)
            #expect(session.preview.start == expectedStart)

            // Date changes after the session exists must not recreate it or reset its chosen time.
            router.selectScheduleDate(day3)
            await store.prepare(
                request: request,
                router: router,
                appointmentsForBooking: { _ in
                    Issue.record("Should not reload booking appointments for an existing session.")
                    return []
                },
                onFinished: { id, completion in
                    router.finishScheduleEditor(id, date: completion.date)
                }
            )
            #expect(store.session === session)
            #expect(session.preview.start == expectedStart)

            #expect(await session.save())
            let savedStarts = try await database.read { db in
                try AppointmentRecord.fetchAll(db).map(\.start)
            }
            #expect(savedStarts == [expectedStart])
            #expect(router.selectedScheduleDate == day2)
        }
    }

    @Test func bookingAppointmentShowsToastWithMessageActionAndAutoDismisses() async throws {
        let database = try testDatabase()
        let date = try Date("2026-10-25T10:00:00+05:30", strategy: .iso8601)
        let savedDay = try Date("2026-10-27T00:00:00+05:30", strategy: .iso8601)
        let patient = Patient(name: "Patient", createdDate: date)
        try await database.write { db in
            try PatientRecord.insert { PatientRecord(patient, now: date) }.execute(db)
        }
        let clock = TestClock()
        try await withDependencies {
            $0.continuousClock = clock
            $0.date.now = date
            $0.defaultDatabase = database
        } operation: {
            let router = Router(selectedScheduleDate: date)
            router.requestScheduleCreation()
            let request = try #require(router.scheduleEditorRequest)
            let session = finishingSession(
                request: request, selectedDate: date, router: router)
            session.selectPatient(patient)
            session.selectDate(savedDay)
            let expectedID =
                switch session.preview {
                case .appointment(let appointment): appointment.id
                case .unavailableTime: UUID()
                }

            #expect(await session.save())
            let activeToast = try #require(router.toast.current)
            #expect(activeToast.message == "Appointment booked")
            #expect(activeToast.action?.title == "Message")
            #expect(activeToast.action?.systemImage == "arrow.up.message")
            #expect(activeToast.duration == ScheduleEditorSession.savedAppointmentToastDuration)

            router.selectedTab = .patients
            router.selectScheduleDate(date)
            router.toast.triggerAction(for: activeToast.id)
            #expect(router.toast.current == nil)
            #expect(router.selectedTab == .schedule)
            #expect(router.selectedScheduleDate == savedDay)
            #expect(router.appointmentMessageRequest?.appointmentID == expectedID)

            // Verify auto-dismiss after the configured duration on a fresh booking.
            router.dismissPresentation()
            router.requestScheduleCreation()
            let secondRequest = try #require(router.scheduleEditorRequest)
            let secondSession = finishingSession(
                request: secondRequest, selectedDate: date, router: router)
            secondSession.selectPatient(patient)
            #expect(await secondSession.save())
            #expect(router.toast.current?.message == "Appointment booked")

            await clock.advance(by: .seconds(4))
            #expect(router.toast.current != nil)
            await clock.advance(by: .seconds(1))
            #expect(router.toast.current == nil)
        }
    }

    @Test func reschedulingAppointmentShowsToastWithMessageActionOnUpdatedDate() async throws {
        let database = try testDatabase()
        let date = try Date("2026-10-25T10:00:00+05:30", strategy: .iso8601)
        let movedDay = try Date("2026-10-28T00:00:00+05:30", strategy: .iso8601)
        let patient = Patient(name: "Patient", createdDate: date)
        let appointment = Appointment(
            patientName: patient.displayName, start: date, durationMinutes: 30, status: .scheduled)
        try await database.write { db in
            try PatientRecord.insert { PatientRecord(patient, now: date) }.execute(db)
            let record = try AppointmentRecord.persisted(
                id: appointment.id, patientID: patient.id, start: date, durationMinutes: 30,
                status: .scheduled, createdAt: date, updatedAt: date)
            try AppointmentRecord.insert { record }.execute(db)
        }
        try await withDependencies {
            $0.continuousClock = TestClock()
            $0.date.now = date
            $0.defaultDatabase = database
        } operation: {
            let router = Router(selectedScheduleDate: date)
            router.requestAppointmentEdit(
                AppointmentDetails(appointment: appointment, patient: patient))
            let request = try #require(router.scheduleEditorRequest)
            let session = finishingSession(
                request: request, selectedDate: date, appointments: [appointment],
                router: router)
            session.selectDate(movedDay)

            #expect(await session.save())
            let activeToast = try #require(router.toast.current)
            #expect(activeToast.message == "Appointment rescheduled")
            #expect(activeToast.action?.title == "Message")
            #expect(activeToast.action?.systemImage == "arrow.up.message")

            router.selectScheduleDate(date)
            router.toast.triggerAction(for: activeToast.id)
            #expect(router.toast.current == nil)
            #expect(router.selectedTab == .schedule)
            #expect(router.selectedScheduleDate == movedDay)
            #expect(router.appointmentMessageRequest?.appointmentID == appointment.id)
        }
    }

    @Test func patientOnlyEditShowsAppointmentUpdatedToastWithoutAction() async throws {
        let database = try testDatabase()
        let date = try Date("2026-10-25T10:00:00+05:30", strategy: .iso8601)
        let originalPatient = Patient(name: "Original Patient", createdDate: date)
        let replacementPatient = Patient(name: "Replacement Patient", createdDate: date)
        let appointment = Appointment(
            patientName: originalPatient.displayName, start: date, durationMinutes: 30,
            status: .scheduled)
        try await database.write { db in
            try PatientRecord.insert { PatientRecord(originalPatient, now: date) }.execute(db)
            try PatientRecord.insert { PatientRecord(replacementPatient, now: date) }.execute(db)
            let record = try AppointmentRecord.persisted(
                id: appointment.id, patientID: originalPatient.id, start: date, durationMinutes: 30,
                status: .scheduled, createdAt: date, updatedAt: date)
            try AppointmentRecord.insert { record }.execute(db)
        }
        try await withDependencies {
            $0.continuousClock = TestClock()
            $0.date.now = date
            $0.defaultDatabase = database
        } operation: {
            let router = Router(selectedScheduleDate: date)
            router.requestAppointmentEdit(
                AppointmentDetails(appointment: appointment, patient: originalPatient))
            let request = try #require(router.scheduleEditorRequest)
            let session = finishingSession(
                request: request, selectedDate: date, appointments: [appointment],
                router: router)
            session.selectPatient(replacementPatient)

            #expect(await session.save())
            let activeToast = try #require(router.toast.current)
            #expect(activeToast.message == "Appointment updated")
            #expect(activeToast.action == nil)
            #expect(activeToast.duration == ScheduleEditorSession.savedAppointmentToastDuration)
        }
    }

    @Test func durationOnlyEditShowsAppointmentUpdatedToastWithoutAction() async throws {
        let database = try testDatabase()
        let date = try Date("2026-10-25T10:00:00+05:30", strategy: .iso8601)
        let patient = Patient(name: "Patient", createdDate: date)
        let appointment = Appointment(
            patientName: patient.displayName, start: date, durationMinutes: 30,
            status: .scheduled)
        try await database.write { db in
            try PatientRecord.insert { PatientRecord(patient, now: date) }.execute(db)
            let record = try AppointmentRecord.persisted(
                id: appointment.id, patientID: patient.id, start: date, durationMinutes: 30,
                status: .scheduled, createdAt: date, updatedAt: date)
            try AppointmentRecord.insert { record }.execute(db)
        }
        try await withDependencies {
            $0.continuousClock = TestClock()
            $0.date.now = date
            $0.defaultDatabase = database
        } operation: {
            let router = Router(selectedScheduleDate: date)
            router.requestAppointmentEdit(
                AppointmentDetails(appointment: appointment, patient: patient))
            let request = try #require(router.scheduleEditorRequest)
            let session = finishingSession(
                request: request, selectedDate: date, appointments: [appointment],
                router: router)
            guard case .appointment(let model) = session.editor else {
                Issue.record("Expected an appointment editor")
                return
            }
            model.draft.selectDuration(60)

            #expect(await session.save())
            let activeToast = try #require(router.toast.current)
            #expect(activeToast.message == "Appointment updated")
            #expect(activeToast.action == nil)
            #expect(activeToast.duration == ScheduleEditorSession.savedAppointmentToastDuration)
        }
    }

    @Test func unavailableTimeSaveAndDeleteDoNotShowToast() async throws {
        let database = try testDatabase()
        let date = try Date("2026-10-25T11:00:00+05:30", strategy: .iso8601)
        try await withDependencies {
            $0.continuousClock = TestClock()
            $0.date.now = date
            $0.defaultDatabase = database
        } operation: {
            let router = Router(selectedScheduleDate: date)

            // Create unavailable time.
            router.requestScheduleCreation()
            let createRequest = try #require(router.scheduleEditorRequest)
            let createSession = finishingSession(
                request: createRequest, selectedDate: date, router: router)
            createSession.selectType(.unavailableTime)
            #expect(await createSession.save())
            #expect(router.toast.current == nil)

            let savedBlock = try #require(
                try await database.read { try UnavailableTimeRecord.fetchAll($0).first }?
                    .unavailableTime)

            // Edit unavailable time.
            router.requestUnavailableTimeEdit(savedBlock)
            let editRequest = try #require(router.scheduleEditorRequest)
            let editSession = finishingSession(
                request: editRequest, selectedDate: date, router: router)
            #expect(await editSession.save())
            #expect(router.toast.current == nil)

            // Delete unavailable time.
            router.requestUnavailableTimeEdit(savedBlock)
            let deleteRequest = try #require(router.scheduleEditorRequest)
            let deleteSession = finishingSession(
                request: deleteRequest, selectedDate: date, router: router)
            #expect(await deleteSession.delete())
            #expect(router.toast.current == nil)
        }
    }

    @Test func failedSaveDiscardAndSupersededSessionDoNotShowToast() async throws {
        let database = try testDatabase()
        let date = try Date("2026-10-25T11:00:00+05:30", strategy: .iso8601)
        let patient = Patient(name: "Patient", createdDate: date)
        let appointment = Appointment(
            patientName: patient.displayName, start: date, durationMinutes: 30, status: .scheduled)
        try await database.write { db in
            try PatientRecord.insert { PatientRecord(patient, now: date) }.execute(db)
        }
        try await withDependencies {
            $0.continuousClock = TestClock()
            $0.date.now = date
            $0.defaultDatabase = database
        } operation: {
            let router = Router(selectedScheduleDate: date)

            // Failed save (editing a missing appointment).
            router.requestAppointmentEdit(
                AppointmentDetails(appointment: appointment, patient: patient))
            let failedRequest = try #require(router.scheduleEditorRequest)
            let failedSession = finishingSession(
                request: failedRequest, selectedDate: date, router: router)
            #expect(!(await failedSession.save()))
            #expect(failedSession.errorMessage != nil)
            #expect(router.toast.current == nil)

            // Discard edits.
            #expect(
                failedSession.finish(
                    using: router, completion: .discarded(date: date)))
            #expect(router.toast.current == nil)

            // Stale/superseded session finish.
            router.requestScheduleCreation()
            let oldRequest = try #require(router.scheduleEditorRequest)
            let oldSession = finishingSession(
                request: oldRequest, selectedDate: date, router: router)
            oldSession.selectPatient(patient)
            router.requestScheduleCreation()
            let replacementID = try #require(router.activePresentation?.id)
            #expect(replacementID != oldSession.id)
            #expect(await oldSession.save())
            #expect(router.activePresentation?.id == replacementID)
            #expect(router.toast.current == nil)
        }
    }

    @Test func storeBeginHoldCreatesAndManagesCreationAndEditSessions() async throws {
        let date = try Date("2026-10-26T00:00:00+05:30", strategy: .iso8601)
        let otherDate = try Date("2026-10-27T00:00:00+05:30", strategy: .iso8601)
        let patient = Patient(name: "Aarav Mehta", createdDate: date)
        let scheduled = Appointment(
            patientName: patient.displayName,
            start: date.setTime(11, 0, using: ClinicDate.calendar),
            durationMinutes: 30,
            status: .scheduled
        )
        let completed = Appointment(
            patientName: patient.displayName,
            start: date.setTime(12, 0, using: ClinicDate.calendar),
            durationMinutes: 30,
            status: .completed
        )
        let block = UnavailableTime(
            label: "Travel",
            start: date.setTime(15, 0, using: ClinicDate.calendar),
            durationMinutes: 60
        )

        try await withDependencies {
            $0.date.now = date
        } operation: {
            let router = Router(selectedScheduleDate: date)
            let store = ScheduleEditorStore()

            // Wrong day is rejected before changing router or store state.
            #expect(
                store.beginHold(
                    on: nil,
                    center: TimeOfDay(12, 0),
                    date: otherDate,
                    items: [],
                    router: router,
                    detailsForAppointment: { _ in nil },
                    onFinished: { _, _ in }
                ) == nil)
            #expect(!store.hasEditor(for: router))

            // Holding on empty timeline creates a centered creation session synchronously.
            let created = try #require(
                store.beginHold(
                    on: nil,
                    center: TimeOfDay(12, 0),
                    date: date,
                    items: [],
                    router: router,
                    detailsForAppointment: { _ in nil },
                    onFinished: { id, completion in
                        store.finish(id, completion: completion, router: router)
                    }
                ))
            let createdRequest = try #require(router.scheduleEditorRequest)
            #expect(created.id == createdRequest.id)
            #expect(store.activeSession(for: createdRequest) === created)
            #expect(created.adjustment.isDragging)
            #expect(!created.isShowingSheet)

            // Subsequent async prepare keeps the synchronously installed hold session.
            await store.prepare(
                request: createdRequest,
                router: router,
                appointmentsForBooking: { _ in
                    Issue.record("Should not reload booking appointments for an active hold.")
                    return []
                },
                onFinished: { _, _ in }
            )
            #expect(store.session === created)

            // A second hold while an editor is active is rejected.
            #expect(
                store.beginHold(
                    on: .unavailableTime(block),
                    center: TimeOfDay(15, 0),
                    date: date,
                    items: [.unavailableTime(block)],
                    router: router,
                    detailsForAppointment: { _ in nil },
                    onFinished: { _, _ in }
                ) == nil)

            // Date selection stays blocked while dragging and syncs both router and session after release.
            store.selectDate(otherDate, using: router)
            #expect(router.selectedScheduleDate == date)
            #expect(store.selectedDate(using: router) == date)
            created.adjustment.release()
            store.selectDate(otherDate, using: router)
            #expect(router.selectedScheduleDate == otherDate)
            #expect(store.selectedDate(using: router) == otherDate)

            // Finishing with a stale ID does nothing; finishing with the active ID clears both.
            #expect(!store.finish(UUID(), completion: .discarded(date: date), router: router))
            #expect(store.session === created)
            #expect(store.finish(created.id, completion: .discarded(date: date), router: router))
            #expect(store.session == nil)
            #expect(router.scheduleEditorRequest == nil)
            #expect(router.selectedScheduleDate == date)

            // Holding on a completed appointment is rejected.
            #expect(
                store.beginHold(
                    on: .appointment(completed),
                    center: TimeOfDay(12, 0),
                    date: date,
                    items: [.appointment(completed)],
                    router: router,
                    detailsForAppointment: {
                        AppointmentDetails(appointment: $0, patient: patient)
                    },
                    onFinished: { _, _ in }
                ) == nil)

            // Holding on a scheduled appointment starts an edit session and begins adjustment.
            let appointmentSession = try #require(
                store.beginHold(
                    on: .appointment(scheduled),
                    center: TimeOfDay(11, 0),
                    date: date,
                    items: [.appointment(scheduled)],
                    router: router,
                    detailsForAppointment: {
                        AppointmentDetails(appointment: $0, patient: patient)
                    },
                    onFinished: { _, _ in }
                ))
            #expect(appointmentSession.adjustment.isDragging)
            #expect(appointmentSession.preview.id == .appointment(scheduled.id))
            #expect(store.finish(appointmentSession.id, completion: .discarded(date: date), router: router))

            // Holding on unavailable time starts an unavailable-time edit session, and mismatch clears it.
            let blockSession = try #require(
                store.beginHold(
                    on: .unavailableTime(block),
                    center: TimeOfDay(15, 0),
                    date: date,
                    items: [.unavailableTime(block)],
                    router: router,
                    detailsForAppointment: { _ in nil },
                    onFinished: { _, _ in }
                ))
            #expect(blockSession.adjustment.isDragging)
            #expect(blockSession.preview.id == .unavailableTime(block.id))
            store.clearIfMismatching(blockSession.id)
            #expect(store.session === blockSession)
            store.clearIfMismatching(nil)
            #expect(store.session == nil)
        }
    }

    private func finishingSession(
        request: ScheduleEditorRequest,
        selectedDate: Date,
        appointments: [Appointment] = [],
        router: Router
    ) -> ScheduleEditorSession {
        weak var created: ScheduleEditorSession?
        let session = ScheduleEditorSession(
            request: request,
            selectedDate: selectedDate,
            appointments: appointments
        ) { completion in
            created?.finish(using: router, completion: completion)
        }
        created = session
        return session
    }
}
