import Combine
import Foundation
import UIKit

/// Изменения, которые экраны чатов применяют без полной перезагрузки.
enum ChatEvent {
    case messageCreated(ChatMessage, chatID: String)
    case messageDeleted(chatID: String, messageID: String)
    case chatUpdated(ChatPreview)
    case readStateUpdated(chatID: String, userID: String, lastReadMessageID: String)
    /// Соединение восстановлено: часть событий могла потеряться, данные нужно перечитать.
    case resync
}

struct ChatShareableRoute {
    let id: String
    let title: String
}

/// Источник данных экранов чатов: сервер или демонстрационные данные.
@MainActor
protocol ChatsRepository: AnyObject {
    /// Данные приходят по сети: экраны показывают загрузку и ошибки.
    var isRemote: Bool { get }
    /// ID текущего пользователя на сервере; в демо-режиме `nil`.
    var currentUserID: String? { get }
    var events: AnyPublisher<ChatEvent, Never> { get }

    func chats(query: String, cursor: String?) async throws -> Page<ChatPreview>
    /// Сообщения от новых к старым.
    func messages(chatID: String, cursor: String?) async throws -> Page<ChatMessage>
    /// `localID` используется как `Idempotency-Key`: повтор не создаст второе сообщение.
    func sendText(_ text: String, chatID: String, localID: String) async throws -> ChatMessage
    func sendPhoto(_ image: UIImage, chatID: String, localID: String) async throws -> ChatMessage
    func sendRoute(_ routeID: String, chatID: String, localID: String) async throws -> ChatMessage
    func shareableRoutes() async throws -> [ChatShareableRoute]
    func markRead(chatID: String, messageID: String) async
}

// MARK: - Сервер

@MainActor
final class RemoteChatsRepository: ChatsRepository {
    private let api: ChatsAPI
    private let session: APISession
    private let realtime: RealtimeClient

    let isRemote = true

    var currentUserID: String? { session.currentUserID }

    init(session: APISession, realtime: RealtimeClient) {
        self.api = ChatsAPI(client: session.client)
        self.session = session
        self.realtime = realtime
    }

    var events: AnyPublisher<ChatEvent, Never> {
        let realtimeEvents = realtime.events.compactMap { [weak self] event -> ChatEvent? in
            self?.chatEvent(from: event)
        }
        let resync = realtime.connectionRestored.map { ChatEvent.resync }
        return realtimeEvents.merge(with: resync).eraseToAnyPublisher()
    }

    func chats(query: String, cursor: String?) async throws -> Page<ChatPreview> {
        let page = try await api.chats(query: query, cursor: cursor)
        return Page(items: page.items.map(preview(from:)), nextCursor: page.nextCursor)
    }

    func messages(chatID: String, cursor: String?) async throws -> Page<ChatMessage> {
        let page = try await api.messages(chatID: chatID, cursor: cursor)
        return Page(items: page.items.map(message(from:)), nextCursor: page.nextCursor)
    }

    func sendText(_ text: String, chatID: String, localID: String) async throws -> ChatMessage {
        let dto = try await api.sendMessage(chatID: chatID, .text(text), idempotencyKey: localID)
        return message(from: dto)
    }

    func sendPhoto(_ image: UIImage, chatID: String, localID: String) async throws -> ChatMessage {
        let media = try await session.client.uploadImage(image)
        let dto = try await api.sendMessage(chatID: chatID, .photo(media.id), idempotencyKey: localID)
        return message(from: dto)
    }

    func sendRoute(_ routeID: String, chatID: String, localID: String) async throws -> ChatMessage {
        let dto = try await api.sendMessage(chatID: chatID, .route(routeID), idempotencyKey: localID)
        return message(from: dto)
    }

    func shareableRoutes() async throws -> [ChatShareableRoute] {
        let routes = try await ServerRoutesAPI.list(
            session.client, path: "users/me/routes",
            query: [URLQueryItem(name: "visibility", value: "public")]
        )
        return routes.map { ChatShareableRoute(id: $0.id, title: $0.title) }
    }

    func markRead(chatID: String, messageID: String) async {
        _ = try? await api.markRead(chatID: chatID, messageID: messageID)
    }

    // MARK: - Преобразование DTO

    private func chatEvent(from event: RealtimeEvent) -> ChatEvent? {
        switch event.payload {
        case .messageCreated(let dto):
            return .messageCreated(message(from: dto), chatID: dto.chatId)
        case .messageDeleted(let chatID, let messageID):
            return .messageDeleted(chatID: chatID, messageID: messageID)
        case .chatUpdated(let dto):
            return .chatUpdated(preview(from: dto))
        case .readStateUpdated(let dto):
            return .readStateUpdated(chatID: dto.chatId, userID: dto.userId, lastReadMessageID: dto.lastReadMessageId)
        case .locationShareUpdated, .locationShareStopped, .unknown:
            return nil
        }
    }

    private func preview(from dto: ChatSummaryDTO) -> ChatPreview {
        ChatPreview(
            id: dto.id,
            title: dto.title,
            subtitle: dto.lastMessage.map { subtitle(for: $0, in: dto) } ?? "Нет сообщений",
            time: ChatDateFormatting.listTime(dto.lastMessage?.createdAt ?? dto.updatedAt),
            unread: dto.unreadCount,
            avatarImage: nil,
            initials: Self.initials(from: dto.title),
            avatarURL: dto.avatar?.thumbnailUrl,
            sharesLocation: dto.sharesLocation
        )
    }

