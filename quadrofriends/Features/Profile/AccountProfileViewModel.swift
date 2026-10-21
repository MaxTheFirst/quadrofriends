import Combine
import Foundation

@MainActor
protocol AccountProfileDataSource {
    func profile() async throws -> AccountProfileDTO
    func publicRoutes() async throws -> [ServerRoute]
    func signOut() async
}

@MainActor
final class RemoteAccountProfileDataSource: AccountProfileDataSource {
    private let session: APISession

    init(session: APISession) { self.session = session }

    func profile() async throws -> AccountProfileDTO {
        try await session.client.send(APIRequest(method: .get, path: "users/me"))
    }

    func publicRoutes() async throws -> [ServerRoute] {
        try await ServerRoutesAPI.list(
            session.client,
            path: "users/me/routes",
            query: [URLQueryItem(name: "visibility", value: "public")]
        )
    }

    func signOut() async { await session.signOut() }
}

@MainActor
final class AccountProfileViewModel: ObservableObject {
    @Published private(set) var account: AccountProfileDTO?
    @Published private(set) var error: String?
    @Published private(set) var publicRoutes: [ServerRoute] = []

    func load(from dataSource: any AccountProfileDataSource) async {
        error = nil
        do {
            account = try await dataSource.profile()
            publicRoutes = (try? await dataSource.publicRoutes()) ?? []
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signOut(using dataSource: any AccountProfileDataSource) async {
        await dataSource.signOut()
    }
}
