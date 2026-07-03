import Foundation

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
