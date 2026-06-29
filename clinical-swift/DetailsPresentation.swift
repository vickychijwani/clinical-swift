import Foundation

struct DetailsPresentation: Identifiable, Hashable {
    let id: UUID
    let root: Route
    var path: [Route]

    init(
        id: UUID = UUID(),
        root: Route,
        path: [Route] = []
    ) {
        self.id = id
        self.root = root
        self.path = path
    }
}
