import ClinicalModels
import Dependencies
import Foundation
import Synchronization
import Testing
import UIKit

@testable import clinical_swift

@MainActor
struct RouterTests {
    @Test func staleFieldTrayExitCannotClearAReplacement() throws {
        let router = Router()
        router.requestScheduleCreation()
        let oldID = try #require(router.activePresentation?.id)
        router.presentationDidAppear(oldID)
        router.requestPatientCreation()
        router.presentationDidDismiss(oldID)
        let newID = try #require(router.patientEditRequest?.id)
        router.presentationDidAppear(newID)
        router.presentationDidDismiss(oldID)
        #expect(router.activePresentation?.id == newID)
    }

    @Test func staleAppearanceAndDismissalDoNotAffectANewSession() throws {
        let router = makeRouter()
        router.presentDetails(.patient(UUID()))
        let oldID = try #require(router.detailsPresentation?.id)
        router.requestScheduleCreation()
        let newID = try #require(router.scheduleEditorRequest?.id)
        router.presentationDidAppear(newID)
        router.presentationDidAppear(oldID)
        router.presentationDidDismiss(oldID)
        #expect(router.activePresentation?.id == newID)
    }

    @Test func patientSelectionDismissalRetainsEditorAndAllowsImmediateInterruption() throws {
        let router = makeRouter()
        router.requestScheduleCreation()
        let id = try #require(router.activePresentation?.id)
        router.presentationDidAppear(id)
        router.presentationDidDismiss(id)
        #expect(router.activePresentation?.id == id)
        router.requestScheduleCreation()
        let replacementID = try #require(router.scheduleEditorRequest?.id)
        #expect(replacementID != id)
        #expect(router.activePresentation?.id == replacementID)
    }

    @Test func interruptedPatientSelectionDismissalActivatesReplacement() throws {
        let router = makeRouter()
        router.requestScheduleCreation()
        let id = try #require(router.activePresentation?.id)
        router.presentationDidAppear(id)
        router.requestScheduleCreation()
        #expect(router.activePresentation == nil)
        router.presentationDidDismiss(id)
        let replacementID = try #require(router.scheduleEditorRequest?.id)
        #expect(replacementID != id)
        #expect(router.activePresentation?.id == replacementID)
    }

    @Test func settingsDoesNotReplaceAnActiveEditor() throws {
        let router = makeRouter()
        router.requestScheduleCreation()
        let editorID = try #require(router.activePresentation?.id)
        router.requestSettings()
        #expect(router.settingsRequest == nil)
        #expect(router.activePresentation?.id == editorID)
    }

    @Test func settingsOpensWhenIdleAndDoesNotReplaceItselfOrDismissingSheets() throws {
        let router = makeRouter()
        router.requestSettings()
        let settingsID = try #require(router.settingsRequest?.id)

        router.requestSettings()
        #expect(router.settingsRequest?.id == settingsID)

        router.presentationDidAppear(settingsID)
        router.dismissPresentation()
        #expect(router.settingsRequest == nil)

        router.requestSettings()
        #expect(router.settingsRequest == nil)

        router.presentationDidDismiss(settingsID)
        router.requestSettings()
        #expect(router.settingsRequest != nil)
    }

    @Test func windowPostsShakeNotificationOnlyForMotionShake() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let receivedCount = Mutex(0)
        let token = NotificationCenter.default.addObserver(
            forName: .deviceDidShake,
            object: window,
            queue: nil
        ) { _ in
            receivedCount.withLock { $0 += 1 }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        window.motionEnded(.none, with: nil)
        #expect(receivedCount.withLock { $0 } == 0)

        window.motionEnded(.motionShake, with: nil)
        #expect(receivedCount.withLock { $0 } == 1)
    }

