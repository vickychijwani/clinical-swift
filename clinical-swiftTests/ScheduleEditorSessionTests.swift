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
    func draftIdentityPreventsDraggingAnotherItem(unavailable: Bool) throws {
        let start = try Date("2026-10-02T12:00:00Z", strategy: .iso8601)
        try withDependencies {
            $0.calendar = utcCalendar
        } operation: {
            let session = try editingSession(unavailable: unavailable, start: start)
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
    }

    @Test(arguments: [false, true])
    func dateSelectionPreservesDraftAndMovesItBetweenPages(unavailable: Bool) throws {
        let calendar = Calendar.autoupdatingCurrent
        let start = try Date("2026-10-02T00:00:00Z", strategy: .iso8601)
            .setTime(14, 0, using: calendar)
        let nextStart = start.date(byAddingDays: 1, using: calendar).setTime(14, 0, using: calendar)
        try withDependencies {
            $0.calendar = calendar
        } operation: {
            let session = try editingSession(unavailable: unavailable, start: start)
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
    }

    @Test(arguments: [false, true])
    func dateSelectionKeepsClockTimeAcrossDaylightSavingChange(unavailable: Bool) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let start = try Date("2026-10-31T16:00:00Z", strategy: .iso8601)
        let nextStart = try Date("2026-11-01T17:00:00Z", strategy: .iso8601)
        try withDependencies {
            $0.calendar = calendar
        } operation: {
            let session = try editingSession(unavailable: unavailable, start: start)
            session.selectDate(nextStart)
            #expect(session.preview.start == nextStart)
            #expect(session.preview.durationMinutes == 45)
        }
    }

    @Test(arguments: [false, true])
    func nextGestureUsesDraftControlAndMetadataChanges(unavailable: Bool) throws {
        let start = try Date("2026-10-02T12:00:00Z", strategy: .iso8601)
        let selectedStart = try Date("2026-10-02T16:00:00Z", strategy: .iso8601)
        try withDependencies {
            $0.calendar = utcCalendar
        } operation: {
            let session = try editingSession(unavailable: unavailable, start: start)
            let staleItem = session.preview
            session.beginAdjustment(staleItem, edge: .move, items: [])
            session.updateAdjustment(translation: 15, items: [])
            session.adjustment.release()
            let patient = Patient(name: "Changed patient", createdDate: start)
            let conflict = Appointment(
                patientName: "Other", start: selectedStart, durationMinutes: 60,
                status: .scheduled)
            switch session.editor {
            case .appointment(let model):
                model.selectPatient(patient)
                model.selectStart(selectedStart)
                model.selectDuration(45)
                model.updateAppointments([conflict], for: start)
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
    }

    private func editingSession(unavailable: Bool, start: Date) throws -> ScheduleEditorSession {
        let request: AppPresentation =
            unavailable
            ? .unavailableTimeEditor(
                UnavailableTimeEditorRequest(
                    block: UnavailableTime(label: "Travel", start: start, durationMinutes: 45)))
            : .appointmentEdit(
                AppointmentEditRequest(
                    details: AppointmentDetails(
                        appointment: Appointment(
                            patientName: "Patient", start: start, durationMinutes: 45,
                            status: .scheduled),
                        patient: Patient(name: "Patient", createdDate: start))))
        return try #require(
            ScheduleEditorSession(
                request: request, selectedDate: start, appointments: [], onFinished: { _ in }))
    }

    @Test func initialHoldUsesItsOwnAdjustmentAndDoneRequiresPatientSelection() async throws {
        let date = try Date("2026-10-02T00:00:00Z", strategy: .iso8601)
        await withDependencies {
            $0.calendar = utcCalendar
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
        let database = try makeDatabase()
        let date = try Date("2026-10-02T00:00:00Z", strategy: .iso8601)
        let patient = Patient(name: "Patient", createdDate: date)
        try await database.write { db in
            try PatientRecord.insert { PatientRecord(patient, now: date) }.execute(db)
        }
        try await withDependencies {
            $0.calendar = utcCalendar
            $0.date.now = date
            $0.defaultDatabase = database
        } operation: {
            var finishedDates: [Date] = []
            let request = AppPresentation.scheduleCreation(ScheduleCreationRequest())
            let session = try #require(
                ScheduleEditorSession(
                    request: request, selectedDate: date, appointments: []
                ) { finishedDates.append($0) })
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
        let database = try makeDatabase()
        let date = try Date("2026-10-02T11:00:00Z", strategy: .iso8601)
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
            $0.calendar = utcCalendar
            $0.date.now = date
            $0.defaultDatabase = database
        } operation: {
            var didFinish = false
            let session = try #require(
                ScheduleEditorSession(
                    request: .appointmentEdit(
                        AppointmentEditRequest(
                            details: AppointmentDetails(appointment: appointment, patient: patient))
                    ),
                    selectedDate: date, appointments: [appointment]
                ) { _ in didFinish = true })
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
        let database = try makeDatabase()
        let date = try Date("2026-10-02T11:00:00Z", strategy: .iso8601)
        let nextDate = try Date("2026-10-03T00:00:00Z", strategy: .iso8601)
        let block = UnavailableTime(label: "Travel", start: date, durationMinutes: 60)
        try await database.write { db in
            try UnavailableTimeRecord.insert {
                UnavailableTimeRecord(
                    id: block.id, label: block.label, start: block.start,
                    durationMinutes: block.durationMinutes, createdAt: date, updatedAt: date)
            }.execute(db)
        }
        try await withDependencies {
            $0.calendar = utcCalendar
            $0.date.now = date
            $0.defaultDatabase = database
        } operation: {
            var finishedDates: [Date] = []
            let session = try #require(
                ScheduleEditorSession(
                    request: .unavailableTimeEditor(
                        UnavailableTimeEditorRequest(block: block)),
                    selectedDate: date, appointments: []
                ) { finishedDates.append($0) })
            #expect(session.canDelete)
            session.selectDate(nextDate)
            session.beginAdjustment(session.preview, edge: .move, items: [])
            session.updateAdjustment(translation: 15, items: [])
            await session.delete()
            #expect(!session.adjustment.isDragging)
            #expect(finishedDates == [nextDate])
            #expect(try await database.read { try UnavailableTimeRecord.fetchAll($0).isEmpty })
        }
    }

    @Test func bookingUsesTheRouterIDAndPrefillsBeforePresentation() throws {
        let date = try Date("2026-10-02T00:00:00Z", strategy: .iso8601)
        let busyStart = try Date("2026-10-02T09:00:00Z", strategy: .iso8601)
        let expectedStart = try Date("2026-10-02T11:00:00Z", strategy: .iso8601)
        try withDependencies {
            $0.calendar = utcCalendar
            $0.date.now = date
        } operation: {
            let patient = Patient(name: "Patient", createdDate: date)
            let request = AppointmentBookingRequest(patient: patient)
            let appointment = Appointment(
                patientName: "Other patient", start: busyStart, durationMinutes: 120,
                status: .scheduled)
            let session = try #require(
                ScheduleEditorSession(
                    request: .appointmentBooking(request), selectedDate: date,
                    appointments: [appointment], onFinished: { _ in }))
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
        let start = try Date("2026-10-02T11:00:00Z", strategy: .iso8601)
        let nextDate = try Date("2026-10-03T00:00:00Z", strategy: .iso8601)
        try withDependencies {
            $0.calendar = utcCalendar
            $0.date.now = start
        } operation: {
            let id = UUID()
            let appointment = Appointment(
                id: id, patientName: "Patient", start: start, durationMinutes: 60,
                status: .scheduled)
            let block = UnavailableTime(id: id, label: "Travel", start: start, durationMinutes: 60)
            let request: AppPresentation =
                unavailable
                ? .unavailableTimeEditor(UnavailableTimeEditorRequest(block: block))
                : .appointmentEdit(
                    AppointmentEditRequest(
                        details: AppointmentDetails(
                            appointment: appointment,
                            patient: Patient(name: "Patient", createdDate: start))))
            let session = try #require(
                ScheduleEditorSession(
                    request: request, selectedDate: start, appointments: [appointment],
                    onFinished: { _ in }))
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
        let date = try Date("2026-10-02T00:00:00Z", strategy: .iso8601)
        let nextDate = try Date("2026-10-03T00:00:00Z", strategy: .iso8601)
        try withDependencies {
            $0.calendar = utcCalendar
            $0.date.now = date
        } operation: {
            let router = Router(selectedScheduleDate: date)
            router.requestScheduleCreation()
            let request = try #require(router.activePresentation)
            let session = try #require(
                ScheduleEditorSession(
                    request: request, selectedDate: date,
                    appointments: [], onFinished: { _ in }))
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

    @Test func availabilityUpdatesLeaveUnavailableTimeUnchanged() throws {
        let start = try Date("2026-10-02T10:00:00Z", strategy: .iso8601)
        try withDependencies {
            $0.calendar = utcCalendar
        } operation: {
            let block = UnavailableTime(start: start, durationMinutes: 60)
            let session = try #require(
                ScheduleEditorSession(
                    request: .unavailableTimeEditor(
                        UnavailableTimeEditorRequest(block: block)),
                    selectedDate: start, appointments: [], onFinished: { _ in }))
            let before = session.scrollRequest
            #expect(
                !session.updateAppointments(
                    [
                        Appointment(
                            patientName: "Patient", start: start, durationMinutes: 120,
                            status: .scheduled)
                    ], for: start))
            #expect(session.preview.start == start)
            #expect(session.scrollRequest == before)
        }
    }

    @Test(arguments: [false, true], [false, true])
    func completionRejectsAnOldSessionAndKeepsTheNewestReplacement(
        unavailable: Bool, editing: Bool
    ) throws {
        let start = try Date("2026-10-02T11:00:00Z", strategy: .iso8601)
        let savedDate = try Date("2026-10-03T11:00:00Z", strategy: .iso8601)
        try withDependencies {
            $0.calendar = utcCalendar
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
            let request = try #require(router.activePresentation)
            let session = try #require(
                ScheduleEditorSession(
                    request: request, selectedDate: start,
                    appointments: [], onFinished: { _ in }))
            if unavailable && !editing { session.selectType(.unavailableTime) }
            router.presentationDidAppear(session.id)
            #expect(session.finish(using: router, date: savedDate))
            #expect(router.selectedScheduleDate == savedDate.startOfDay(using: utcCalendar))
            #expect(router.activePresentation == nil)
            router.requestScheduleCreation()
            router.requestScheduleCreation()
            #expect(!session.finish(using: router, date: start))
            router.presentationDidDismiss()
            let replacementID = try #require(router.activePresentation?.id)
            #expect(!session.finish(using: router, date: start))
            #expect(router.activePresentation?.id == replacementID)
            #expect(router.selectedScheduleDate == savedDate.startOfDay(using: utcCalendar))
        }
    }

    @Test(arguments: [false, true])
    func genericCreationSwitchesKeepIntervalAndClearFields(hold: Bool) throws {
        let date = try Date("2026-10-02T00:00:00Z", strategy: .iso8601)
        let nextDate = try Date("2026-10-03T00:00:00Z", strategy: .iso8601)
        try withDependencies {
            $0.calendar = utcCalendar
            $0.date.now = date
        } operation: {
            let router = Router(selectedScheduleDate: date)
            router.requestScheduleCreation()
            let request = try #require(router.activePresentation)
            let session = try genericSession(request: request, date: date, hold: hold)
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
            guard case .unavailableTime(let returnedBlock) = session.editor else { return }
            #expect(returnedBlock.draft.label.isEmpty)
            #expect(session.visibleItems([], for: nextDate).count == 1)
            let fresh = try genericSession(
                request: .scheduleCreation(ScheduleCreationRequest()), date: date, hold: hold)
            #expect(fresh.itemType == .appointment)
            #expect(fresh.preview.durationMinutes == 30)
        }
    }

    @Test(arguments: [false, true], [false, true])
    func switchingSavesOnlyActiveTypeAndKeepsPatientRecord(hold: Bool, unavailable: Bool)
        async throws
    {
        let database = try makeDatabase()
        let date = try Date("2026-10-02T00:00:00Z", strategy: .iso8601)
        let patient = Patient(name: "Patient", createdDate: date)
        try await database.write { db in
            try PatientRecord.insert { PatientRecord(patient, now: date) }.execute(db)
        }
        try await withDependencies {
            $0.defaultDatabase = database
            $0.calendar = utcCalendar
            $0.date.now = date
        } operation: {
            let session = try genericSession(
                request: .scheduleCreation(ScheduleCreationRequest()), date: date, hold: hold)
            if hold { session.releaseBooking(session.adjustment) }
            session.selectPatient(patient)
            let interval = session.preview
            session.selectType(.unavailableTime)
            if !unavailable {
                session.selectType(.appointment)
                session.isShowingSheet = false
                await session.save()
                #expect(session.isShowingSheet)
                #expect(!session.state.didFinish)
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

    @Test func typeChangeIsBlockedForSavedItemsPatientBookingAndActiveSave() throws {
        let date = try Date("2026-10-02T12:00:00Z", strategy: .iso8601)
        try withDependencies {
            $0.calendar = utcCalendar
            $0.date.now = date
        } operation: {
            for unavailable in [false, true] {
                let session = try editingSession(unavailable: unavailable, start: date)
                let preview = session.preview
                #expect(!session.allowsTypeSelection)
                #expect(!session.isShowingSheet)
                session.selectType(unavailable ? .appointment : .unavailableTime)
                #expect(session.preview.id == preview.id)
            }
            let patient = Patient(name: "Patient", createdDate: date)
            let booking = try #require(
                ScheduleEditorSession(
                    request: .appointmentBooking(AppointmentBookingRequest(patient: patient)),
                    selectedDate: date, appointments: [], onFinished: { _ in }))
            #expect(!booking.allowsTypeSelection)
            #expect(!booking.isShowingSheet)
            booking.selectType(.unavailableTime)
            #expect(booking.itemType == .appointment)
            let generic = try genericSession(
                request: .scheduleCreation(ScheduleCreationRequest()), date: date, hold: false)
            let preview = generic.preview
            generic.state.isWorking = true
            generic.selectType(.unavailableTime)
            generic.selectDate(date.addingTimeInterval(24 * 3600))
            #expect(generic.itemType == .appointment)
            #expect(generic.preview.start == preview.start)
            generic.state.isWorking = false
            generic.beginAdjustment(preview, edge: .move, items: [])
            generic.selectType(.unavailableTime)
            #expect(!generic.adjustment.isDragging)
            #expect(generic.itemType == .unavailableTime)
        }
    }

    private func genericSession(request: AppPresentation, date: Date, hold: Bool) throws
        -> ScheduleEditorSession
    {
        if hold {
            return ScheduleEditorSession(
                bookingID: request.id, selectedDate: date, center: TimeOfDay(12, 0), items: [],
                onFinished: { _ in })
        }
        return try #require(
            ScheduleEditorSession(
                request: request, selectedDate: date, appointments: [], onFinished: { _ in }))
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
        let date = try Date("2026-10-26T00:00:00Z", strategy: .iso8601)
        withDependencies {
            $0.calendar = utcCalendar
            $0.date.now = date
        } operation: {
            let session = ScheduleEditorSession(
                bookingID: UUID(), selectedDate: date, center: center, items: [],
                onFinished: { _ in })
            guard case .appointment(let model) = session.editor else { return }
            #expect(
                model.draftAppointment.start
                    == expectedStart.on(date: date, using: utcCalendar))
            #expect(model.draftAppointment.start.timeOfDay.totalMinutes % 15 == 0)
            #expect(model.draftAppointment.durationMinutes == 30)
            #expect(session.adjustment.isDragging)
            #expect(!session.isShowingSheet)
            session.updateAdjustment(translation: 0, items: [])
            #expect(
                model.draftAppointment.start
                    == expectedStart.on(date: date, using: utcCalendar))
        }
    }

    @Test func timelineBookingKeepsDraggedTimeThroughPatientSelectionAndSavesOnlyWithDone()
        async throws
    {
        let database = try makeDatabase()
        let date = try Date("2026-10-26T00:00:00Z", strategy: .iso8601)
        let patient = Patient(name: "Patient", createdDate: date)
        try await database.write { db in
            try PatientRecord.insert { PatientRecord(patient, now: date) }.execute(db)
        }
        try await withDependencies {
            $0.calendar = utcCalendar
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
            #expect(!session.isShowingSheet)
            #expect(!(await model.saveAppointment()))
            session.releaseBooking(session.adjustment)
            #expect(session.isShowingSheet)
            #expect(!session.adjustment.isDragging)
            model.selectPatient(patient)
            model.updateAppointments([conflict], for: date)
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
        let database = try makeDatabase()
        let date = try Date("2026-10-25T12:00:00Z", strategy: .iso8601)
        let nextDate = try Date("2026-10-26T12:00:00Z", strategy: .iso8601)
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
            $0.calendar = utcCalendar
            $0.date.now = date
            $0.defaultDatabase = database
        } operation: {
            var savedDate: Date?
            let request: AppPresentation
            if editing {
                request =
                    unavailable
                    ? .unavailableTimeEditor(UnavailableTimeEditorRequest(block: block))
                    : .appointmentEdit(
                        AppointmentEditRequest(
                            details: AppointmentDetails(appointment: appointment, patient: patient))
                    )
            } else {
                request = .scheduleCreation(ScheduleCreationRequest())
            }
            let session = try #require(
                ScheduleEditorSession(request: request, selectedDate: date, appointments: []) {
                    savedDate = $0
                })
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
            let expectedStart = TimeOfDay(date: movedStart, calendar: utcCalendar).on(
                date: nextDate, using: utcCalendar)
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
    private func makeDatabase() throws -> DatabaseQueue {
        let database = try DatabaseQueue(configuration: clinicalDatabaseConfiguration())
        try migrateDatabase(database)
        return database
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }
}
