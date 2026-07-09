import SwiftUI

struct DetailsFlowSheet: View {
    @Environment(Router.self) private var router

    @Bindable var presentation: DetailsPresentation

    var body: some View {
        NavigationStack(path: $presentation.path) {
            ZStack {
                DetailsRouteView(
                    route: presentation.root,
                    onNavigate: navigate
                )
                .id(presentation.root)
                .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.15), value: presentation.root)
            .navigationDestination(for: Route.self) { route in
                DetailsRouteView(
                    route: route,
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
        .presentationBackground(Color("AppBackground"))
        .presentationContentInteraction(.resizes)
    }

    private var isAtRoot: Bool {
        presentation.path.isEmpty
    }

    private func navigate(to route: Route) {
        router.pushDetails(route)
    }
}
