import Dependencies
import Foundation

enum AppTab: Hashable {
    case schedule
    case patients
    case payments
}

enum Route: Hashable {
    case patient(_ id: UUID)
    case appointment(_ id: UUID)
}

@MainActor @Observable
final class Router {
    @ObservationIgnored @Dependency(\.calendar) private var calendar

    var selectedTab: AppTab = .schedule  // Home screen is Schedule tab
    var schedulePath: [Route] = []
    var patientsPath: [Route] = []
    var paymentsPath: [Route] = []

    // Schedule selection lives here so every entry point (UI, URL, widget, or App Intent) changes
    // the same date that is visible behind appointment details.
    private(set) var selectedScheduleDate: Date

    // Invariant: the app has exactly one app-root presentation intent. Independent optional sheet
    // state can make multiple hosts present at once or resurrect an older flow after interruption.
    private(set) var activePresentation: AppPresentation?
    private(set) var patientSearchRequest: PatientSearchRequest?

    // SwiftUI cannot replace an already-presented sheet in one state change. Keep only the newest
    // replacement while the visible sheet dismisses, and track whether an onDismiss callback is
    // actually expected so an action replaced before appearing can activate immediately.
    private var replacementPresentation: AppPresentation?
    private var presentedPresentationID: UUID?
    private var dismissingPresentationID: UUID?

    init(selectedScheduleDate: Date = .now) {
        @Dependency(\.calendar) var calendar
        self.selectedScheduleDate = selectedScheduleDate.startOfDay(using: calendar)
    }

    var detailsPresentation: DetailsPresentation? {
        guard case .details(let presentation) = activePresentation else { return nil }
        return presentation
    }

    var appointmentBookingRequest: AppointmentBookingRequest? {
        guard case .appointmentBooking(let request) = activePresentation else { return nil }
        return request
    }

    var appointmentEditRequest: AppointmentEditRequest? {
        guard case .appointmentEdit(let request) = activePresentation else { return nil }
        return request
    }

    var appointmentMessageRequest: AppointmentMessageRequest? {
        guard case .appointmentMessage(let request) = activePresentation else { return nil }
        return request
    }

    var patientEditRequest: PatientEditRequest? {
        guard case .patientEdit(let request) = activePresentation else { return nil }
        return request
    }

    func presentDetails(_ root: Route) {
        if let detailsPresentation, dismissingPresentationID == nil {
            // A new selection behind the visible details sheet replaces its content in place. Keep
            // the session ID stable so SwiftUI does not perform an unnecessary sheet handoff.
            detailsPresentation.replaceRoot(with: root)
        } else {
            requestPresentation(.details(DetailsPresentation(root: root)))
        }
    }

    func pushDetails(_ route: Route) {
        detailsPresentation?.push(route)
    }

    func setDetailsPath(_ path: [Route], presentationID: DetailsPresentation.ID) {
        // NavigationStack can write its path back after a sheet has been replaced. The session ID
        // prevents that stale write from mutating the new details flow.
        guard let detailsPresentation, detailsPresentation.id == presentationID else { return }
        detailsPresentation.setPath(path)
    }

    func dismissDetails() {
        guard detailsPresentation != nil else { return }
        discardActivePresentation()
    }

    func dismissPresentation() {
        discardActivePresentation()
    }

    func selectScheduleDate(_ date: Date) {
        let normalizedDate = date.startOfDay(using: calendar)
        guard !calendar.isDate(normalizedDate, inSameDayAs: selectedScheduleDate) else { return }

        selectedScheduleDate = normalizedDate
        // Invariant: appointment details for date X must never remain over schedule date Y. A
        // direct date selection is a new navigation action, so discard the complete details flow.
        if detailsPresentation != nil {
            discardActivePresentation()
        }
    }

    func alignSchedule(
        with appointmentDate: Date,
        appointmentID: Appointment.ID,
        presentationID: DetailsPresentation.ID
    ) {
        // Appointment records resolve asynchronously. Require both the sheet session and its
        // current route to match so a late result cannot change the tab or date after navigation.
        guard
            isCurrentDetailsRoute(
                .appointment(appointmentID),
                presentationID: presentationID
            )
        else { return }

        selectedTab = .schedule
        selectedScheduleDate = appointmentDate.startOfDay(using: calendar)
    }

