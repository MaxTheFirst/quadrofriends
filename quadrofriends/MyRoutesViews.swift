import SwiftUI

enum MyRoutesTab: String, CaseIterable, Identifiable {
    case recent = "Недавние"
    case privateRoutes = "Приватные"

    var id: Self { self }
}

struct MyRoutesView: View {
    @State private var selectedTab = MyRoutesTab.recent
    @State private var showingFolderEditor = false
    @State private var showingRouteEditor = false

    private var visibleRoutes: [TrailRoute] {
        selectedTab == .recent ? MockData.routes : MockData.routes.filter(\.isPrivate)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                Picker("Маршруты", selection: $selectedTab) {
                    ForEach(MyRoutesTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                VStack(spacing: 10) {
                    ForEach(visibleRoutes) { route in
                        NavigationLink {
                            RouteDetailView(route: route)
                        } label: {
                            RouteRow(route: route)
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(spacing: 10) {
                    SectionTitle(title: "Мои папки")
                    ForEach(MockData.folders) { folder in
                        Button { } label: {
                            HStack(spacing: 12) {
                                Image(systemName: folder.icon)
                                    .foregroundStyle(Color.brandOlive)
                                    .frame(width: 34, height: 34)
                                    .background(Color.brandOlive.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(folder.name)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)
                                    Text("\(folder.count) маршрутов")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(12)
                            .background(Color.surfaceCream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .appBackground()
        .navigationTitle("Мои маршруты")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Новая папка", systemImage: "folder.badge.plus") {
                    showingFolderEditor = true
                }
                .labelStyle(.iconOnly)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Новый маршрут", systemImage: "plus") {
                    showingRouteEditor = true
                }
                .labelStyle(.iconOnly)
            }
        }
        .sheet(isPresented: $showingFolderEditor) {
            NavigationStack {
                NewFolderView()
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingRouteEditor) {
            NavigationStack {
                RouteEditorView(title: "Новый маршрут")
            }
        }
    }
}

private struct NewFolderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        Form {
            Section("Название") {
                TextField("Например, Карелия", text: $name)
            }
            Section {
                Label("Маршруты можно будет добавлять в папку из меню карточки.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Новая папка")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Создать", systemImage: "checkmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
