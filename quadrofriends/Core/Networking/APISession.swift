import Combine
import Foundation

/// Сессия backend: вход по email, хранение токенов в Keychain и ротация refresh token.
@MainActor
final class APISession: ObservableObject, AccessTokenProvider {
    private struct StoredSession: Codable {
        let id: String
        let accessToken: String
        let accessExpiresAt: Date
        let refreshToken: String
        let refreshExpiresAt: Date
        let userID: String
        let userDisplayName: String
    }

    /// Запас до истечения access token, после которого он считается устаревшим.
    private static let accessTokenLeeway: TimeInterval = 30

    @Published private(set) var isAuthorized: Bool

    let client: APIClient

    private let keychain = KeychainStore<StoredSession>(service: "quadrofriends.api", account: "session")
    private var stored: StoredSession?
    private var refreshTask: Task<StoredSession, Error>?

    var currentUserID: String? { stored?.userID }
    var currentUserDisplayName: String? { stored?.userDisplayName }

    /// Случайный ID установки для `device_id`: не рекламный идентификатор.
    let deviceID: String = {
        let key = "api.deviceID"
        if let saved = UserDefaults.standard.string(forKey: key) { return saved }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }()

    init(client: APIClient? = nil) {
        let client = client ?? APIClient()
        self.client = client
        let saved = keychain.load()
        stored = saved.flatMap { $0.refreshExpiresAt > Date() ? $0 : nil }
        isAuthorized = stored != nil
        client.tokenProvider = self
    }

    /// Вход по email и паролю.
    func signIn(email: String, password: String) async throws {
        let session = try await client.send(APIRequest<SessionDTO>(
            method: .post,
            path: "sessions",
            body: CreateSessionRequest.password(email: email, password: password, deviceID: deviceID),
            idempotencyKey: UUID().uuidString,
            requiresAuth: false
        ))
        store(session)
    }

    /// Регистрация сразу выдаёт сессию; подтверждение email не требуется.
    func register(
        email: String, password: String, firstName: String, lastName: String,
        username: String?, birthYear: Int?, city: String?
    ) async throws {
        let session = try await client.send(APIRequest<SessionDTO>(
            method: .post,
            path: "sessions",
            body: CreateSessionRequest.register(
                email: email, password: password, firstName: firstName, lastName: lastName,
                username: username, birthYear: birthYear, city: city, deviceID: deviceID
            ),
            idempotencyKey: UUID().uuidString,
            requiresAuth: false
        ))
        store(session)
    }

    /// Выход с устройства: отзыв refresh token на сервере и очистка Keychain.
    func signOut() async {
        if let stored {
            _ = try? await client.send(APIRequest<EmptyResponse>(method: .delete, path: "sessions/\(stored.id)"))
        }
        clear()
    }

    // MARK: - AccessTokenProvider

    func validAccessToken() async throws -> String {
        guard let stored else { throw APIError.unauthorized }
        if stored.accessExpiresAt.timeIntervalSinceNow > Self.accessTokenLeeway {
            return stored.accessToken
        }
        return try await refresh().accessToken
    }

    func refreshAccessToken() async throws {
        _ = try await refresh()
    }

    // MARK: - Ротация

    /// Одновременные запросы ждут одно и то же обновление: refresh token одноразовый.
    private func refresh() async throws -> StoredSession {
        if let refreshTask {
            return try await refreshTask.value
        }
        guard let current = stored else { throw APIError.unauthorized }

        let request = APIRequest<SessionDTO>(
            method: .post,
            path: "sessions",
            body: CreateSessionRequest.refresh(token: current.refreshToken, deviceID: deviceID),
            idempotencyKey: UUID().uuidString,
            requiresAuth: false
        )
        let task = Task { [client] in
            let session = try await client.send(request)
            return Self.makeStored(from: session)
        }
        refreshTask = task
        defer { refreshTask = nil }

        do {
            let renewed = try await task.value
            save(renewed)
            return renewed
        } catch let error as APIError {
            // Сетевой сбой не завершает сессию, а отказ сервера в refresh token — завершает.
            if let status = error.status, [400, 401, 403].contains(status) {
                clear()
                throw APIError.unauthorized
            }
            throw error
        }
    }

    private func store(_ session: SessionDTO) {
        save(Self.makeStored(from: session))
    }

    private func save(_ session: StoredSession) {
        stored = session
        keychain.save(session)
        isAuthorized = true
    }

    private func clear() {
        refreshTask?.cancel()
        refreshTask = nil
        stored = nil
        keychain.delete()
        isAuthorized = false
    }

    private static func makeStored(from session: SessionDTO) -> StoredSession {
        StoredSession(
            id: session.id,
            accessToken: session.accessToken,
            accessExpiresAt: session.accessExpiresAt,
            refreshToken: session.refreshToken,
            refreshExpiresAt: session.refreshExpiresAt,
            userID: session.user.id,
            userDisplayName: session.user.displayName
        )
    }
}
