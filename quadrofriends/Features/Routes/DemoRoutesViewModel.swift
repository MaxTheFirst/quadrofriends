import Combine
import Foundation

enum MyRoutesTab: String, CaseIterable, Identifiable {
    case recent = "Недавние"
    case privateRoutes = "Приватные"

    var id: Self { self }
}

enum RouteSearchFilter: String, CaseIterable, Identifiable {
    case all = "Все"
    case publicRoutes = "Публичные"
    case privateRoutes = "Приватные"

    var id: Self { self }
}

/// Готовит сохранённые маршруты и папки для экранов деморежима.
@MainActor
final class DemoRoutesViewModel: ObservableObject {
    @Published private(set) var routes: [TrailRoute] = []
    @Published private(set) var folders: [RouteFolder] = []

    private let dataSource: any DemoRoutesDataSource

    init(dataSource: (any DemoRoutesDataSource)? = nil) {
        self.dataSource = dataSource ?? DemoRepository.shared
        reload()
    }

    func reload() {
        routes = dataSource.routes()
        folders = dataSource.folders()
    }

    func routes(for tab: MyRoutesTab) -> [TrailRoute] {
        tab == .recent ? routes : routes.filter(\.isPrivate)
    }

    func search(query: String, filter: RouteSearchFilter) -> [TrailRoute] {
        routes.filter { route in
            let matchesQuery = query.isEmpty
                || route.title.localizedCaseInsensitiveContains(query)
                || route.description.localizedCaseInsensitiveContains(query)
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .publicRoutes: matchesFilter = !route.isPrivate
            case .privateRoutes: matchesFilter = route.isPrivate
            }
            return matchesQuery && matchesFilter
        }
    }

    var recommendedRoutes: [TrailRoute] { Array(routes.prefix(2)) }

    func route(id: String) -> TrailRoute? { routes.first { $0.id == id } }

    func publicRoutes(for authorID: String?, ownProfile: Bool) -> [TrailRoute] {
        let publicRoutes = routes.filter { !$0.isPrivate }
        return ownProfile
            ? Array(publicRoutes.prefix(3))
            : publicRoutes.filter { $0.author.id == authorID }
    }
}
