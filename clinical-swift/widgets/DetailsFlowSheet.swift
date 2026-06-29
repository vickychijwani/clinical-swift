import SwiftUI

struct DetailsFlowSheet: View {
    @Environment(Router.self) private var router

    let presentation: DetailsPresentation

    @State private var selectedDetent: PresentationDetent = .medium

    var body: some View {
        NavigationStack(path: detailsPath) {
            DetailsRouteView(
                route: presentation.root,
                onNavigate: navigate
            )
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
        .presentationDetents(availableDetents, selection: $selectedDetent)
        .presentationBackground(Color("AppBackground"))
        .presentationContentInteraction(.resizes)
    }

    private var detailsPath: Binding<[Route]> {
        Binding(
            get: {
                guard router.detailsPresentation?.id == presentation.id else { return [] }
                return router.detailsPresentation?.path ?? []
            },
            set: { path in
                router.updateDetailsPath(path, presentationID: presentation.id)
            }
        )
    }

    private var currentRoute: Route {
        guard router.detailsPresentation?.id == presentation.id else {
            return presentation.root
        }
        return router.detailsPresentation?.path.last ?? presentation.root
    }

    private var isAtRoot: Bool {
        guard router.detailsPresentation?.id == presentation.id else { return true }
        return router.detailsPresentation?.path.isEmpty ?? true
    }

    private var availableDetents: Set<PresentationDetent> {
        switch currentRoute {
        case .patient:
            [.medium]
        case .appointment:
            [.height(220), .medium, .large]
        }
    }

    private func navigate(to route: Route) {
        if case .patient = route {
            selectedDetent = .medium
        }
        router.pushDetails(route)
    }
}
