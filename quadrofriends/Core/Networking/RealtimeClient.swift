import Combine
import Foundation

/// Одно WebSocket-соединение `/api/realtime` на активное приложение.
///
/// После каждого (пере)подключения публикует `connectionRestored`: подписчики перечитывают данные через REST,
/// потому что события во время разрыва могли потеряться.
@MainActor
final class RealtimeClient: ObservableObject {
    private static let maxRetryDelay: TimeInterval = 30
    private static let rememberedEventCount = 500

    @Published private(set) var isConnected = false

    let events = PassthroughSubject<RealtimeEvent, Never>()
    let connectionRestored = PassthroughSubject<Void, Never>()

    private let session: APISession
    private let urlSession: URLSession
    private let decoder = APIClient.makeDecoder()
    private var socket: URLSessionWebSocketTask?
    private var loopTask: Task<Void, Never>?
    private var seenEventIDs: [String] = []
    private var seenEventIDSet: Set<String> = []

    init(session: APISession, urlSession: URLSession = .shared) {
        self.session = session
        self.urlSession = urlSession
    }

    func start() {
        guard loopTask == nil, session.isAuthorized else { return }
        loopTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        isConnected = false
    }

    private func runLoop() async {
        var retryDelay: TimeInterval = 1

        while !Task.isCancelled {
            do {
                // Просроченный access token обновится здесь, перед новым handshake.
                let token = try await session.validAccessToken()
                var request = URLRequest(url: session.client.configuration.realtimeURL)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                let socket = urlSession.webSocketTask(with: request)
                self.socket = socket
                socket.resume()
                try await Self.ping(socket)

                retryDelay = 1
                isConnected = true
                connectionRestored.send()

                while !Task.isCancelled {
                    let message = try await socket.receive()
                    handle(message)
                }
            } catch APIError.unauthorized {
                break
            } catch {
                isConnected = false
                socket?.cancel(with: .abnormalClosure, reason: nil)
                socket = nil
                guard !Task.isCancelled else { break }
                try? await Task.sleep(for: .seconds(retryDelay))
                retryDelay = min(retryDelay * 2, Self.maxRetryDelay)
            }
        }

        // После stop() задача уже снята; иначе (сессия завершена) освобождаем место для нового start().
        if !Task.isCancelled {
            isConnected = false
            loopTask = nil
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let text):
            data = Data(text.utf8)
        case .data(let payload):
            data = payload
        @unknown default:
            return
        }

        guard let event = try? decoder.decode(RealtimeEvent.self, from: data),
              rememberEvent(event.eventId) else { return }
        events.send(event)
    }

    /// События могут прийти повторно: пропускаем уже обработанные `event_id`.
    private func rememberEvent(_ id: String) -> Bool {
        guard seenEventIDSet.insert(id).inserted else { return false }
        seenEventIDs.append(id)
        if seenEventIDs.count > Self.rememberedEventCount {
            seenEventIDSet.remove(seenEventIDs.removeFirst())
        }
        return true
    }

    /// Первый ping подтверждает, что handshake прошёл и токен принят.
    private static func ping(_ socket: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            socket.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
