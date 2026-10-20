import CoreLocation
import Foundation

// Общие DTO из BACKEND_API.md. Имена полей в camelCase: JSON-кодеки клиента переводят их в snake_case.

/// Страница списка: `{ "items": [...], "next_cursor": string | null }`.
struct Page<Item> {
    var items: [Item]
    var nextCursor: String?
}

extension Page: Decodable where Item: Decodable { }

/// Ответ без тела (`204 No Content`).
struct EmptyResponse: Decodable { }

struct CoordinateDTO: Codable, Equatable {
    let lat: Double
    let lon: Double

    init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(lat: coordinate.latitude, lon: coordinate.longitude)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

struct MediaDTO: Decodable {
    let id: String
    let mimeType: String
    let width: Int
    let height: Int
    let url: URL
    let thumbnailUrl: URL
}

struct UserSummaryDTO: Decodable {
    let id: String
    let username: String
    let displayName: String
    let avatar: MediaDTO?
    let city: String?

    var initials: String {
        let letters = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        return letters.isEmpty ? String(username.prefix(1)).uppercased() : String(letters).uppercased()
    }
}

// MARK: - Сессия

struct CreateSessionRequest: Encodable {
    let grantType: String
    var providerAccessToken: String?
    var refreshToken: String?
    var deviceId: String?

    static func vk(accessToken: String, deviceID: String) -> CreateSessionRequest {
        CreateSessionRequest(grantType: "vk", providerAccessToken: accessToken, deviceId: deviceID)
    }

    static func refresh(token: String, deviceID: String) -> CreateSessionRequest {
        CreateSessionRequest(grantType: "refresh", refreshToken: token, deviceId: deviceID)
    }
}

struct SessionDTO: Decodable {
    let id: String
    let accessToken: String
    let accessExpiresAt: Date
    let refreshToken: String
    let refreshExpiresAt: Date
    let user: UserSummaryDTO
    let isNewUser: Bool
}
