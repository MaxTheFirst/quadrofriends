import Foundation
import CoreLocation

struct ChatPreview: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let time: String
    let unread: Int
    let avatarImage: String?
    let initials: String
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

enum ChatMessageKind {
    case text(String)
    case location(CLLocationCoordinate2D)
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let author: String
    let isMine: Bool
    let time: String
    let kind: ChatMessageKind
}
