import Foundation

/// Ручки чатов, сообщений и передачи геопозиции.
@MainActor
struct ChatsAPI {
    let client: APIClient

    // MARK: - Чаты и сообщения

    func chats(query: String?, cursor: String?, limit: Int = 30) async throws -> Page<ChatSummaryDTO> {
        try await client.send(APIRequest(
            method: .get,
            path: "chats",
            query: [
                URLQueryItem(name: "query", value: query?.isEmpty == false ? query : nil),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "cursor", value: cursor)
            ]
        ))
    }

    /// История от новых сообщений к старым.
    func messages(chatID: String, cursor: String?, limit: Int = 50) async throws -> Page<MessageDTO> {
        try await client.send(APIRequest(
            method: .get,
            path: "chats/\(chatID)/messages",
            query: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "cursor", value: cursor)
            ]
        ))
    }

    func sendMessage(
        chatID: String,
        _ message: MessageCreateRequest,
        idempotencyKey: String
    ) async throws -> MessageDTO {
        try await client.send(APIRequest(
            method: .post,
            path: "chats/\(chatID)/messages",
            body: message,
            idempotencyKey: idempotencyKey
        ))
    }

    func markRead(chatID: String, messageID: String) async throws -> ChatReadStateDTO {
        try await client.send(APIRequest(
            method: .put,
            path: "chats/\(chatID)/read-state",
            body: ReadStateRequest(lastReadMessageId: messageID)
        ))
    }

    // MARK: - Геопозиция

    func createLocationShare(chatID: String, expiresAt: Date, idempotencyKey: String) async throws -> LocationShareDTO {
        try await client.send(APIRequest(
            method: .post,
            path: "location-shares",
            body: LocationShareCreateRequest(chatIds: [chatID], expiresAt: expiresAt),
            idempotencyKey: idempotencyKey
        ))
    }

    func sendPosition(shareID: String, _ position: LocationPositionWriteDTO) async throws -> LocationPositionDTO {
        try await client.send(APIRequest(
            method: .post,
            path: "location-shares/\(shareID)/positions",
            body: position,
            idempotencyKey: UUID().uuidString
        ))
    }

    func stopLocationShare(shareID: String) async throws {
        _ = try await client.send(APIRequest<EmptyResponse>(method: .delete, path: "location-shares/\(shareID)"))
    }

    func chatLocationShares(chatID: String) async throws -> Page<VisibleLocationShareDTO> {
        try await client.send(APIRequest(
            method: .get,
            path: "chats/\(chatID)/location-shares",
            query: [URLQueryItem(name: "limit", value: "100")]
        ))
    }

    /// Все активные передачи, доступные пользователю через его чаты.
    func visibleLocationShares() async throws -> Page<VisibleLocationShareDTO> {
        try await client.send(APIRequest(
            method: .get,
            path: "users/me/visible-location-shares",
            query: [URLQueryItem(name: "limit", value: "100")]
        ))
    }
}
