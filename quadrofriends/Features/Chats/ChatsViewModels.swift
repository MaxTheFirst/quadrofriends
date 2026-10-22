import Combine
import Foundation
import UIKit

/// Операции с пользователями и создание личного чата отделены от UIKit-экрана.
@MainActor
protocol ChatPeopleDataSource {
    func searchUsers(query: String, limit: Int) async throws -> [UserSummaryDTO]
    func createChat(kind: String, participantIDs: [String], title: String?) async throws -> ChatPreview
}

@MainActor
final class RemoteChatPeopleDataSource: ChatPeopleDataSource {
    private let session: APISession

    init(session: APISession) { self.session = session }

    func searchUsers(query: String, limit: Int) async throws -> [UserSummaryDTO] {
        let normalized = query.replacingOccurrences(of: "^@", with: "", options: .regularExpression)
        let page: Page<UserSummaryDTO> = try await session.client.send(APIRequest(
            method: .get,
            path: "users",
            query: [URLQueryItem(name: "query", value: normalized), URLQueryItem(name: "limit", value: String(limit))]
        ))
        return page.items.filter { $0.id != session.currentUserID }
    }

    func createChat(kind: String, participantIDs: [String], title: String?) async throws -> ChatPreview {
        let chat: ChatSummaryDTO = try await session.client.send(APIRequest(
            method: .post,
            path: "chats",
            body: ChatCreateRequest(kind: kind, participantUserIds: participantIDs, title: title),
            idempotencyKey: UUID().uuidString
        ))
        return ChatPreview(
            id: chat.id,
            title: chat.title,
            subtitle: "Нет сообщений",
            time: "Сейчас",
            unread: chat.unreadCount,
            avatarImage: nil,
            initials: String(chat.title.prefix(2)).uppercased(),
            avatarURL: chat.avatar?.thumbnailUrl,
            sharesLocation: chat.sharesLocation
        )
    }
}

@MainActor
final class ChatsListViewModel {
    private let repository: any ChatsRepository
    private let people: (any ChatPeopleDataSource)?

    var isRemote: Bool { repository.isRemote }
    var events: AnyPublisher<ChatEvent, Never> { repository.events }

    init(repository: any ChatsRepository, people: (any ChatPeopleDataSource)? = nil) {
        self.repository = repository
        self.people = people
    }

    func chats(query: String, cursor: String?) async throws -> Page<ChatPreview> {
        try await repository.chats(query: query, cursor: cursor)
    }

    func searchUsers(query: String) async throws -> [UserSummaryDTO] {
        guard let people, !query.isEmpty else { return [] }
        return try await people.searchUsers(query: query, limit: 30)
    }

    func startDirectChat(with user: UserSummaryDTO) async throws -> ChatPreview {
        guard let people else { throw APIError.unauthorized }
        let chat = try await people.createChat(kind: "direct", participantIDs: [user.id], title: nil)
        return ChatPreview(
            id: chat.id,
            title: chat.title,
            subtitle: chat.subtitle,
            time: chat.time,
            unread: chat.unread,
            avatarImage: chat.avatarImage,
            initials: user.initials,
            avatarURL: chat.avatarURL,
            sharesLocation: chat.sharesLocation
        )
    }

    func threadViewModel() -> ChatThreadViewModel { ChatThreadViewModel(repository: repository) }
}

@MainActor
final class NewChatViewModel: ObservableObject {
    @Published private(set) var users: [UserSummaryDTO] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isCreating = false
    @Published private(set) var error: String?

    private let people: (any ChatPeopleDataSource)?

    init(people: (any ChatPeopleDataSource)?) { self.people = people }

    func search(query: String) async {
        guard let people, !query.isEmpty else {
            users = []
            error = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        error = nil
        do {
            let found = try await people.searchUsers(query: query, limit: 50)
            guard !Task.isCancelled else { return }
            users = found
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }

    func createChat(participantIDs: [String], groupTitle: String?) async -> ChatPreview? {
        guard let people else { return nil }
        isCreating = true
        error = nil
        defer { isCreating = false }
        do {
            return try await people.createChat(
                kind: groupTitle == nil ? "direct" : "group",
                participantIDs: participantIDs,
                title: groupTitle
            )
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
}

@MainActor
final class ChatThreadViewModel {
    private let repository: any ChatsRepository

    var isRemote: Bool { repository.isRemote }
    var currentUserID: String? { repository.currentUserID }
    var events: AnyPublisher<ChatEvent, Never> { repository.events }

    init(repository: any ChatsRepository) { self.repository = repository }

    func messages(chatID: String, cursor: String?) async throws -> Page<ChatMessage> {
        try await repository.messages(chatID: chatID, cursor: cursor)
    }

    func sendText(_ text: String, chatID: String, localID: String) async throws -> ChatMessage {
        try await repository.sendText(text, chatID: chatID, localID: localID)
    }

    func sendPhoto(_ image: UIImage, chatID: String, localID: String) async throws -> ChatMessage {
        try await repository.sendPhoto(image, chatID: chatID, localID: localID)
    }

    func sendRoute(_ routeID: String, chatID: String, localID: String) async throws -> ChatMessage {
        try await repository.sendRoute(routeID, chatID: chatID, localID: localID)
    }

    func shareableRoutes() async throws -> [ChatShareableRoute] {
        try await repository.shareableRoutes()
    }

    func markRead(chatID: String, messageID: String) async {
        await repository.markRead(chatID: chatID, messageID: messageID)
    }
}
