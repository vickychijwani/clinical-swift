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
    private(set) var appointmentEditRequest: AppointmentEditRequest?

    private var pendingAppointmentEditRequest: AppointmentEditRequest?
    private var suspendedDetailsSession: SuspendedDetailsSession?

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
        let request = AppointmentEditRequest(details: details)

        if let detailsPresentation {
            suspendedDetailsSession = SuspendedDetailsSession(
                presentation: detailsPresentation,
                returnTab: selectedTab
            )
            pendingAppointmentEditRequest = request
            selectedTab = .schedule
            dismissDetails()
        } else {
            selectedTab = .schedule
            appointmentEditRequest = request
        }
    }

    func detailsDidDismiss() {
        guard let pendingAppointmentEditRequest else { return }
        self.pendingAppointmentEditRequest = nil
        appointmentEditRequest = pendingAppointmentEditRequest
    }

    func consumeAppointmentEditRequest(_ requestID: AppointmentEditRequest.ID) {
        guard appointmentEditRequest?.id == requestID else { return }
        appointmentEditRequest = nil
    }

    func appointmentEditorDidDismiss() {
        guard let suspendedDetailsSession else { return }
        self.suspendedDetailsSession = nil
        selectedTab = suspendedDetailsSession.returnTab
        detailsPresentation = suspendedDetailsSession.presentation
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

private struct SuspendedDetailsSession {
    let presentation: DetailsPresentation
    var returnTab: AppTab
}