    private func subtitle(for message: MessageDTO, in chat: ChatSummaryDTO) -> String {
        let text = Self.previewText(for: message)
        if message.sender.id == session.currentUserID {
            return "Вы: \(text)"
        }
        if chat.kind == "group", let firstName = message.sender.displayName.split(separator: " ").first {
            return "\(firstName): \(text)"
        }
        return text
    }

    private func message(from dto: MessageDTO) -> ChatMessage {
        let isMine = dto.sender.id == session.currentUserID
        return ChatMessage(
            id: dto.id,
            author: isMine ? "Вы" : dto.sender.displayName,
            isMine: isMine,
            sentAt: dto.createdAt,
            kind: Self.kind(for: dto),
            status: isMine ? (dto.deliveryStatus == "read" ? .read : .sent) : nil
        )
    }

    private static func kind(for dto: MessageDTO) -> ChatMessageKind {
        if dto.type == "photo", dto.deletedAt == nil {
            return .photo(dto.media?.first?.url, nil, dto.text)
        }
        if dto.type == "location", dto.deletedAt == nil, let coordinate = dto.coordinate {
            return .location(coordinate.coordinate)
        }
        return .text(previewText(for: dto))
    }

    /// Текст для пузыря и последнего сообщения в списке. Фото, голос и маршрут пока показываются подписью.
    private static func previewText(for dto: MessageDTO) -> String {
        if dto.deletedAt != nil { return "Сообщение удалено" }
        let caption = dto.text.flatMap { $0.isEmpty ? nil : $0 }

        switch dto.type {
        case "text":
            return caption ?? ""
        case "photo":
            return ["Фото", caption].compactMap { $0 }.joined(separator: ": ")
        case "voice":
            return "Голосовое сообщение"
        case "route":
            let title = dto.route.map { "Маршрут «\($0.title)»" } ?? "Маршрут"
            return [title, caption].compactMap { $0 }.joined(separator: ": ")
        case "location":
            return dto.label ?? caption ?? "Геопозиция"
        case "live_location":
            return ["Трансляция геопозиции", caption].compactMap { $0 }.joined(separator: ": ")
        default:
            return caption ?? "Сообщение не поддерживается"
        }
    }

    private static func initials(from title: String) -> String {
        let letters = title
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first(where: \.isLetter) }
        return String(letters).uppercased()
    }
}

// MARK: - Демо

@MainActor
final class DemoChatsRepository: ChatsRepository {
    let isRemote = false
    let currentUserID: String? = nil
    private let dataSource: any DemoChatsDataSource & DemoRoutesDataSource

    init(dataSource: (any DemoChatsDataSource & DemoRoutesDataSource)? = nil) {
        self.dataSource = dataSource ?? DemoRepository.shared
    }

    var events: AnyPublisher<ChatEvent, Never> {
        Empty().eraseToAnyPublisher()
    }

    func chats(query: String, cursor: String?) async throws -> Page<ChatPreview> {
        let storedChats = dataSource.chats()
        let chats = query.isEmpty ? storedChats : storedChats.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.subtitle.localizedCaseInsensitiveContains(query)
        }
        return Page(items: chats, nextCursor: nil)
    }

    func messages(chatID: String, cursor: String?) async throws -> Page<ChatMessage> {
        Page(items: dataSource.messages(in: chatID).reversed(), nextCursor: nil)
    }

    func sendText(_ text: String, chatID: String, localID: String) async throws -> ChatMessage {
        try await Task.sleep(for: .milliseconds(300))
        let message = ChatMessage(id: localID, author: "Вы", isMine: true, sentAt: Date(), kind: .text(text), status: .sent)
        dataSource.appendMessage(message, in: chatID)
        return message
    }

    func sendPhoto(_ image: UIImage, chatID: String, localID: String) async throws -> ChatMessage {
        let message = ChatMessage(id: localID, author: "Вы", isMine: true, sentAt: Date(), kind: .photo(nil, image, nil), status: .sent)
        dataSource.appendMessage(message, in: chatID)
        return message
    }

    func sendRoute(_ routeID: String, chatID: String, localID: String) async throws -> ChatMessage {
        let message = ChatMessage(id: localID, author: "Вы", isMine: true, sentAt: Date(), kind: .text("Маршрут"), status: .sent)
        dataSource.appendMessage(message, in: chatID)
        return message
    }

    func shareableRoutes() async throws -> [ChatShareableRoute] {
        dataSource.routes().filter { !$0.isPrivate }.map { ChatShareableRoute(id: $0.id, title: $0.title) }
    }

    func markRead(chatID: String, messageID: String) async { }
}

// MARK: - Даты

enum ChatDateFormatting {
    /// Время в списке чатов: «09:15», «Вчера», «пн», «18.10.26».
    static func listTime(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) {
            return "Вчера"
        }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day,
           days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated)).capitalized
        }
        return date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year(.twoDigits))
    }

    /// Заголовок дня в переписке: «Сегодня», «Вчера», «18 октября».
    static func dayTitle(_ day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return "Сегодня" }
        if calendar.isDateInYesterday(day) { return "Вчера" }
        if calendar.isDate(day, equalTo: Date(), toGranularity: .year) {
            return day.formatted(.dateTime.day().month(.wide))
        }
        return day.formatted(.dateTime.day().month(.wide).year())
    }
}
