import SwiftUI

struct ServerMyRoutesView: View {
    @EnvironmentObject private var session: APISession
    @StateObject private var viewModel = ServerMyRoutesViewModel()
    @State private var selectedTab = MyRoutesTab.recent
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

                if viewModel.isLoading {
                    ProgressView("Загружаем маршруты")
                        .frame(maxWidth: .infinity)
                } else if let error = viewModel.error {
                    ContentUnavailableView {
                        Label("Не удалось загрузить маршруты", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Повторить") { Task { await load() } }
                    }
                } else {
                    ForEach(viewModel.routes) { route in
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
                if viewModel.folders.isEmpty && !viewModel.isLoading && viewModel.error == nil {
                    Text("Папок пока нет")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(viewModel.folders) { folder in
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
        await viewModel.load(tab: selectedTab, from: RemoteServerRoutesDataSource(session: session))
    }
}

private struct ServerFolderView: View {
    @EnvironmentObject private var session: APISession
    let folder: ServerRouteFolder
    @StateObject private var viewModel = ServerRoutesQueryViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if viewModel.isLoading {
                    ProgressView("Загружаем папку")
                } else if let error = viewModel.error {
                    ContentUnavailableView {
                        Label("Не удалось загрузить папку", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Повторить") { Task { await load() } }
                    }
                } else {
                    ForEach(viewModel.routes) { route in
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
        await viewModel.load(
            path: "users/me/folders/\(folder.id)/routes",
            from: RemoteServerRoutesDataSource(session: session)
        )
    }
}

private struct ServerNewFolderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: APISession
    let onCreated: () async -> Void
    @StateObject private var viewModel = ServerNewFolderViewModel()
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Название папки", text: $name)
                if let error = viewModel.error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Новая папка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") { Task { await create() } }
                        .disabled(viewModel.isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func create() async {
        if await viewModel.create(name: name, using: RemoteServerRoutesDataSource(session: session)) {
            await onCreated()
            dismiss()
        }
    }
}
