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

    func presentDetails(_ root: Route) {
        detailsPresentation = DetailsPresentation(root: root)
    }

    func pushDetails(_ route: Route) {
        guard detailsPresentation != nil else { return }
        detailsPresentation?.path.append(route)
    }

    func updateDetailsPath(_ path: [Route], presentationID: DetailsPresentation.ID) {
        guard detailsPresentation?.id == presentationID else { return }
        detailsPresentation?.path = path
    }

    func dismissDetails() {
        detailsPresentation = nil
    }

    func openExternalDetails(_ route: Route) {
        selectedTab =
            switch route {
            case .patient:
                .patients
            case .appointment:
                .schedule
            }
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
