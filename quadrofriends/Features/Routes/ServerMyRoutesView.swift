import SwiftUI

struct ServerMyRoutesView: View {
    @EnvironmentObject private var session: APISession
    @State private var selectedTab = MyRoutesTab.recent
    @State private var routes: [ServerRoute] = []
    @State private var folders: [ServerRouteFolder] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showingNewFolder = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Picker("Маршруты", selection: $selectedTab) {
                    ForEach(MyRoutesTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                if isLoading {
                    ProgressView("Загружаем маршруты")
                        .frame(maxWidth: .infinity)
                } else if let error {
                    ContentUnavailableView {
                        Label("Не удалось загрузить маршруты", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Повторить") { Task { await load() } }
                    }
                } else {
                    ForEach(routes) { route in
                        NavigationLink {
                            ServerRouteDetailView(routeID: route.id)
                        } label: {
                            ServerRouteRow(route: route)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    Text("Мои папки").font(.title3.bold())
                    Spacer()
                    Button("Новая папка") { showingNewFolder = true }
                        .font(.subheadline)
                }
                if folders.isEmpty && !isLoading && error == nil {
                    Text("Папок пока нет")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(folders) { folder in
                    NavigationLink {
                        ServerFolderView(folder: folder)
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Color.brandOlive)
                            Text(folder.name).foregroundStyle(.primary)
                            Spacer()
                            Text("\(folder.routeCount)").foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .background(Color.surfaceCream, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .appBackground()
        .navigationTitle("Мои маршруты")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task(id: selectedTab) { await load() }
        .sheet(isPresented: $showingNewFolder) {
            ServerNewFolderView {
                await load()
            }
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            let path = selectedTab == .recent ? "users/me/recent-routes" : "users/me/routes"
            let query = selectedTab == .privateRoutes ? [URLQueryItem(name: "visibility", value: "private")] : []
            routes = try await ServerRoutesAPI.list(session.client, path: path, query: query)
            let loadedFolders: Page<ServerRouteFolder> = try await session.client.send(APIRequest(method: .get, path: "users/me/folders", query: [URLQueryItem(name: "limit", value: "100")]))
            folders = loadedFolders.items
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

private struct ServerFolderView: View {
    @EnvironmentObject private var session: APISession
    let folder: ServerRouteFolder
    @State private var routes: [ServerRoute] = []
    @State private var error: String?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if isLoading {
                    ProgressView("Загружаем папку")
                } else if let error {
                    ContentUnavailableView {
                        Label("Не удалось загрузить папку", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Повторить") { Task { await load() } }
                    }
                } else {
                    ForEach(routes) { route in
                        NavigationLink {
                            ServerRouteDetailView(routeID: route.id)
                        } label: {
                            ServerRouteRow(route: route)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .appBackground()
        .navigationTitle(folder.name)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            routes = try await ServerRoutesAPI.list(session.client, path: "users/me/folders/\(folder.id)/routes")
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

private struct ServerNewFolderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: APISession
    let onCreated: () async -> Void
    @State private var name = ""
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Название папки", text: $name)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Новая папка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") { Task { await create() } }
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func create() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let _: ServerRouteFolder = try await session.client.send(APIRequest(
                method: .post,
                path: "users/me/folders",
                body: CreateFolderRequest(name: name.trimmingCharacters(in: .whitespacesAndNewlines)),
                idempotencyKey: UUID().uuidString
            ))
            await onCreated()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct CreateFolderRequest: Encodable {
    let name: String
}
