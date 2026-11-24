import SwiftUI

struct DetailsFlowNavigation: View {
    @Environment(Router.self) private var router
    @Bindable var presentation: DetailsPresentation
    let requestDismiss: () -> Void

    var body: some View {
        let visitID = presentation.visitID
        let navigate: @MainActor @Sendable (Route) -> Void = { route in
            router.pushDetails(route, presentationID: presentation.id, visitID: visitID)
        }
        NavigationStack(path: pathBinding) {
            ZStack {
                DetailsRouteView(
                    route: presentation.root,
                    presentationID: presentation.id,
                    completionDrafts: presentation.completionDrafts,
                    onNavigate: navigate
                )
                .id(presentation.visitID)
                .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.15), value: presentation.root)
            .navigationDestination(for: Route.self) { route in
                DetailsRouteView(
                    route: route,
                    presentationID: presentation.id,
                    completionDrafts: presentation.completionDrafts,
                    onNavigate: navigate
                )
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if presentation.path.isEmpty {
                        Button("Close", systemImage: "xmark", action: requestDismiss)
                            .labelStyle(.iconOnly)
                            .disabled(presentation.isSavingCompletion)
                    }
                }
            }
        }
    }

    private var pathBinding: Binding<[Route]> {
        // Do not bind NavigationStack directly to the presentation's path. SwiftUI may write back
        // during dismissal, so the router must validate the sheet-session ID before mutating it.
        let visitID = presentation.visitID
        return Binding(
            get: { presentation.path },
            set: {
                guard presentation.visitID == visitID else { return }
                router.setDetailsPath($0, presentationID: presentation.id)
            }
        )
    }

}

struct DetailsFlowView: View {
    @Bindable var presentation: DetailsPresentation
    @Environment(Router.self) private var router
    @Environment(\.traySurfaceMetrics) private var metrics

    static func traySize(for presentation: DetailsPresentation) -> TraySize {
        presentation.showsCompletion ? .height(400) : .height(280)
    }

    var body: some View {
        switch presentation.root {
        case .appointment(let appointmentID):
            AppointmentRootCarouselFlow(
                presentation: presentation,
                initialAppointmentID: appointmentID,
                initialScheduleDate: router.selectedScheduleDate,
                requestDismiss: requestDismiss
            )
        case .patient, .appointmentCompletion:
            DetailsFlowNavigation(
                presentation: presentation,
                requestDismiss: requestDismiss
            )
            // The standalone navigation bar supplies ten points of top space. Add six to
            // match the native sheet's sixteen-point header without changing its controls.
            .padding(.top, 6)
            .safeAreaPadding(.bottom, metrics.bottomInset + metrics.keyboardHeight)
            .modifier(
                TrayFrame(
                    topEdge: metrics.topEdge, size: metrics.size, safeArea: metrics.safeArea,
                    showsIndicator: metrics.showsIndicator)
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("tray-surface")
            .trayOptions(
                size: Self.traySize(for: presentation),
                allowsInteractiveDismiss: !presentation.showsCompletion
                    && !presentation.isSavingCompletion,
                showsIndicator: !presentation.showsCompletion,
                requestDismiss: requestDismiss
            )
        }
    }

    private func requestDismiss() {
        guard router.detailsPresentation === presentation,
            !presentation.showsCompletion, !presentation.isSavingCompletion
        else { return }
        router.dismissDetails(presentationID: presentation.id)
    }
}
