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
                model.finishLabelEntry()
                model.selectStart(selectedStart)
                model.selectDuration(45)
                #expect(model.hasUnsavedChanges)
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
                    purpose: .edit(
                        UnavailableTime(label: "Travel", start: start, durationMinutes: 45))))
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
            let request: AppPresentation =
                unavailable
                ? .unavailableTimeEditor(UnavailableTimeEditorRequest(purpose: .create))
                : .appointmentBooking(AppointmentBookingRequest(patient: patient))
            let session = try #require(
                ScheduleEditorSession(
                    request: request, selectedDate: date, appointments: []
                ) { finishedDates.append($0) })
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
                        UnavailableTimeEditorRequest(purpose: .edit(block))),
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

    @Test(arguments: [false, true])
    func unavailableTimeUsesLabelSheetOnlyForCreation(editing: Bool) throws {
        let start = try Date("2026-10-02T11:00:00Z", strategy: .iso8601)
        try withDependencies {
            $0.calendar = utcCalendar
        } operation: {
            let block = UnavailableTime(label: "Travel", start: start, durationMinutes: 60)
            let session = try #require(
                ScheduleEditorSession(
                    request: .unavailableTimeEditor(
                        UnavailableTimeEditorRequest(
                            purpose: editing ? .edit(block) : .create)),
                    selectedDate: start, appointments: [], onFinished: { _ in }))
            #expect(session.isShowingSheet == !editing)
            #expect(session.preview.durationMinutes == 60)
            if !editing {
                #expect(
                    session.preview.start == Bitehaus.opening.on(date: start, using: utcCalendar))
            }
            session.isShowingSheet = false
            #expect(!session.isShowingSheet)
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
            #expect(session.id != model.id)
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
                ? .unavailableTimeEditor(UnavailableTimeEditorRequest(purpose: .edit(block)))
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
    func scrollRequestsIncludeDateAndRepeatedModelRequests(unavailable: Bool) throws {
        let date = try Date("2026-10-02T00:00:00Z", strategy: .iso8601)
        let nextDate = try Date("2026-10-03T00:00:00Z", strategy: .iso8601)
        try withDependencies {
            $0.calendar = utcCalendar
            $0.date.now = date
        } operation: {
            let router = Router(selectedScheduleDate: date)
            if unavailable {
                router.requestUnavailableTimeCreation()
            } else {
                router.requestAppointmentBooking()
            }
            let request = try #require(router.activePresentation)
            let session = try #require(
                ScheduleEditorSession(
                    request: request, selectedDate: date,
                    appointments: [], onFinished: { _ in }))
            let initial = session.scrollRequest
            session.selectDate(nextDate)
            let moved = session.scrollRequest
            #expect(moved != initial)
            #expect(moved.sessionID == initial.sessionID)
            #expect(moved.date == nextDate)
            switch session.editor {
            case .appointment(let model): model.draftPreviewScrollRequest += 1
            case .unavailableTime(let model): model.selectDuration(model.draft.durationMinutes)
            }
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
                        UnavailableTimeEditorRequest(purpose: .edit(block))),
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
                    router.requestUnavailableTimeCreation()
                }
            } else if editing {
                router.requestAppointmentEdit(
                    AppointmentDetails(
                        appointment: Appointment(
                            patientName: "Patient", start: start,
                            durationMinutes: 60, status: .scheduled),
                        patient: Patient(name: "Patient", createdDate: start)))
            } else {
                router.requestAppointmentBooking()
            }
            let request = try #require(router.activePresentation)
            let session = try #require(
                ScheduleEditorSession(
                    request: request, selectedDate: start,
                    appointments: [], onFinished: { _ in }))
            router.presentationDidAppear(session.id)
            #expect(session.finish(using: router, date: savedDate))
            #expect(router.selectedScheduleDate == savedDate.startOfDay(using: utcCalendar))
            #expect(router.activePresentation == nil)
            router.requestUnavailableTimeCreation()
            router.requestAppointmentBooking()
            #expect(!session.finish(using: router, date: start))
            router.presentationDidDismiss()
            let replacementID = try #require(router.appointmentBookingRequest?.id)
            #expect(!session.finish(using: router, date: start))
            #expect(router.activePresentation?.id == replacementID)
            #expect(router.selectedScheduleDate == savedDate.startOfDay(using: utcCalendar))
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
