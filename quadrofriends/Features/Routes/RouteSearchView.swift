import SwiftUI

enum RouteSearchFilter: String, CaseIterable, Identifiable {
    case all = "Все"
    case publicRoutes = "Публичные"
    case privateRoutes = "Приватные"

    var id: Self { self }
}

struct RouteSearchView: View {
    @State private var query = ""
    @State private var filter = RouteSearchFilter.all

    private var results: [TrailRoute] {
        MockData.routes.filter { route in
            let matchesQuery = query.isEmpty || route.title.localizedCaseInsensitiveContains(query) || route.description.localizedCaseInsensitiveContains(query)
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .publicRoutes: matchesFilter = !route.isPrivate
            case .privateRoutes: matchesFilter = route.isPrivate
            }
            return matchesQuery && matchesFilter
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                Picker("Доступ", selection: $filter) {
                    ForEach(RouteSearchFilter.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                if query.isEmpty && filter == .all {
                    VStack(spacing: 12) {
                        SectionTitle(title: "Рекомендуемые", action: "Смотреть все")
                        ForEach(MockData.routes.prefix(2)) { route in
                            NavigationLink {
                                RouteDetailView(route: route)
                            } label: {
                                RouteRow(route: route)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(spacing: 12) {
                    SectionTitle(title: query.isEmpty ? "Новые маршруты" : "Результаты", action: "\(results.count)")
                    ForEach(results) { route in
                        NavigationLink {
                            RouteDetailView(route: route)
                        } label: {
                            RouteRow(route: route)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .appBackground()
        .navigationTitle("Поиск маршрутов")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Название или описание")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Фильтры", systemImage: "line.3.horizontal.decrease.circle") { }
                    .labelStyle(.iconOnly)
            }
        }
    }
}
