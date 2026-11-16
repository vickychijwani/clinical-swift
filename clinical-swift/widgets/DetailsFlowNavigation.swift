import SwiftUI

struct DetailsFlowNavigation: View {
    @Environment(Router.self) private var router
    @Bindable var presentation: DetailsPresentation
    let dismissAction: TrayCancelAction

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
                        TrayCancelButton(action: dismissAction, label: "Close")
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
    @Environment(\.trayDismiss) private var dismiss
    @Bindable var presentation: DetailsPresentation
    @Environment(Router.self) private var router
    @State private var policy = DetailsDismissal()

    static func traySize(for presentation: DetailsPresentation) -> TraySize {
        presentation.showsCompletion ? .height(400) : .height(280)
    }

    var body: some View {
        DetailsFlowNavigation(
            presentation: presentation,
            dismissAction: TrayCancelAction(
                title: "Discard unsaved payment?",
                message: "Your payment changes have not been saved.",
                hasUnsavedChanges: { presentation.hasUnsavedCompletion },
                dismiss: { dismiss() })
        )
        .trayOptions(
            size: Self.traySize(for: presentation),
            allowsInteractiveDismiss: !presentation.showsCompletion
                && !presentation.isSavingCompletion,
            showsIndicator: !presentation.showsCompletion,
            requestDismiss: { policy.request(router: router, presentation: presentation) }
        )
        .confirmationDialog(
            "Discard unsaved payment?", isPresented: $policy.isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard Changes", role: .destructive) {
                policy.discard(router: router, presentation: presentation)
            }
        } message: {
            Text("Your payment changes have not been saved.")
        }
    }
}

/// A discard prompt belongs to the visit that opened it, even if its session is reused.
@MainActor @Observable
final class DetailsDismissal {
    var isConfirmingDiscard = false
    private var visitID: UUID?

    func request(router: Router, presentation: DetailsPresentation) {
        guard router.detailsPresentation === presentation,
            !presentation.showsCompletion, !presentation.isSavingCompletion
        else { return }
        if presentation.hasUnsavedCompletion {
            visitID = presentation.visitID
            isConfirmingDiscard = true
        } else {
            router.dismissDetails(presentationID: presentation.id)
        }
    }

    func discard(router: Router, presentation: DetailsPresentation) {
        guard router.detailsPresentation === presentation, visitID == presentation.visitID,
            !presentation.showsCompletion, !presentation.isSavingCompletion
        else { return }
        router.dismissDetails(presentationID: presentation.id)
    }
}