    @Test func detailsHistoryPreservesRepeatedRoutes() throws {
        let router = makeRouter()
        let patientID = UUID()
        let appointmentID = UUID()

        router.presentDetails(.patient(patientID))
        let presentationID = try #require(router.detailsPresentation?.id)
        router.pushDetails(.appointment(appointmentID))
        router.pushDetails(.patient(patientID))

        #expect(router.detailsPresentation?.root == .patient(patientID))
        #expect(
            router.detailsPresentation?.path == [
                .appointment(appointmentID),
                .patient(patientID),
            ]
        )

        router.setDetailsPath([.appointment(appointmentID)], presentationID: presentationID)
        #expect(router.detailsPresentation?.currentRoute == .appointment(appointmentID))
    }

    @Test func detailsPathMutationRequiresTheActivePresentationIdentity() throws {
        let router = makeRouter()
        router.presentDetails(.patient(UUID()))
        let activeID = try #require(router.detailsPresentation?.id)

        router.setDetailsPath([.appointment(UUID())], presentationID: UUID())
        #expect(router.detailsPresentation?.path == [])

        let appointmentID = UUID()
        router.setDetailsPath([.appointment(appointmentID)], presentationID: activeID)
        #expect(router.detailsPresentation?.path == [.appointment(appointmentID)])
    }

    @Test func presentingDetailsAgainReusesTheSessionAndReplacesHistory() throws {
        let router = makeRouter()
        router.presentDetails(.appointment(UUID()))
        router.pushDetails(.patient(UUID()))
        let presentationID = try #require(router.detailsPresentation?.id)
        let appointmentID = UUID()

        router.presentDetails(.appointment(appointmentID))

        #expect(router.detailsPresentation?.id == presentationID)
        #expect(router.detailsPresentation?.root == .appointment(appointmentID))
        #expect(router.detailsPresentation?.path == [])
    }

    @Test func changingTheScheduleDateDismissesDetailsButSelectingTheSameDayDoesNot() throws {
        let selectedDate = try Date("2026-07-18T00:00:00+05:30", strategy: .iso8601)
        let sameDay = try Date("2026-07-18T15:00:00+05:30", strategy: .iso8601)
        let nextDay = try Date("2026-07-19T00:00:00+05:30", strategy: .iso8601)

        let router = makeRouter(selectedScheduleDate: selectedDate)
        router.presentDetails(.appointment(UUID()))
        let presentationID = try #require(router.detailsPresentation?.id)
        router.presentationDidAppear(presentationID)

        router.selectScheduleDate(sameDay)
        #expect(router.detailsPresentation != nil)

        router.selectScheduleDate(nextDay)
        #expect(router.selectedScheduleDate == nextDay)
        #expect(router.detailsPresentation == nil)

        router.presentationDidDismiss(presentationID)
        #expect(router.activePresentation?.id == nil)
    }

    @Test func appointmentResolutionAlignsTheScheduleWithoutDismissingDetails() throws {
        let calendar = ClinicDate.calendar
        let initialDate = try Date("2026-07-18T00:00:00+05:30", strategy: .iso8601)
        let appointmentDate = try Date("2026-07-22T11:00:00+05:30", strategy: .iso8601)

        let router = makeRouter(selectedScheduleDate: initialDate)
        router.selectedTab = .patients
        let appointmentID = UUID()
        router.presentDetails(.appointment(appointmentID))
        let presentationID = try #require(router.detailsPresentation?.id)

        #expect(
            !router.scheduleIsAligned(
                with: appointmentDate,
                appointmentID: appointmentID,
                presentationID: presentationID
            )
        )

        router.alignSchedule(
            with: appointmentDate,
            appointmentID: appointmentID,
            presentationID: presentationID
        )

        #expect(router.selectedTab == .schedule)
        #expect(router.selectedScheduleDate == appointmentDate.startOfDay(using: calendar))
        #expect(router.detailsPresentation?.currentRoute == .appointment(appointmentID))
        #expect(
            router.scheduleIsAligned(
                with: appointmentDate,
                appointmentID: appointmentID,
                presentationID: presentationID
            )
        )

        let rescheduledDate = appointmentDate.date(byAddingDays: 2, using: calendar)
        #expect(
            !router.scheduleIsAligned(
                with: rescheduledDate,
                appointmentID: appointmentID,
                presentationID: presentationID
            )
        )
        router.alignSchedule(
            with: rescheduledDate,
            appointmentID: appointmentID,
            presentationID: presentationID
        )
        #expect(router.selectedScheduleDate == rescheduledDate)
    }

    @Test func staleAppointmentResolutionCannotChangeTheSchedule() throws {
        let calendar = ClinicDate.calendar
        let initialDate = try Date("2026-07-18T00:00:00+05:30", strategy: .iso8601)
        let staleDate = try Date("2026-07-20T11:00:00+05:30", strategy: .iso8601)
        let currentDate = try Date("2026-07-21T11:00:00+05:30", strategy: .iso8601)

        let router = makeRouter(selectedScheduleDate: initialDate)
        let staleID = UUID()
        let currentID = UUID()
        router.presentDetails(.appointment(staleID))
        let presentationID = try #require(router.detailsPresentation?.id)
        router.presentDetails(.appointment(currentID))

        router.alignSchedule(
            with: staleDate,
            appointmentID: staleID,
            presentationID: presentationID
        )
        #expect(router.selectedScheduleDate == initialDate)

        router.alignSchedule(
            with: currentDate,
            appointmentID: currentID,
            presentationID: presentationID
        )
        #expect(router.selectedScheduleDate == currentDate.startOfDay(using: calendar))

        router.dismissDetails()
        router.alignSchedule(
            with: staleDate,
            appointmentID: currentID,
            presentationID: presentationID
        )
        #expect(router.selectedScheduleDate == currentDate.startOfDay(using: calendar))
    }

    @Test func crossNavigationRealignsAppointmentsWhilePreservingHistory() throws {
        let calendar = ClinicDate.calendar
        let dateX = try Date("2026-07-18T10:00:00+05:30", strategy: .iso8601)
        let dateY = try Date("2026-07-24T15:00:00+05:30", strategy: .iso8601)

        let router = makeRouter(selectedScheduleDate: dateX)
        let appointmentX = UUID()
        let appointmentY = UUID()
        let patientID = UUID()
        router.presentDetails(.appointment(appointmentX))
        let presentationID = try #require(router.detailsPresentation?.id)
        router.alignSchedule(
            with: dateX,
            appointmentID: appointmentX,
            presentationID: presentationID
        )

        router.pushDetails(.patient(patientID))
        router.pushDetails(.appointment(appointmentY))
        router.alignSchedule(
            with: dateY,
            appointmentID: appointmentY,
            presentationID: presentationID
        )
        #expect(router.selectedScheduleDate == dateY.startOfDay(using: calendar))

        router.setDetailsPath([.patient(patientID)], presentationID: presentationID)
        #expect(router.selectedScheduleDate == dateY.startOfDay(using: calendar))

        router.setDetailsPath([], presentationID: presentationID)
        router.alignSchedule(
            with: dateX,
            appointmentID: appointmentX,
            presentationID: presentationID
        )

        #expect(router.selectedScheduleDate == dateX.startOfDay(using: calendar))
        #expect(router.detailsPresentation?.root == .appointment(appointmentX))
        #expect(router.detailsPresentation?.path == [])
    }

    @Test func newestPresentationWinsDuringDismissalAndInterruptedStateNeverRestores() throws {
        let router = makeRouter()
        let patient = Patient(name: "Aarav Mehta")
        router.presentDetails(.patient(patient.id))
        let presentationID = try #require(router.detailsPresentation?.id)
        router.presentationDidAppear(presentationID)

        router.requestPatientEdit(patient)
        #expect(router.activePresentation?.id == nil)

        router.openAppointment(id: UUID())
        router.requestScheduleCreation()
        router.presentationDidDismiss(presentationID)

        let replacementID = try #require(router.scheduleEditorRequest?.id)
        #expect(router.detailsPresentation == nil)
        #expect(router.patientEditRequest == nil)

        router.presentationDidDismiss(presentationID)
        #expect(router.activePresentation?.id == replacementID)
        #expect(router.detailsPresentation == nil)
    }

    @Test func outgoingSheetDismissalDoesNotDiscardQueuedReplacement() throws {
        let router = makeRouter()
        let patient = Patient(name: "Aarav Mehta")
        router.presentDetails(.patient(patient.id))
        let presentationID = try #require(router.detailsPresentation?.id)
        router.presentationDidAppear(presentationID)

        router.requestPatientEdit(patient)
        router.dismissPresentation()
        router.presentationDidDismiss(presentationID)

        #expect(router.patientEditRequest?.patientID == patient.id)
    }

    @Test func externalDestinationDiscardsQueuedReplacement() throws {
        let calendar = ClinicDate.calendar
        let initialDate = try Date("2026-07-18T00:00:00+05:30", strategy: .iso8601)
        let destinationDay = try #require(ScheduleDay(year: 2026, month: 7, day: 25))

        let router = Router(selectedScheduleDate: initialDate)
        router.presentDetails(.appointment(UUID()))
        let presentationID = try #require(router.detailsPresentation?.id)
        router.presentationDidAppear(presentationID)
        router.requestPatientCreation()

        router.openExternalSchedule(destinationDay)
        router.presentationDidDismiss(presentationID)

        #expect(router.activePresentation?.id == nil)
        #expect(router.selectedScheduleDate == destinationDay.date(using: calendar))
    }

    @Test func externalAppointmentInterruptsEveryAppRootPresentation() throws {
        let patient = Patient(name: "Aarav Mehta")
        let details = appointmentDetails()

        let bookingRouter = makeRouter()
        bookingRouter.requestScheduleCreation()
        try assertExternalAppointmentInterrupts(bookingRouter)

        let patientBookingRouter = makeRouter()
        patientBookingRouter.requestAppointmentBooking(for: patient)
        try assertExternalAppointmentInterrupts(patientBookingRouter)

        let editRouter = makeRouter()
        editRouter.requestAppointmentEdit(details)
        try assertExternalAppointmentInterrupts(editRouter)

        let messageRouter = makeRouter()
        messageRouter.requestAppointmentMessage(details)
        try assertExternalAppointmentInterrupts(messageRouter)

        let patientRouter = makeRouter()
        patientRouter.requestPatientEdit(patient)
        try assertExternalAppointmentInterrupts(patientRouter)

        let creationRouter = makeRouter()
        creationRouter.requestPatientCreation()
        try assertExternalAppointmentInterrupts(creationRouter)

        let detailsRouter = makeRouter()
        detailsRouter.presentDetails(.patient(patient.id))
        let presentationID = try #require(detailsRouter.detailsPresentation?.id)
        let appointmentID = UUID()
        detailsRouter.openAppointment(id: appointmentID)
        #expect(detailsRouter.detailsPresentation?.id == presentationID)
        #expect(detailsRouter.detailsPresentation?.root == .appointment(appointmentID))
    }

    @Test func anUnpresentedActionIsReplacedImmediatelyWithoutWaitingForDismissal() {
        let router = makeRouter()
        router.requestScheduleCreation()
        let appointmentID = UUID()

        router.openAppointment(id: appointmentID)

        #expect(router.detailsPresentation?.root == .appointment(appointmentID))
        #expect(router.scheduleEditorRequest == nil)
    }

    @Test func externalPatientSearchInterruptsPresentationAndNormalizesPhones() throws {
        let router = makeRouter()
        router.requestScheduleCreation()
        let presentationID = try #require(router.activePresentation?.id)
        router.presentationDidAppear(presentationID)

        router.openExternalPatientSearch(
            phoneNumbers: ["98201 44532", "+91 98201 44533"]
        )

        #expect(router.selectedTab == .patients)
        #expect(router.activePresentation?.id == nil)
        let request = try #require(router.patientSearchRequest)
        #expect(request.phoneNumbers == ["+919820144532", "+919820144533"])

        router.presentationDidDismiss(presentationID)
        #expect(router.activePresentation?.id == nil)
    }

    @Test func requestingAppointmentMessageByIDAlignsScheduleAndOpensMessageTray() throws {
        let calendar = ClinicDate.calendar
        let initialDate = try Date("2026-07-18T00:00:00+05:30", strategy: .iso8601)
        let appointmentStart = try Date("2026-07-22T14:30:00+05:30", strategy: .iso8601)
        let appointmentID = UUID()

        let router = makeRouter(selectedScheduleDate: initialDate)
        router.selectedTab = .patients

        router.requestAppointmentMessage(id: appointmentID, date: appointmentStart)

        #expect(router.selectedTab == .schedule)
        #expect(router.selectedScheduleDate == appointmentStart.startOfDay(using: calendar))
        #expect(router.appointmentMessageRequest?.appointmentID == appointmentID)
    }

    @Test func appointmentAndScheduleURLsUseAuthoritativeRouterEntryPoints() throws {
        let calendar = ClinicDate.calendar
        let initialDate = try Date("2026-07-18T00:00:00+05:30", strategy: .iso8601)

        let router = makeRouter(selectedScheduleDate: initialDate)
        let appointmentID = UUID()
        let appointmentURL = try #require(ClinicalURL.appointment(appointmentID).url)

        #expect(router.open(appointmentURL))
        #expect(router.selectedTab == .schedule)
        #expect(router.detailsPresentation?.root == .appointment(appointmentID))
        #expect(router.selectedScheduleDate == initialDate)

        let day = try #require(ScheduleDay(year: 2026, month: 7, day: 25))
        let scheduleURL = try #require(ClinicalURL.schedule(day).url)
        #expect(router.open(scheduleURL))
        #expect(router.detailsPresentation == nil)
        #expect(router.selectedScheduleDate == day.date(using: calendar))
    }

    @Test func scheduleEditorEntryPointsUseUnifiedPresentationAndKeepTelemetryCompatible() throws {
        let initialDate = try Date("2026-07-18T00:00:00+05:30", strategy: .iso8601)
        let bookingDate = try Date("2026-07-20T00:00:00+05:30", strategy: .iso8601)
        let editDate = try Date("2026-07-22T11:00:00+05:30", strategy: .iso8601)
        let blockDate = try Date("2026-07-24T15:00:00+05:30", strategy: .iso8601)
        let patient = Patient(name: "Aarav Mehta", createdDate: initialDate)
        let details = appointmentDetails(start: editDate)
        let block = UnavailableTime(label: "Travel", start: blockDate, durationMinutes: 60)

        let events = Mutex<[TelemetryEntry]>([])
        try withDependencies {
            $0.telemetry = TelemetryClient(
                record: { entry in events.withLock { $0.append(entry) } },
                isVerboseEnabled: { false }
            )
        } operation: {
            let router = makeRouter(selectedScheduleDate: initialDate)
            router.selectedTab = .patients

            router.requestScheduleCreation()
            let creation = try #require(router.scheduleEditorRequest)
            if case .create = creation.kind {
            } else {
                Issue.record("Expected schedule creation kind.")
            }
            #expect(router.selectedTab == .schedule)
            #expect(router.selectedScheduleDate == initialDate)

            router.requestAppointmentBooking(for: patient, on: bookingDate)
            let booking = try #require(router.scheduleEditorRequest)
            if case .bookAppointment(let bookedPatient) = booking.kind {
                #expect(bookedPatient.id == patient.id)
            } else {
                Issue.record("Expected appointment booking kind.")
            }
            #expect(router.selectedScheduleDate == bookingDate)

            router.requestAppointmentEdit(details)
            let edit = try #require(router.scheduleEditorRequest)
            if case .editAppointment(let editedDetails) = edit.kind {
                #expect(editedDetails.id == details.id)
            } else {
                Issue.record("Expected appointment edit kind.")
            }
            #expect(router.selectedScheduleDate == ClinicDate.day(editDate))

            router.requestUnavailableTimeEdit(block)
            let unavailable = try #require(router.scheduleEditorRequest)
            if case .editUnavailableTime(let editedBlock) = unavailable.kind {
                #expect(editedBlock.id == block.id)
            } else {
                Issue.record("Expected unavailable-time edit kind.")
            }
            #expect(router.selectedScheduleDate == ClinicDate.day(blockDate))
        }

        let presentationEvents = events.withLock { entries in
            entries.filter {
                $0.name == "presentation_opened" || $0.name == "presentation_replaced"
            }
        }
        #expect(
            presentationEvents.map(\.route) == [
                "schedule_creation",
                "appointment_booking",
                "appointment_edit",
                "unavailable_time_editor",
            ])
        #expect(
            presentationEvents.map(\.recordID) == [
                nil,
                patient.id.uuidString.lowercased(),
                details.appointment.id.uuidString.lowercased(),
                block.id.uuidString.lowercased(),
            ])
    }

    @Test func unavailableTimeNavigationFailureLogsAndRespectsActiveRequestIdentity() throws {
        struct LookupError: Error {}
        let blockID = UUID()
        let newerBlockID = UUID()
        let entries = Mutex<[TelemetryEntry]>([])

        try withDependencies {
            $0.telemetry = TelemetryClient(
                record: { entry in entries.withLock { $0.append(entry) } },
                isVerboseEnabled: { false }
            )
        } operation: {
            let router = makeRouter()
            router.openUnavailableTime(blockID)
            let firstRequest = try #require(router.unavailableTimeNavigationRequest)
            router.openUnavailableTime(newerBlockID)
            let currentRequest = try #require(router.unavailableTimeNavigationRequest)

            router.failUnavailableTimeNavigation(firstRequest, error: LookupError())
            #expect(router.unavailableTimeNavigationRequest == currentRequest)
            #expect(router.navigationErrorMessage == nil)

            router.failUnavailableTimeNavigation(currentRequest, error: LookupError())
            #expect(router.unavailableTimeNavigationRequest == nil)
            #expect(router.navigationErrorMessage == "The unavailable time could not be loaded.")
        }

        let failureLogs = entries.withLock { recorded in
            recorded.filter { $0.name == "unavailable_time_navigation_failed" }
        }
        #expect(failureLogs.count == 2)
        #expect(
            failureLogs.map(\.recordID) == [
                blockID.uuidString.lowercased(),
                newerBlockID.uuidString.lowercased(),
            ])
    }

    private func assertExternalAppointmentInterrupts(_ router: Router) throws {
        let presentationID = try #require(router.activePresentation?.id)
        router.presentationDidAppear(presentationID)
        let appointmentID = UUID()
        router.openAppointment(id: appointmentID)

        #expect(router.activePresentation?.id == nil)
        router.presentationDidDismiss(presentationID)
        #expect(router.detailsPresentation?.root == .appointment(appointmentID))
    }

    private func appointmentDetails(
        id: Appointment.ID = UUID(),
        start: Date = Date(timeIntervalSince1970: 0)
    ) -> AppointmentDetails {
        let patient = Patient(name: "Aarav Mehta", createdDate: start)
        return AppointmentDetails(
            appointment: Appointment(
                id: id,
                patientName: patient.displayName,
                start: start,
                durationMinutes: 30,
                status: .scheduled
            ),
            patient: patient
        )
    }

    private func makeRouter(selectedScheduleDate: Date = .now) -> Router {
        Router(selectedScheduleDate: selectedScheduleDate)
    }
}