    func scheduleIsAligned(
        with appointmentDate: Date,
        appointmentID: Appointment.ID,
        presentationID: DetailsPresentation.ID
    ) -> Bool {
        guard
            selectedTab == .schedule,
            isCurrentDetailsRoute(
                .appointment(appointmentID),
                presentationID: presentationID
            )
        else { return false }

        return calendar.isDate(appointmentDate, inSameDayAs: selectedScheduleDate)
    }

    func isCurrentDetailsRoute(
        _ route: Route,
        presentationID: DetailsPresentation.ID
    ) -> Bool {
        guard let detailsPresentation, detailsPresentation.id == presentationID else {
            return false
        }
        return detailsPresentation.currentRoute == route
    }

    func requestAppointmentEdit(_ details: AppointmentDetails) {
        selectedTab = .schedule
        selectedScheduleDate = details.appointment.start.startOfDay(using: calendar)
        requestPresentation(.appointmentEdit(AppointmentEditRequest(details: details)))
    }

    func requestAppointmentBooking(for patient: Patient? = nil) {
        selectedTab = .schedule
        requestPresentation(.appointmentBooking(AppointmentBookingRequest(patient: patient)))
    }

    func requestAppointmentMessage(_ details: AppointmentDetails) {
        selectedTab = .schedule
        selectedScheduleDate = details.appointment.start.startOfDay(using: calendar)
        requestPresentation(
            .appointmentMessage(
                AppointmentMessageRequest(appointmentID: details.appointment.id)
            )
        )
    }

    func requestPatientEdit(_ patient: Patient) {
        requestPresentation(.patientEdit(PatientEditRequest(patient: patient)))
    }

    func requestPatientCreation() {
        requestPresentation(.patientEdit(PatientEditRequest(patient: nil)))
    }

    func presentationDidAppear(_ presentationID: UUID) {
        // Only a sheet that actually appeared will later send onDismiss. This distinction lets an
        // action supersede an unpresented request without waiting for a callback that will not come.
        guard activePresentation?.id == presentationID else { return }
        presentedPresentationID = presentationID
    }

    func presentationDidDismiss() {
        presentedPresentationID = nil
        // onDismiss either completes a router-driven handoff or reports that the user dismissed
        // the active sheet. Preserve a queued replacement only in the former case.
        if dismissingPresentationID != nil {
            self.dismissingPresentationID = nil
        } else {
            activePresentation = nil
        }

        activateReplacementIfPossible()
    }

    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let clinicalURL = ClinicalURL(url) else { return false }

