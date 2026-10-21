import Combine
import Foundation

@MainActor
final class ServerMyRoutesViewModel: ObservableObject {
    @Published private(set) var routes: [ServerRoute] = []
    @Published private(set) var folders: [ServerRouteFolder] = []
    @Published private(set) var isLoading = true
    @Published private(set) var error: String?

    func load(tab: MyRoutesTab, from dataSource: any ServerRoutesDataSource) async {
        isLoading = true
        error = nil
        do {
            let path = tab == .recent ? "users/me/recent-routes" : "users/me/routes"
            let query = tab == .privateRoutes
                ? [URLQueryItem(name: "visibility", value: "private")]
                : []
            routes = try await dataSource.list(path: path, query: query)
            folders = try await dataSource.folders()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

@MainActor
final class ServerRoutesQueryViewModel: ObservableObject {
    @Published private(set) var routes: [ServerRoute] = []
    @Published private(set) var isLoading = true
    @Published private(set) var error: String?

    func load(path: String, query: [URLQueryItem] = [], from dataSource: any ServerRoutesDataSource) async {
        isLoading = true
        error = nil
        do {
            routes = try await dataSource.list(path: path, query: query)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func geometry(id: String, from dataSource: any ServerRoutesDataSource) async throws -> ServerRouteGeometry {
        try await dataSource.geometry(id: id)
    }
}

@MainActor
final class ServerRouteDetailViewModel: ObservableObject {
    @Published private(set) var route: ServerRoute?
    @Published private(set) var geometry: ServerRouteGeometry?
    @Published var error: String?
    @Published private(set) var isLoading = true
    @Published private(set) var isUpdatingBookmark = false

    func load(id: String, from dataSource: any ServerRoutesDataSource) async {
        error = nil
        isLoading = true
        do {
            route = try await dataSource.route(id: id)
            geometry = try await dataSource.geometry(id: id)
            try await dataSource.markRecent(id: id)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func toggleBookmark(id: String, currentlySaved: Bool, using dataSource: any ServerRoutesDataSource) async {
        isUpdatingBookmark = true
        defer { isUpdatingBookmark = false }
        do {
            try await dataSource.setBookmarked(!currentlySaved, routeID: id)
            route = try await dataSource.route(id: id)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

@MainActor
final class ServerNewFolderViewModel: ObservableObject {
    @Published private(set) var isSaving = false
    @Published private(set) var error: String?

    func create(name: String, using dataSource: any ServerRoutesDataSource) async -> Bool {
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            try await dataSource.createFolder(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

@MainActor
final class PublishRecordingViewModel: ObservableObject {
    @Published private(set) var isSaving = false
    @Published private(set) var error: String?

    func save(id: String, title: String, description: String, isPrivate: Bool,
              using dataSource: any ServerRoutesDataSource) async -> Bool {
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            try await dataSource.publishRecording(
                id: id,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                isPrivate: isPrivate
            )
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}
