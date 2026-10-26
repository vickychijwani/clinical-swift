import ClinicalModels
import Dependencies
import Foundation
import Testing

@testable import clinical_swift

@MainActor
struct ScheduleEditorSessionTests {
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

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }
}
