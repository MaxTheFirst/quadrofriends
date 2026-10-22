import SwiftUI

struct RouteSearchView: View {
    @StateObject private var viewModel = DemoRoutesViewModel()
    @State private var query = ""
    @State private var filter = RouteSearchFilter.all

    private var results: [TrailRoute] { viewModel.search(query: query, filter: filter) }

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
                        ForEach(viewModel.recommendedRoutes) { route in
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
