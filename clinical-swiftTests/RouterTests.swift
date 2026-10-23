import ClinicalModels
import Dependencies
import Foundation
import Testing

@testable import clinical_swift

@MainActor
struct RouterTests {
    @Test func settingsDoesNotReplaceAnActiveEditor() throws {
        let router = makeRouter()
        router.requestAppointmentBooking()
        let editorID = try #require(router.appointmentBookingRequest?.id)
        router.requestSettings()
        #expect(router.settingsRequest == nil)
        #expect(router.appointmentBookingRequest?.id == editorID)
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
        let calendar = gregorianCalendar
        let selectedDate = try Date("2026-07-18T00:00:00Z", strategy: .iso8601)
        let sameDay = try Date("2026-07-18T15:00:00Z", strategy: .iso8601)
        let nextDay = try Date("2026-07-19T00:00:00Z", strategy: .iso8601)

        withDependencies {
            $0.calendar = calendar
        } operation: {
            let router = makeRouter(selectedScheduleDate: selectedDate)
            router.presentDetails(.appointment(UUID()))
            if let presentationID = router.detailsPresentation?.id {
                router.presentationDidAppear(presentationID)
            }

            router.selectScheduleDate(sameDay)
            #expect(router.detailsPresentation != nil)

            router.selectScheduleDate(nextDay)
            #expect(router.selectedScheduleDate == nextDay)
            #expect(router.detailsPresentation == nil)

            router.presentationDidDismiss()
            #expect(router.activePresentation?.id == nil)
        }
    }

    @Test func appointmentResolutionAlignsTheScheduleWithoutDismissingDetails() throws {
        let calendar = gregorianCalendar
        let initialDate = try Date("2026-07-18T00:00:00Z", strategy: .iso8601)
        let appointmentDate = try Date("2026-07-22T11:00:00Z", strategy: .iso8601)

        try withDependencies {
            $0.calendar = calendar
        } operation: {
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
    }

    @Test func staleAppointmentResolutionCannotChangeTheSchedule() throws {
        let calendar = gregorianCalendar
        let initialDate = try Date("2026-07-18T00:00:00Z", strategy: .iso8601)
        let staleDate = try Date("2026-07-20T11:00:00Z", strategy: .iso8601)
        let currentDate = try Date("2026-07-21T11:00:00Z", strategy: .iso8601)

        try withDependencies {
            $0.calendar = calendar
        } operation: {
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
    }

    @Test func crossNavigationRealignsAppointmentsWhilePreservingHistory() throws {
        let calendar = gregorianCalendar
        let dateX = try Date("2026-07-18T10:00:00Z", strategy: .iso8601)
        let dateY = try Date("2026-07-24T15:00:00Z", strategy: .iso8601)

        try withDependencies {
            $0.calendar = calendar
        } operation: {
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
    }

    @Test func newestPresentationWinsDuringDismissalAndInterruptedStateNeverRestores() throws {
        let router = makeRouter()
        let patient = Patient(name: "Aarav Mehta")
        router.presentDetails(.patient(patient.id))
        router.presentationDidAppear(try #require(router.detailsPresentation?.id))

        router.requestPatientEdit(patient)
        #expect(router.activePresentation?.id == nil)

        router.openAppointment(id: UUID())
        router.requestAppointmentBooking()
        router.presentationDidDismiss()

        #expect(router.appointmentBookingRequest != nil)
        #expect(router.detailsPresentation == nil)
        #expect(router.patientEditRequest == nil)

        router.presentationDidDismiss()
        #expect(router.activePresentation?.id == nil)
        #expect(router.detailsPresentation == nil)
    }

    @Test func outgoingSheetDismissalDoesNotDiscardQueuedReplacement() throws {
        let router = makeRouter()
        let patient = Patient(name: "Aarav Mehta")
        router.presentDetails(.patient(patient.id))
        router.presentationDidAppear(try #require(router.detailsPresentation?.id))

        router.requestPatientEdit(patient)
        router.dismissPresentation()
        router.presentationDidDismiss()

        #expect(router.patientEditRequest?.patientID == patient.id)
    }

    @Test func externalDestinationDiscardsQueuedReplacement() throws {
        let calendar = gregorianCalendar
        let initialDate = try Date("2026-07-18T00:00:00Z", strategy: .iso8601)
        let destinationDay = try #require(ScheduleDay(year: 2026, month: 7, day: 25))

        try withDependencies {
            $0.calendar = calendar
        } operation: {
            let router = Router(selectedScheduleDate: initialDate)
            router.presentDetails(.appointment(UUID()))
            router.presentationDidAppear(try #require(router.detailsPresentation?.id))
            router.requestPatientCreation()

            router.openExternalSchedule(destinationDay)
            router.presentationDidDismiss()

            #expect(router.activePresentation?.id == nil)
            #expect(router.selectedScheduleDate == destinationDay.date(using: calendar))
        }
    }

    @Test func externalAppointmentInterruptsEveryAppRootPresentation() throws {
        let patient = Patient(name: "Aarav Mehta")
        let details = appointmentDetails()

        let bookingRouter = makeRouter()
        bookingRouter.requestAppointmentBooking()
        assertExternalAppointmentInterrupts(bookingRouter)

        let editRouter = makeRouter()
        editRouter.requestAppointmentEdit(details)
        assertExternalAppointmentInterrupts(editRouter)

        let messageRouter = makeRouter()
        messageRouter.requestAppointmentMessage(details)
        assertExternalAppointmentInterrupts(messageRouter)

        let patientRouter = makeRouter()
        patientRouter.requestPatientEdit(patient)
        assertExternalAppointmentInterrupts(patientRouter)

        let creationRouter = makeRouter()
        creationRouter.requestPatientCreation()
        assertExternalAppointmentInterrupts(creationRouter)

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
        router.requestAppointmentBooking()
        let appointmentID = UUID()

        router.openAppointment(id: appointmentID)

        #expect(router.detailsPresentation?.root == .appointment(appointmentID))
        #expect(router.appointmentBookingRequest == nil)
    }

    @Test func externalPatientSearchInterruptsPresentationAndNormalizesPhones() throws {
        let router = makeRouter()
        router.requestAppointmentBooking()
        if let presentationID = router.activePresentation?.id {
            router.presentationDidAppear(presentationID)
        }

        router.openExternalPatientSearch(
            phoneNumbers: ["98201 44532", "+91 98201 44533"]
        )

        #expect(router.selectedTab == .patients)
        #expect(router.activePresentation?.id == nil)
        let request = try #require(router.patientSearchRequest)
        #expect(request.phoneNumbers == ["+919820144532", "+919820144533"])

        router.presentationDidDismiss()
        #expect(router.activePresentation?.id == nil)
    }

    @Test func appointmentAndScheduleURLsUseAuthoritativeRouterEntryPoints() throws {
        let calendar = gregorianCalendar
        let initialDate = try Date("2026-07-18T00:00:00Z", strategy: .iso8601)

        try withDependencies {
            $0.calendar = calendar
        } operation: {
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
    }

    private func assertExternalAppointmentInterrupts(_ router: Router) {
        if let presentationID = router.activePresentation?.id {
            router.presentationDidAppear(presentationID)
        }
        let appointmentID = UUID()
        router.openAppointment(id: appointmentID)

        #expect(router.activePresentation?.id == nil)
        router.presentationDidDismiss()
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
        withDependencies {
            $0.calendar = gregorianCalendar
        } operation: {
            Router(selectedScheduleDate: selectedScheduleDate)
        }
    }

    private var gregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