        switch clinicalURL {
        case .bookAppointment:
            requestAppointmentBooking()
        case .appointment(let id):
            openAppointment(id: id)
        case .schedule(let day):
            openExternalSchedule(day)
        }
        return true
    }

    func openAppointment(id: Appointment.ID) {
        selectedTab = .schedule
        // ID-only entry points do not know the appointment date yet. AppointmentDetailsView keeps
        // neutral content visible until the resolved record aligns the router-owned schedule date.
        presentDetails(.appointment(id))
    }

    func openExternalDetails(_ route: Route) {
        switch route {
        case .patient:
            selectedTab = .patients
            presentDetails(route)
        case .appointment(let id):
            openAppointment(id: id)
        }
    }

    func openExternalPatientSearch(phoneNumbers: Set<String>) {
        let normalizedPhoneNumbers = Set(phoneNumbers.compactMap(PhoneNumber.normalizedE164))
        guard !normalizedPhoneNumbers.isEmpty else { return }

        selectedTab = .patients
        discardAllPresentations()
        patientSearchRequest = PatientSearchRequest(phoneNumbers: normalizedPhoneNumbers)
    }

    func openExternalSchedule(_ day: ScheduleDay) {
        guard let date = day.date(using: calendar) else { return }

        selectedTab = .schedule
        discardAllPresentations()
        patientSearchRequest = nil
        selectedScheduleDate = date
    }

    func consumePatientSearchRequest(_ requestID: PatientSearchRequest.ID) {
        guard patientSearchRequest?.id == requestID else { return }
        patientSearchRequest = nil
    }

    func openPatient(_ id: UUID, in tab: AppTab?) {
        self[keyPath: getKeyPath(for: tab)].append(.patient(id))
    }

    func openAppointment(_ id: UUID, in tab: AppTab?) {
        self[keyPath: getKeyPath(for: tab)].append(.appointment(id))
    }

    func pop(in tab: AppTab?) {
        let keyPath = getKeyPath(for: tab)
        var path = self[keyPath: keyPath]
        guard !path.isEmpty else { return }
        path.removeLast()
        self[keyPath: keyPath] = path
    }

    func popToRoot(in tab: AppTab?) {
        self[keyPath: getKeyPath(for: tab)].removeAll()
    }

    private func requestPresentation(_ presentation: AppPresentation) {
        // App-root actions are latest-wins interruptions. Do not queue multiple sheets or restore
        // the interrupted presentation after the replacement ends; its transient state is stale.
        patientSearchRequest = nil
        replacementPresentation = presentation

        guard dismissingPresentationID == nil else { return }

        if let activePresentation {
            self.activePresentation = nil
            if presentedPresentationID == activePresentation.id {
                dismissingPresentationID = activePresentation.id
            } else {
                activateReplacementIfPossible()
            }
        } else {
            activateReplacementIfPossible()
        }
    }

    private func discardActivePresentation() {
        guard dismissingPresentationID == nil, let activePresentation else { return }

        replacementPresentation = nil
        self.activePresentation = nil
        if presentedPresentationID == activePresentation.id {
            dismissingPresentationID = activePresentation.id
        } else {
            activateReplacementIfPossible()
        }
    }

    private func discardAllPresentations() {
        // External non-sheet destinations supersede both the visible sheet and any replacement
        // already waiting for its dismissal to complete.
        replacementPresentation = nil
        discardActivePresentation()
    }

    private func activateReplacementIfPossible() {
        guard
            activePresentation == nil,
            dismissingPresentationID == nil,
            let replacementPresentation
        else { return }

        self.replacementPresentation = nil
        activePresentation = replacementPresentation
    }

    private func getKeyPath(for tab: AppTab?) -> ReferenceWritableKeyPath<Router, [Route]> {
        switch tab ?? selectedTab {
        case .schedule:
            \.schedulePath
        case .patients:
            \.patientsPath
        case .payments:
            \.paymentsPath
        }
    }
}

/// The mutually exclusive app-root flows. Sheet hosts expose individual cases as computed values,
/// but this enum remains the sole source of presentation truth.
enum AppPresentation {
    case details(DetailsPresentation)
    case appointmentBooking(AppointmentBookingRequest)
    case appointmentEdit(AppointmentEditRequest)
    case appointmentMessage(AppointmentMessageRequest)
    case patientEdit(PatientEditRequest)

    var id: UUID {
        switch self {
        case .details(let presentation):
            presentation.id
        case .appointmentBooking(let request):
            request.id
        case .appointmentEdit(let request):
            request.id
        case .appointmentMessage(let request):
            request.id
        case .patientEdit(let request):
            request.id
        }
    }

}

@MainActor @Observable
final class DetailsPresentation: Identifiable {
    /// Stable identity for one details-sheet session. Its root may be replaced in place, while
    /// asynchronous route work and NavigationStack write-backs use this ID to reject stale events
    /// from a sheet session that has already been discarded.
    let id: UUID
    private(set) var root: Route

    // Keep mutation router-owned so every NavigationStack write-back can be checked against `id`.
    private(set) var path: [Route]

    var currentRoute: Route {
        path.last ?? root
    }

    init(
        id: UUID = UUID(),
        root: Route,
        path: [Route] = []
    ) {
        self.id = id
        self.root = root
        self.path = path
    }

    fileprivate func replaceRoot(with route: Route) {
        root = route
        path.removeAll()
    }

    fileprivate func push(_ route: Route) {
        path.append(route)
    }

    fileprivate func setPath(_ path: [Route]) {
        self.path = path
    }
}

nonisolated struct AppointmentEditRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let details: AppointmentDetails

    var appointmentID: Appointment.ID {
        details.appointment.id
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

nonisolated struct AppointmentBookingRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let patient: Patient?

    var patientID: Patient.ID? {
        patient?.id
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

nonisolated struct AppointmentMessageRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let appointmentID: Appointment.ID

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

nonisolated struct PatientEditRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let patient: Patient?

    var patientID: Patient.ID? {
        patient?.id
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

nonisolated struct PatientSearchRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let phoneNumbers: Set<String>

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}
