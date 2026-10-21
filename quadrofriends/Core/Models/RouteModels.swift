import Foundation

struct TrailRoute: Identifiable {
    let id: String
    let title: String
    let imageName: String
    let distance: Int
    let duration: String
    let rating: Double
    let reviewCount: Int
    let completedCount: Int
    let ratings: RouteRatings
    let isPrivate: Bool
    let description: String
    let tags: [String]
    let author: RouteAuthor
}

struct RouteAuthor {
    let id: String
    let name: String
    let username: String
    let birthYear: Int
    let city: String
    let avatarImage: String?
    let initials: String
    let vehicles: [Vehicle]
}

struct RouteRatings {
    let difficulty: Double
    let mud: Double
    let fields: Double
    let forest: Double
    let scenery: Double
}

struct RouteFolder: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
    let icon: String
}
