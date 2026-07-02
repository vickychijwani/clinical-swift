import Foundation
import Testing

@testable import clinical_swift

struct RouterTests {
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

    @Test func detailsPushAndPathUpdateRequireAnActiveMatchingPresentation() throws {
        let router = Router()
        router.pushDetails(.patient(UUID()))
        #expect(router.detailsPresentation == nil)

        router.presentDetails(.patient(UUID()))
        let presentationID = try #require(router.detailsPresentation?.id)
        router.updateDetailsPath([.appointment(UUID())], presentationID: UUID())
        #expect(router.detailsPresentation?.path == [])

        let route = Route.appointment(UUID())
        router.updateDetailsPath([route], presentationID: presentationID)
        #expect(router.detailsPresentation?.path == [route])
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
        #expect(router.detailsPresentation?.id != previousID)
        #expect(router.detailsPresentation?.root == .patient(patientID))
        #expect(router.detailsPresentation?.path == [])

        let patientPresentationID = try #require(router.detailsPresentation?.id)
        let appointmentID = UUID()
        router.openExternalDetails(.appointment(appointmentID))

        #expect(router.selectedTab == .schedule)
        #expect(router.detailsPresentation?.id != patientPresentationID)
        #expect(router.detailsPresentation?.root == .appointment(appointmentID))
        #expect(router.detailsPresentation?.path == [])
    }

    @Test func appointmentEditWaitsForDetailsDismissalAndPreservesTabPaths() {
        let router = Router()
        let appointmentID = UUID()
        let schedulePath: [Route] = [.patient(UUID())]
        let patientsPath: [Route] = [.appointment(UUID())]
        router.selectedTab = .patients
        router.schedulePath = schedulePath
        router.patientsPath = patientsPath
        router.presentDetails(.appointment(appointmentID))

        router.requestAppointmentEdit(appointmentID)

        #expect(router.selectedTab == .schedule)
        #expect(router.detailsPresentation == nil)
        #expect(router.appointmentEditRequest == nil)
        #expect(router.schedulePath == schedulePath)
        #expect(router.patientsPath == patientsPath)

        router.detailsDidDismiss()

        #expect(router.appointmentEditRequest?.appointmentID == appointmentID)
    }

    @Test func appointmentEditRequestsAreUniquelyIdentifiedAndConsumedByIdentity() throws {
        let router = Router()
        let appointmentID = UUID()

        router.requestAppointmentEdit(appointmentID)
        let firstRequest = try #require(router.appointmentEditRequest)
        router.consumeAppointmentEditRequest(UUID())
        #expect(router.appointmentEditRequest == firstRequest)

        router.consumeAppointmentEditRequest(firstRequest.id)
        #expect(router.appointmentEditRequest == nil)

        router.requestAppointmentEdit(appointmentID)
        #expect(router.appointmentEditRequest?.appointmentID == appointmentID)
        #expect(router.appointmentEditRequest?.id != firstRequest.id)
    }
}
