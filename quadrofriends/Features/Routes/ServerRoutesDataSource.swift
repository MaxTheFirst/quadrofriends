import Foundation

@MainActor
enum ServerRoutesAPI {
    static func list(_ client: APIClient, path: String, query: [URLQueryItem] = [], authenticated: Bool = true) async throws -> [ServerRoute] {
        var routes: [ServerRoute] = []
        var cursor: String?
        repeat {
            let page: Page<ServerRoute> = try await client.send(APIRequest(
                method: .get,
                path: path,
                query: query + [URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "cursor", value: cursor)],
                requiresAuth: authenticated
            ))
            routes.append(contentsOf: page.items)
            cursor = page.nextCursor
        } while cursor != nil && routes.count < 500
        return routes
    }
}

@MainActor
protocol ServerRoutesDataSource {
    func list(path: String, query: [URLQueryItem]) async throws -> [ServerRoute]
    func folders() async throws -> [ServerRouteFolder]
    func createFolder(name: String) async throws
    func route(id: String) async throws -> ServerRoute
    func geometry(id: String) async throws -> ServerRouteGeometry
    func markRecent(id: String) async throws
    func setBookmarked(_ bookmarked: Bool, routeID: String) async throws
    func publishRecording(id: String, title: String, description: String, isPrivate: Bool) async throws
}

@MainActor
final class RemoteServerRoutesDataSource: ServerRoutesDataSource {
    private let session: APISession

    init(session: APISession) { self.session = session }

    func list(path: String, query: [URLQueryItem] = []) async throws -> [ServerRoute] {
        try await ServerRoutesAPI.list(session.client, path: path, query: query)
    }

    func folders() async throws -> [ServerRouteFolder] {
        let page: Page<ServerRouteFolder> = try await session.client.send(APIRequest(
            method: .get,
            path: "users/me/folders",
            query: [URLQueryItem(name: "limit", value: "100")]
        ))
        return page.items
    }

    func createFolder(name: String) async throws {
        let _: ServerRouteFolder = try await session.client.send(APIRequest(
            method: .post,
            path: "users/me/folders",
            body: CreateFolderRequest(name: name),
            idempotencyKey: UUID().uuidString
        ))
    }

    func route(id: String) async throws -> ServerRoute {
        try await session.client.send(APIRequest(method: .get, path: "routes/\(id)"))
    }

    func geometry(id: String) async throws -> ServerRouteGeometry {
        try await session.client.send(APIRequest(method: .get, path: "routes/\(id)/geometry"))
    }

    func markRecent(id: String) async throws {
        let _: EmptyResponse = try await session.client.send(APIRequest(
            method: .put, path: "users/me/recent-routes/\(id)"
        ))
    }

    func setBookmarked(_ bookmarked: Bool, routeID: String) async throws {
        if bookmarked {
            let _: ServerRouteBookmark = try await session.client.send(APIRequest(
                method: .put, path: "users/me/bookmarks/\(routeID)"
            ))
        } else {
            let _: EmptyResponse = try await session.client.send(APIRequest(
                method: .delete, path: "users/me/bookmarks/\(routeID)"
            ))
        }
    }

    func publishRecording(id: String, title: String, description: String, isPrivate: Bool) async throws {
        let _: ServerRoute = try await session.client.send(APIRequest(
            method: .post,
            path: "routes",
            body: PublishRecordingRequest(
                title: title,
                description: description,
                visibility: isPrivate ? "private" : "public",
                recordingId: id
            ),
            idempotencyKey: UUID().uuidString
        ))
    }
}

private struct CreateFolderRequest: Encodable {
    let name: String
}

private struct ServerRouteBookmark: Decodable {
    let routeId: String
}

private struct PublishRecordingRequest: Encodable {
    let title: String
    let description: String
    let visibility: String
    let recordingId: String
}
