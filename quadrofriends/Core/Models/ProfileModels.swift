import Foundation

struct Vehicle: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var model: String
    var year: Int
    var imageName: String
    var isPrimary: Bool
}

struct UserProfile: Codable, Equatable {
    var firstName: String
    var lastName: String
    var username: String
    var birthYear: Int
    var city: String
    var vehicles: [Vehicle]

    static let sample = UserProfile(
        firstName: "Иван",
        lastName: "Петров",
        username: "ivan_atv",
        birthYear: 1995,
        city: "Санкт-Петербург",
        vehicles: [
            Vehicle(model: "Yamaha Grizzly 700", year: 2019, imageName: "RouteForest", isPrimary: true),
            Vehicle(model: "Polaris Sportsman 570", year: 2021, imageName: "RouteMountain", isPrimary: false)
        ]
    )
}
