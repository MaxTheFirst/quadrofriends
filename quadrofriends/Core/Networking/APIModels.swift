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
    let email: String?
    let password: String?
    let firstName: String?
    let lastName: String?
    let username: String?
    let birthYear: Int?
    let city: String?
    let refreshToken: String?
    let deviceId: String

    static func register(
        email: String, password: String, firstName: String, lastName: String,
        username: String?, birthYear: Int?, city: String?, deviceID: String
    ) -> CreateSessionRequest {
        CreateSessionRequest(
            grantType: "register", email: email, password: password,
            firstName: firstName, lastName: lastName, username: username,
            birthYear: birthYear, city: city, refreshToken: nil, deviceId: deviceID
        )
    }

    static func password(email: String, password: String, deviceID: String) -> CreateSessionRequest {
        CreateSessionRequest(
            grantType: "password", email: email, password: password,
            firstName: nil, lastName: nil, username: nil, birthYear: nil,
            city: nil, refreshToken: nil, deviceId: deviceID
        )
    }

    static func refresh(token: String, deviceID: String) -> CreateSessionRequest {
        CreateSessionRequest(
            grantType: "refresh", email: nil, password: nil,
            firstName: nil, lastName: nil, username: nil, birthYear: nil,
            city: nil, refreshToken: token, deviceId: deviceID
        )
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

struct AccountProfileDTO: Decodable {
    struct Stats: Decodable {
        let routeCount: Int
        let followerCount: Int
        let followingCount: Int
    }

    let id: String
    let email: String?
    let firstName: String
    let lastName: String
    let username: String
    let birthYear: Int?
    let city: String?
    let avatar: MediaDTO?
    let vehicles: [AccountVehicleDTO]
    let stats: Stats
}

struct AccountVehicleDTO: Decodable, Identifiable {
    let id: String
    let model: String
    let year: Int
    let isPrimary: Bool
    let image: MediaDTO?
}
