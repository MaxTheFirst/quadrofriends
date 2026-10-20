import Foundation

// DTO разделов 7 («Временная передача геопозиции») и 9 («Чаты и сообщения») из BACKEND_API.md.

struct ChatSummaryDTO: Decodable {
    let id: String
    let kind: String
    let title: String
    let avatar: MediaDTO?
    let lastMessage: MessageDTO?
    let unreadCount: Int
    let sharesLocation: Bool
    let updatedAt: Date
}

struct MessageDTO: Decodable {
    struct RouteSummary: Decodable {
        let id: String
        let title: String
    }

    let id: String
    let chatId: String
    let sender: UserSummaryDTO
    let type: String
    let text: String?
    let media: [MediaDTO]?
    let route: RouteSummary?
    let coordinate: CoordinateDTO?
    let label: String?
    let locationShareId: String?
    let deliveryStatus: String?
    let createdAt: Date
    let deletedAt: Date?
}

/// `MessageCreateRequest`: пустые поля не кодируются.
struct MessageCreateRequest: Encodable {
    let type: String
    var text: String?
    var coordinate: CoordinateDTO?
    var label: String?

    static func text(_ text: String) -> MessageCreateRequest {
        MessageCreateRequest(type: "text", text: text)
    }

    static func location(_ coordinate: CoordinateDTO, label: String? = nil) -> MessageCreateRequest {
        MessageCreateRequest(type: "location", coordinate: coordinate, label: label)
    }
}

struct ReadStateRequest: Encodable {
    let lastReadMessageId: String
}

struct ChatReadStateDTO: Decodable {
    let chatId: String
    let userId: String
    let lastReadMessageId: String
    let readAt: Date
}

// MARK: - Геопозиция

struct LocationShareCreateRequest: Encodable {
    let chatIds: [String]
    let expiresAt: Date
}

struct LocationPositionWriteDTO: Encodable {
    let coordinate: CoordinateDTO
    let accuracyM: Double
    let recordedAt: Date
}

struct LocationPositionDTO: Decodable {
    let coordinate: CoordinateDTO
    let accuracyM: Double
    let recordedAt: Date
}

struct LocationShareDTO: Decodable {
    let id: String
    let owner: UserSummaryDTO
    let chatIds: [String]
    let status: String
    let lastPosition: LocationPositionDTO?
    let createdAt: Date
    let expiresAt: Date
}

struct VisibleLocationShareDTO: Decodable {
    let id: String
    let owner: UserSummaryDTO
    let chatIds: [String]
    let lastPosition: LocationPositionDTO
    let createdAt: Date
    let expiresAt: Date
}

// MARK: - WebSocket

struct RealtimeEvent: Decodable {
    enum Payload {
        case messageCreated(MessageDTO)
        case messageDeleted(chatID: String, messageID: String)
        case chatUpdated(ChatSummaryDTO)
        case readStateUpdated(ChatReadStateDTO)
        case locationShareUpdated(VisibleLocationShareDTO)
        case locationShareStopped(shareID: String)
        case unknown
    }

    private struct MessageReference: Decodable {
        let chatId: String
        let messageId: String
    }

    private struct ShareReference: Decodable {
        let shareId: String
    }

    private enum CodingKeys: String, CodingKey {
        case eventId, type, occurredAt, data
    }

    let eventId: String
    let type: String
    let occurredAt: Date
    let payload: Payload

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventId = try container.decode(String.self, forKey: .eventId)
        type = try container.decode(String.self, forKey: .type)
        occurredAt = try container.decode(Date.self, forKey: .occurredAt)

        switch type {
        case "chat.message.created":
            payload = .messageCreated(try container.decode(MessageDTO.self, forKey: .data))
        case "chat.message.deleted":
            let reference = try container.decode(MessageReference.self, forKey: .data)
            payload = .messageDeleted(chatID: reference.chatId, messageID: reference.messageId)
        case "chat.updated":
            payload = .chatUpdated(try container.decode(ChatSummaryDTO.self, forKey: .data))
        case "chat.read_state.updated":
            payload = .readStateUpdated(try container.decode(ChatReadStateDTO.self, forKey: .data))
        case "location.share.started", "location.position.updated":
            payload = .locationShareUpdated(try container.decode(VisibleLocationShareDTO.self, forKey: .data))
        case "location.share.stopped":
            payload = .locationShareStopped(shareID: try container.decode(ShareReference.self, forKey: .data).shareId)
        default:
            payload = .unknown
        }
    }
}
