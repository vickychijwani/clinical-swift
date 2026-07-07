import Foundation
import Testing

@testable import clinical_swift

struct RouterTests {
    @Test func patientTimelineNavigationPreservesRepeatedRoutes() {
        let router = Router()
        let patientID = UUID()
        let appointmentID = UUID()

        router.presentDetails(.patient(patientID))
        router.pushDetails(.appointment(appointmentID))
        router.pushDetails(.patient(patientID))

        #expect(router.detailsPresentation?.root == .patient(patientID))
        #expect(
            router.detailsPresentation?.path == [
                .appointment(appointmentID),
                .patient(patientID),
            ]
        )
    }

    @Test func detailsHistoryPreservesRepeatedRoutesAndTabState() throws {
        let router = Router()
        let appointmentID = UUID()
        let patientID = UUID()
        let schedulePath: [Route] = [.patient(UUID())]
        let patientsPath: [Route] = [.appointment(UUID())]
        router.selectedTab = .schedule
        router.schedulePath = schedulePath
        router.patientsPath = patientsPath

        router.presentDetails(.appointment(appointmentID))
        let presentationID = try #require(router.detailsPresentation?.id)
        router.pushDetails(.patient(patientID))
        router.pushDetails(.appointment(appointmentID))

        #expect(router.detailsPresentation?.id == presentationID)
        #expect(router.detailsPresentation?.root == .appointment(appointmentID))
        #expect(
            router.detailsPresentation?.path == [
                .patient(patientID),
                .appointment(appointmentID),
            ]
        )
        #expect(router.selectedTab == .schedule)
        #expect(router.schedulePath == schedulePath)
        #expect(router.patientsPath == patientsPath)
    }

    @Test func detailsPushRequiresAnActivePresentation() {
        let router = Router()
        router.pushDetails(.patient(UUID()))
        #expect(router.detailsPresentation == nil)
    }

    @Test func presentingDetailsAgainReusesTheSessionAndReplacesHistory() throws {
        let router = Router()
        router.presentDetails(.appointment(UUID()))
        router.pushDetails(.patient(UUID()))
        let presentationID = try #require(router.detailsPresentation?.id)
        let appointmentID = UUID()

        router.presentDetails(.appointment(appointmentID))

        #expect(router.detailsPresentation?.id == presentationID)
        #expect(router.detailsPresentation?.root == .appointment(appointmentID))
        #expect(router.detailsPresentation?.path == [])
    }

    @Test func dismissDetailsClearsTheCompletePresentation() {
        let router = Router()
        router.presentDetails(.appointment(UUID()))
        router.pushDetails(.patient(UUID()))

        router.dismissDetails()

        #expect(router.detailsPresentation == nil)
    }

    @Test func externalDetailsReplaceHistoryAndSelectTheUnderlyingTab() throws {
        let router = Router()
        router.presentDetails(.appointment(UUID()))
        router.pushDetails(.patient(UUID()))
        let previousID = try #require(router.detailsPresentation?.id)
        let patientID = UUID()

        router.openExternalDetails(.patient(patientID))

        #expect(router.selectedTab == .patients)
        #expect(router.detailsPresentation?.id == previousID)
        #expect(router.detailsPresentation?.root == .patient(patientID))
        #expect(router.detailsPresentation?.path == [])

        let patientPresentationID = try #require(router.detailsPresentation?.id)
        let appointmentID = UUID()
        router.openExternalDetails(.appointment(appointmentID))

        #expect(router.selectedTab == .schedule)
        #expect(router.detailsPresentation?.id == patientPresentationID)
        #expect(router.detailsPresentation?.root == .appointment(appointmentID))
        #expect(router.detailsPresentation?.path == [])
    }

    @Test func appointmentEditSuspendsDetailsUntilEditorDismissal() throws {
        let router = Router()
        let appointmentID = UUID()
        let details = appointmentDetails(id: appointmentID)
        let schedulePath: [Route] = [.patient(UUID())]
        let patientsPath: [Route] = [.appointment(UUID())]
        let detailsPath: [Route] = [.patient(UUID()), .appointment(appointmentID)]
        router.selectedTab = .patients
        router.schedulePath = schedulePath
        router.patientsPath = patientsPath
        router.presentDetails(.appointment(appointmentID))
        for route in detailsPath {
            router.pushDetails(route)
        }
        let presentation = try #require(router.detailsPresentation)

        router.requestAppointmentEdit(details)

        #expect(router.selectedTab == .schedule)
        #expect(router.detailsPresentation == nil)
        #expect(router.appointmentEditRequest == nil)
        #expect(router.schedulePath == schedulePath)
        #expect(router.patientsPath == patientsPath)

        router.detailsDidDismiss()

        #expect(router.appointmentEditRequest?.appointmentID == appointmentID)
        #expect(router.appointmentEditRequest?.details.patient.id == details.patient.id)

        let requestID = try #require(router.appointmentEditRequest?.id)
        router.consumeAppointmentEditRequest(requestID)
        router.appointmentEditorDidDismiss()

        #expect(router.selectedTab == .patients)
        #expect(router.detailsPresentation === presentation)
        #expect(router.detailsPresentation?.path == detailsPath)
        #expect(router.schedulePath == schedulePath)
        #expect(router.patientsPath == patientsPath)
    }

    @Test func appointmentEditRequestsAreUniquelyIdentifiedAndConsumedByIdentity() throws {
        let router = Router()
        let appointmentID = UUID()
        let details = appointmentDetails(id: appointmentID)

        router.requestAppointmentEdit(details)
        let firstRequest = try #require(router.appointmentEditRequest)
        router.consumeAppointmentEditRequest(UUID())
        #expect(router.appointmentEditRequest == firstRequest)

        router.consumeAppointmentEditRequest(firstRequest.id)
        #expect(router.appointmentEditRequest == nil)
        router.appointmentEditorDidDismiss()

        router.requestAppointmentEdit(details)
        #expect(router.appointmentEditRequest?.appointmentID == appointmentID)
        #expect(router.appointmentEditRequest?.id != firstRequest.id)
    }

    @Test func appointmentBookingFromPatientDetailsRestoresExactNavigationState() throws {
        let router = Router()
        let patient = Patient(name: "Aarav Mehta")
        let appointmentID = UUID()
        let schedulePath: [Route] = [.appointment(UUID())]
        let patientsPath: [Route] = [.patient(UUID())]
        let detailsPath: [Route] = [.appointment(appointmentID)]
        router.selectedTab = .patients
        router.schedulePath = schedulePath
        router.patientsPath = patientsPath
        router.presentDetails(.patient(patient.id))
        for route in detailsPath {
            router.pushDetails(route)
        }
        let presentation = try #require(router.detailsPresentation)

        router.requestAppointmentBooking(for: patient)

        #expect(router.selectedTab == .schedule)
        #expect(router.detailsPresentation == nil)
        #expect(router.appointmentBookingRequest == nil)
        #expect(router.schedulePath == schedulePath)
        #expect(router.patientsPath == patientsPath)

        router.detailsDidDismiss()

        let request = try #require(router.appointmentBookingRequest)
        #expect(request.patientID == patient.id)
        router.consumeAppointmentBookingRequest(request.id)
        router.appointmentEditorDidDismiss()

        #expect(router.selectedTab == .patients)
        #expect(router.detailsPresentation === presentation)
        #expect(router.detailsPresentation?.path == detailsPath)
        #expect(router.schedulePath == schedulePath)
        #expect(router.patientsPath == patientsPath)
    }

    @Test func patientEditRestoresExactDetailsHistoryWithoutChangingTabState() throws {
        let router = Router()
        let patient = Patient(name: "Aarav Mehta")
        let appointmentID = UUID()
        let schedulePath: [Route] = [.appointment(UUID())]
        let patientsPath: [Route] = [.patient(UUID())]
        let detailsPath: [Route] = [
            .appointment(appointmentID),
            .patient(patient.id),
        ]
        router.selectedTab = .schedule
        router.schedulePath = schedulePath
        router.patientsPath = patientsPath
        router.presentDetails(.patient(patient.id))
        for route in detailsPath {
            router.pushDetails(route)
        }
        let presentation = try #require(router.detailsPresentation)

        router.requestPatientEdit(patient)

        #expect(router.selectedTab == .schedule)
        #expect(router.detailsPresentation == nil)
        #expect(router.patientEditRequest == nil)
        #expect(router.schedulePath == schedulePath)
        #expect(router.patientsPath == patientsPath)

        router.detailsDidDismiss()

        let request = try #require(router.patientEditRequest)
        #expect(request.patientID == patient.id)
        router.consumePatientEditRequest(request.id)
        router.patientEditorDidDismiss()

        #expect(router.selectedTab == .schedule)
        #expect(router.detailsPresentation === presentation)
        #expect(router.detailsPresentation?.path == detailsPath)
        #expect(router.schedulePath == schedulePath)
        #expect(router.patientsPath == patientsPath)
    }

    @Test func editorRequestsCannotCompeteForTheDetailsHandoff() throws {
        let router = Router()
        let patient = Patient(name: "Aarav Mehta")
        router.presentDetails(.patient(patient.id))

        router.requestPatientEdit(patient)
        router.requestAppointmentEdit(appointmentDetails())
        router.detailsDidDismiss()

        #expect(router.patientEditRequest?.patientID == patient.id)
        #expect(router.appointmentEditRequest == nil)

        let requestID = try #require(router.patientEditRequest?.id)
        router.consumePatientEditRequest(requestID)
        router.requestAppointmentEdit(appointmentDetails())

        #expect(router.appointmentEditRequest == nil)
    }

    @Test func externalDetailsReplacePatientEditorsSuspendedSession() throws {
        let router = Router()
        let patient = Patient(name: "Aarav Mehta")
        router.selectedTab = .schedule
        router.presentDetails(.patient(patient.id))
        let presentation = try #require(router.detailsPresentation)

        router.requestPatientEdit(patient)
        let externalAppointmentID = UUID()
        router.openExternalDetails(.appointment(externalAppointmentID))
        router.detailsDidDismiss()

        let requestID = try #require(router.patientEditRequest?.id)
        router.consumePatientEditRequest(requestID)
        router.patientEditorDidDismiss()

        #expect(router.selectedTab == .schedule)
        #expect(router.detailsPresentation === presentation)
        #expect(router.detailsPresentation?.root == .appointment(externalAppointmentID))
        #expect(router.detailsPresentation?.path == [])
    }

    @Test func directAppointmentEditDoesNotRestoreDetails() throws {
        let router = Router()

        router.requestAppointmentEdit(appointmentDetails())
        let requestID = try #require(router.appointmentEditRequest?.id)
        router.consumeAppointmentEditRequest(requestID)
        router.appointmentEditorDidDismiss()

        #expect(router.selectedTab == .schedule)
        #expect(router.detailsPresentation == nil)
    }

    @Test func externalDetailsReplaceSuspendedSessionWithoutInterruptingEditing() throws {
        let router = Router()
        let editedAppointmentID = UUID()
        router.selectedTab = .patients
        router.presentDetails(.appointment(editedAppointmentID))
        let presentation = try #require(router.detailsPresentation)

        router.requestAppointmentEdit(appointmentDetails(id: editedAppointmentID))
        let externalPatientID = UUID()
        router.openExternalDetails(.patient(externalPatientID))

        #expect(router.selectedTab == .schedule)
        #expect(router.detailsPresentation == nil)

        router.detailsDidDismiss()
        let requestID = try #require(router.appointmentEditRequest?.id)
        router.consumeAppointmentEditRequest(requestID)
        router.appointmentEditorDidDismiss()

        #expect(router.selectedTab == .patients)
        #expect(router.detailsPresentation === presentation)
        #expect(router.detailsPresentation?.root == .patient(externalPatientID))
        #expect(router.detailsPresentation?.path == [])
    }

    private func appointmentDetails(id: Appointment.ID = UUID()) -> AppointmentDetails {
        let date = Date(timeIntervalSince1970: 0)
        let patient = Patient(name: "Aarav Mehta", createdDate: date)
        return AppointmentDetails(
            appointment: Appointment(
                id: id,
                patientName: patient.displayName,
                start: date,
                durationMinutes: 30,
                status: .scheduled
            ),
            patient: patient
        )
    }
}
