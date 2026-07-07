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
    var selectedTab: AppTab = .schedule  // Home screen is Schedule tab
    var schedulePath: [Route] = []
    var patientsPath: [Route] = []
    var paymentsPath: [Route] = []
    var detailsPresentation: DetailsPresentation?
    private(set) var appointmentBookingRequest: AppointmentBookingRequest?
    private(set) var appointmentEditRequest: AppointmentEditRequest?
    private(set) var patientEditRequest: PatientEditRequest?

    private var pendingEditorHandoff: PendingEditorHandoff?
    private var suspendedDetailsSession: SuspendedDetailsSession?
    private var activeEditorSession: EditorSession?

    func presentDetails(_ root: Route) {
        if let detailsPresentation {
            // Keep the active sheet session stable so background selections replace its content.
            // e.g., when switching between selected appointments
            detailsPresentation.replaceRoot(with: root)
        } else {
            detailsPresentation = DetailsPresentation(root: root)
        }
    }

    func pushDetails(_ route: Route) {
        guard detailsPresentation != nil else { return }
        detailsPresentation?.path.append(route)
    }

    func dismissDetails() {
        detailsPresentation = nil
    }

    func requestAppointmentEdit(_ details: AppointmentDetails) {
        guard canRequestEditor else { return }
        let request = AppointmentEditRequest(details: details)
        activeEditorSession = .appointment

        if let detailsPresentation {
            suspendedDetailsSession = SuspendedDetailsSession(
                presentation: detailsPresentation,
                returnTab: selectedTab
            )
            pendingEditorHandoff = .appointment(request)
            selectedTab = .schedule
            dismissDetails()
        } else {
            selectedTab = .schedule
            appointmentEditRequest = request
        }
    }

    func requestAppointmentBooking(for patient: Patient) {
        guard canRequestEditor else { return }
        let request = AppointmentBookingRequest(patient: patient)
        activeEditorSession = .appointment

        if let detailsPresentation {
            suspendedDetailsSession = SuspendedDetailsSession(
                presentation: detailsPresentation,
                returnTab: selectedTab
            )
            pendingEditorHandoff = .appointmentBooking(request)
            selectedTab = .schedule
            dismissDetails()
        } else {
            selectedTab = .schedule
            appointmentBookingRequest = request
        }
    }

    func requestPatientEdit(_ patient: Patient) {
        guard canRequestEditor else { return }
        let request = PatientEditRequest(patient: patient)
        activeEditorSession = .patient

        if let detailsPresentation {
            suspendedDetailsSession = SuspendedDetailsSession(
                presentation: detailsPresentation,
                returnTab: selectedTab
            )
            pendingEditorHandoff = .patient(request)
            dismissDetails()
        } else {
            patientEditRequest = request
        }
    }

    func detailsDidDismiss() {
        guard let pendingEditorHandoff else { return }
        self.pendingEditorHandoff = nil

        switch pendingEditorHandoff {
        case .appointmentBooking(let request):
            appointmentBookingRequest = request
        case .appointment(let request):
            appointmentEditRequest = request
        case .patient(let request):
            patientEditRequest = request
        }
    }

    func consumeAppointmentEditRequest(_ requestID: AppointmentEditRequest.ID) {
        guard appointmentEditRequest?.id == requestID else { return }
        appointmentEditRequest = nil
    }

    func consumeAppointmentBookingRequest(_ requestID: AppointmentBookingRequest.ID) {
        guard appointmentBookingRequest?.id == requestID else { return }
        appointmentBookingRequest = nil
    }

    func consumePatientEditRequest(_ requestID: PatientEditRequest.ID) {
        guard patientEditRequest?.id == requestID else { return }
        patientEditRequest = nil
    }

    func appointmentEditorDidDismiss() {
        guard activeEditorSession == .appointment else { return }
        activeEditorSession = nil
        restoreSuspendedDetailsSession()
    }

    func patientEditorDidDismiss() {
        guard activeEditorSession == .patient else { return }
        activeEditorSession = nil
        restoreSuspendedDetailsSession()
    }

    private func restoreSuspendedDetailsSession() {
        guard let suspendedDetailsSession else { return }
        self.suspendedDetailsSession = nil
        selectedTab = suspendedDetailsSession.returnTab
        detailsPresentation = suspendedDetailsSession.presentation
    }

    private var canRequestEditor: Bool {
        activeEditorSession == nil
    }

    func openExternalDetails(_ route: Route) {
        let destinationTab: AppTab =
            switch route {
            case .patient:
                .patients
            case .appointment:
                .schedule
            }

        if var suspendedDetailsSession {
            suspendedDetailsSession.presentation.replaceRoot(with: route)
            suspendedDetailsSession.returnTab = destinationTab
            self.suspendedDetailsSession = suspendedDetailsSession
            return
        }

        selectedTab = destinationTab
        presentDetails(route)
    }

    func openPatient(_ id: UUID, in tab: AppTab?) {
        // This keyPath stuff is needed because returning schedulePath directly
        // from the called helper returns the array by value, not by reference
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

    /// Returns a reference to appropriate xyzPath field so that it can be mutated
    private func getKeyPath(for tab: AppTab?) -> ReferenceWritableKeyPath<
        Router, [Route]
    > {
        return switch tab ?? selectedTab {
        case .schedule:
            \.schedulePath
        case .patients:
            \.patientsPath
        case .payments:
            \.paymentsPath
        }
    }
}

@MainActor @Observable
final class DetailsPresentation: Identifiable {
    let id: UUID
    private(set) var root: Route
    var path: [Route]

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

    func replaceRoot(with route: Route) {
        root = route
        path.removeAll()
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
    let patient: Patient

    var patientID: Patient.ID {
        patient.id
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

nonisolated struct PatientEditRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let patient: Patient

    var patientID: Patient.ID {
        patient.id
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

private struct SuspendedDetailsSession {
    let presentation: DetailsPresentation
    var returnTab: AppTab
}

private enum PendingEditorHandoff {
    case appointmentBooking(AppointmentBookingRequest)
    case appointment(AppointmentEditRequest)
    case patient(PatientEditRequest)
}

private enum EditorSession {
    case appointment
    case patient
}
