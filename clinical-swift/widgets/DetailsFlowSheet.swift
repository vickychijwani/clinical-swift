import SwiftUI

struct DetailsFlowSheet: View {
    @Environment(Router.self) private var router

    @Bindable var presentation: DetailsPresentation

    var body: some View {
        NavigationStack(path: pathBinding) {
            ZStack {
                DetailsRouteView(
                    route: presentation.root,
                    presentationID: presentation.id,
                    onNavigate: navigate
                )
                .id(presentation.root)
                .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.15), value: presentation.root)
            .navigationDestination(for: Route.self) { route in
                DetailsRouteView(
                    route: route,
                    presentationID: presentation.id,
                    onNavigate: navigate
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if isAtRoot {
                    Button("Close", systemImage: "xmark") {
                        router.dismissDetails()
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
        .presentationDetents([.height(280), .medium])
        .presentationBackground(AppColor.canvas)
        .presentationContentInteraction(.resizes)
    }

    private var isAtRoot: Bool {
        presentation.path.isEmpty
    }

    private var pathBinding: Binding<[Route]> {
        // Do not bind NavigationStack directly to the presentation's path. SwiftUI may write back
        // during dismissal, so the router must validate the sheet-session ID before mutating it.
        Binding(
            get: { presentation.path },
            set: { router.setDetailsPath($0, presentationID: presentation.id) }
        )
    }

    private func navigate(to route: Route) {
        router.pushDetails(route)
    }
}
