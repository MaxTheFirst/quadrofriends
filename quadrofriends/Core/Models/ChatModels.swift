import Foundation
import CoreLocation
import UIKit

struct ChatPreview: Identifiable, Equatable, Codable {
    let id: String
    var title: String
    var subtitle: String
    var time: String
    var unread: Int
    var avatarImage: String?
    var initials: String
    var avatarURL: URL? = nil
    var sharesLocation = false
}

struct ChatLiveLocation: Identifiable {
    let id: String
    let chatID: String
    let userID: String
    let name: String
    let initials: String
    let avatarImage: String?
    var coordinate: CLLocationCoordinate2D
    var updatedAt: Date
    let expiresAt: Date
    let isMine: Bool
    let isDemo: Bool
}

enum ChatMessageKind: Equatable {
    case text(String)
    case photo(URL?, UIImage?, String?)
    case location(CLLocationCoordinate2D)

    static func == (lhs: ChatMessageKind, rhs: ChatMessageKind) -> Bool {
        switch (lhs, rhs) {
        case let (.text(left), .text(right)):
            return left == right
        case let (.photo(leftURL, leftImage, leftCaption), .photo(rightURL, rightImage, rightCaption)):
            return leftURL == rightURL && leftImage === rightImage && leftCaption == rightCaption
        case let (.location(left), .location(right)):
            return left.latitude == right.latitude && left.longitude == right.longitude
        default:
            return false
        }
    }
}

struct ChatMessage: Identifiable, Equatable {
    /// Статус своего сообщения.
    enum DeliveryStatus: Equatable {
        case sending
        case sent
        case read
        case failed
    }

    /// Серверный ID или, пока сообщение не отправлено, локальный `Idempotency-Key`.
    let id: String
    let author: String
    let isMine: Bool
    let sentAt: Date
    var kind: ChatMessageKind
    var status: DeliveryStatus?

    init(
        id: String = UUID().uuidString,
        author: String,
        isMine: Bool,
        sentAt: Date,
        kind: ChatMessageKind,
        status: DeliveryStatus? = nil
    ) {
        self.id = id
        self.author = author
        self.isMine = isMine
        self.sentAt = sentAt
        self.kind = kind
        self.status = status
    }

    var time: String {
        sentAt.formatted(date: .omitted, time: .shortened)
    }
}
