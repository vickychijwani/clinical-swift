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
    private(set) var appointmentMessageRequest: AppointmentMessageRequest?
    private(set) var patientEditRequest: PatientEditRequest?

    private var pendingSheetHandoff: PendingSheetHandoff?
    private var suspendedDetailsSession: SuspendedDetailsSession?
    private var activeSheetSession: SheetSession?

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
        guard canRequestSheet else { return }
        let request = AppointmentEditRequest(details: details)
        activeSheetSession = .appointment

        if let detailsPresentation {
            suspendedDetailsSession = SuspendedDetailsSession(
                presentation: detailsPresentation,
                returnTab: selectedTab
            )
            pendingSheetHandoff = .appointment(request)
            selectedTab = .schedule
            dismissDetails()
        } else {
            selectedTab = .schedule
            appointmentEditRequest = request
        }
    }

    func requestAppointmentBooking(for patient: Patient) {
        guard canRequestSheet else { return }
        let request = AppointmentBookingRequest(patient: patient)
        activeSheetSession = .appointment

        if let detailsPresentation {
            suspendedDetailsSession = SuspendedDetailsSession(
                presentation: detailsPresentation,
                returnTab: selectedTab
            )
            pendingSheetHandoff = .appointmentBooking(request)
            selectedTab = .schedule
            dismissDetails()
        } else {
            selectedTab = .schedule
            appointmentBookingRequest = request
        }
    }

    func requestAppointmentMessage(_ details: AppointmentDetails) {
        guard canRequestSheet else { return }
        let request = AppointmentMessageRequest(appointmentID: details.appointment.id)
        activeSheetSession = .appointmentMessage

        if let detailsPresentation {
            suspendedDetailsSession = SuspendedDetailsSession(
                presentation: detailsPresentation,
                returnTab: selectedTab
            )
            pendingSheetHandoff = .appointmentMessage(request)
            selectedTab = .schedule
            dismissDetails()
        } else {
            selectedTab = .schedule
            appointmentMessageRequest = request
        }
    }

    func requestPatientEdit(_ patient: Patient) {
        guard canRequestSheet else { return }
        let request = PatientEditRequest(patient: patient)
        activeSheetSession = .patient

        if let detailsPresentation {
            suspendedDetailsSession = SuspendedDetailsSession(
                presentation: detailsPresentation,
                returnTab: selectedTab
            )
            pendingSheetHandoff = .patient(request)
            dismissDetails()
        } else {
            patientEditRequest = request
        }
    }

    func detailsDidDismiss() {
        guard let pendingSheetHandoff else { return }
        self.pendingSheetHandoff = nil

        switch pendingSheetHandoff {
        case .appointmentBooking(let request):
            appointmentBookingRequest = request
        case .appointment(let request):
            appointmentEditRequest = request
        case .appointmentMessage(let request):
            appointmentMessageRequest = request
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

    func consumeAppointmentMessageRequest(_ requestID: AppointmentMessageRequest.ID) {
        guard appointmentMessageRequest?.id == requestID else { return }
        appointmentMessageRequest = nil
    }

    func consumePatientEditRequest(_ requestID: PatientEditRequest.ID) {
        guard patientEditRequest?.id == requestID else { return }
        patientEditRequest = nil
    }

    func appointmentEditorDidDismiss() {
        guard activeSheetSession == .appointment else { return }
        activeSheetSession = nil
        restoreSuspendedDetailsSession()
    }

    func appointmentMessageDidDismiss() {
        guard activeSheetSession == .appointmentMessage else { return }
        activeSheetSession = nil
        restoreSuspendedDetailsSession()
    }

    func patientEditorDidDismiss() {
        guard activeSheetSession == .patient else { return }
        activeSheetSession = nil
        restoreSuspendedDetailsSession()
    }

    private func restoreSuspendedDetailsSession() {
        guard let suspendedDetailsSession else { return }
        self.suspendedDetailsSession = nil
        selectedTab = suspendedDetailsSession.returnTab
        detailsPresentation = suspendedDetailsSession.presentation
    }

    private var canRequestSheet: Bool {
        activeSheetSession == nil
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

nonisolated struct AppointmentMessageRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let appointmentID: Appointment.ID

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

private enum PendingSheetHandoff {
    case appointmentBooking(AppointmentBookingRequest)
    case appointment(AppointmentEditRequest)
    case appointmentMessage(AppointmentMessageRequest)
    case patient(PatientEditRequest)
}

private enum SheetSession {
    case appointment
    case appointmentMessage
    case patient
}
