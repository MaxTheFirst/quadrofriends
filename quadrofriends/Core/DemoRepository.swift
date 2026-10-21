import CoreLocation
import Foundation
import SwiftData
import UIKit

/// Локальная запись демоданных. Примеры из MockData нужны только при первом запуске.
@Model
final class DemoRecord {
    @Attribute(.unique) var key: String
    var kind: String
    var sortOrder: Int
    var payload: Data

    init(key: String, kind: String, sortOrder: Int, payload: Data) {
        self.key = key
        self.kind = kind
        self.sortOrder = sortOrder
        self.payload = payload
    }
}

private struct DemoMessageSnapshot: Codable {
    let chatID: String
    let id: String
    let author: String
    let isMine: Bool
    let sentAt: Date
    let kind: String
    let text: String?
    let imageURL: URL?
    let imageData: Data?
    let caption: String?
    let latitude: Double?
    let longitude: Double?
    let status: String?

    init(chatID: String, message: ChatMessage) {
        self.chatID = chatID
        id = message.id
        author = message.author
        isMine = message.isMine
        sentAt = message.sentAt

        switch message.kind {
        case .text(let value):
            kind = "text"
            text = value
            imageURL = nil
            imageData = nil
            caption = nil
            latitude = nil
            longitude = nil
        case .photo(let url, let image, let value):
            kind = "photo"
            text = nil
            imageURL = url
            imageData = image?.jpegData(compressionQuality: 0.85)
            caption = value
            latitude = nil
            longitude = nil
        case .location(let coordinate):
            kind = "location"
            text = nil
            imageURL = nil
            imageData = nil
            caption = nil
            latitude = coordinate.latitude
            longitude = coordinate.longitude
        }

        switch message.status {
        case .sending: status = "sending"
        case .sent: status = "sent"
        case .read: status = "read"
        case .failed: status = "failed"
        case nil: status = nil
        }
    }

    var message: ChatMessage {
        let content: ChatMessageKind
        switch kind {
        case "photo":
            content = .photo(imageURL, imageData.flatMap(UIImage.init(data:)), caption)
        case "location":
            content = .location(CLLocationCoordinate2D(latitude: latitude ?? 0, longitude: longitude ?? 0))
        default:
            content = .text(text ?? "")
        }

        let deliveryStatus: ChatMessage.DeliveryStatus?
        switch status {
        case "sending": deliveryStatus = .sending
        case "sent": deliveryStatus = .sent
        case "read": deliveryStatus = .read
        case "failed": deliveryStatus = .failed
        default: deliveryStatus = nil
        }

        return ChatMessage(
            id: id, author: author, isMine: isMine, sentAt: sentAt,
            kind: content, status: deliveryStatus
        )
    }
}

/// Контракты доступа к демоданным. ViewModel зависит от нужного ей контракта,
/// а не от реализации SwiftData.
@MainActor
protocol DemoRoutesDataSource {
    func routes() -> [TrailRoute]
    func folders() -> [RouteFolder]
}

@MainActor
protocol DemoProfileDataSource {
    func profile() -> UserProfile
    func saveProfile(_ profile: UserProfile)
}

@MainActor
protocol DemoChatsDataSource {
    func chats() -> [ChatPreview]
    func messages(in chatID: String) -> [ChatMessage]
    func appendMessage(_ message: ChatMessage, in chatID: String)
}

/// Единая точка чтения и записи демоданных в SwiftData.
@MainActor
final class DemoRepository: DemoRoutesDataSource, DemoProfileDataSource, DemoChatsDataSource {
    static let shared = DemoRepository()

    private let container: ModelContainer
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        do {
            container = try ModelContainer(for: DemoRecord.self)
            context = container.mainContext
            if try context.fetch(FetchDescriptor<DemoRecord>()).isEmpty {
                try seed()
            }
        } catch {
            fatalError("Не удалось открыть демоданные SwiftData: \(error)")
        }
    }

    func routes() -> [TrailRoute] { read(kind: "route") }
    func folders() -> [RouteFolder] { read(kind: "folder") }
    func chats() -> [ChatPreview] { read(kind: "chat") }

    func messages(in chatID: String) -> [ChatMessage] {
        let snapshots: [DemoMessageSnapshot] = read(kind: "message")
        return snapshots.filter { $0.chatID == chatID }.map(\.message)
    }

    func profile() -> UserProfile {
        let profiles: [UserProfile] = read(kind: "profile")
        guard let profile = profiles.first else {
            fatalError("Демопрофиль отсутствует в SwiftData")
        }
        return profile
    }

    func saveProfile(_ profile: UserProfile) {
        do {
            let payload = try encoder.encode(profile)
            if let record = try context.fetch(FetchDescriptor<DemoRecord>()).first(where: { $0.key == "profile:me" }) {
                record.payload = payload
            } else {
                context.insert(DemoRecord(key: "profile:me", kind: "profile", sortOrder: 0, payload: payload))
            }
            try context.save()
        } catch {
            assertionFailure("Не удалось сохранить демопрофиль: \(error)")
        }
    }

    func appendMessage(_ message: ChatMessage, in chatID: String) {
        do {
            let records = try context.fetch(FetchDescriptor<DemoRecord>())
            let prefix = "message:\(chatID):"
            let order = records.filter { $0.key.hasPrefix(prefix) }.count
            let snapshot = DemoMessageSnapshot(chatID: chatID, message: message)
            let payload = try encoder.encode(snapshot)
            context.insert(DemoRecord(key: prefix + message.id, kind: "message", sortOrder: order, payload: payload))
            try context.save()
        } catch {
            assertionFailure("Не удалось сохранить демосообщение: \(error)")
        }
    }

    private func read<Value: Decodable>(kind: String) -> [Value] {
        guard let records = try? context.fetch(FetchDescriptor<DemoRecord>()) else { return [] }
        return records
            .filter { $0.kind == kind }
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { try? decoder.decode(Value.self, from: $0.payload) }
    }

    private func seed() throws {
        for (index, route) in MockData.routes.enumerated() {
            try insert(route, key: "route:\(route.id)", kind: "route", order: index)
        }
        for (index, folder) in MockData.folders.enumerated() {
            try insert(folder, key: "folder:\(folder.id)", kind: "folder", order: index)
        }
        for (index, chat) in MockData.chats.enumerated() {
            try insert(chat, key: "chat:\(chat.id)", kind: "chat", order: index)
            for (messageIndex, message) in MockData.chatMessages.enumerated() {
                let snapshot = DemoMessageSnapshot(chatID: chat.id, message: message)
                try insert(snapshot, key: "message:\(chat.id):\(messageIndex)", kind: "message", order: messageIndex)
            }
        }

        // Сохраняем профиль пользователя, созданный до перехода с UserDefaults на SwiftData.
        let previous = UserDefaults.standard.data(forKey: "ownProfile.v1")
            .flatMap { try? decoder.decode(UserProfile.self, from: $0) }
        try insert(previous ?? .sample, key: "profile:me", kind: "profile", order: 0)
        try context.save()
    }

    private func insert<Value: Encodable>(_ value: Value, key: String, kind: String, order: Int) throws {
        context.insert(DemoRecord(key: key, kind: kind, sortOrder: order, payload: try encoder.encode(value)))
    }
}
