import SwiftUI
import MapKit

enum MapDisplayStyle: String, CaseIterable, Identifiable {
    case scheme
    case satellite
    case hybrid

    var id: Self { self }

    var title: String {
        switch self {
        case .scheme: "Схема"
        case .satellite: "Спутник"
        case .hybrid: "Гибрид"
        }
    }

    var icon: String {
        switch self {
        case .scheme: "map"
        case .satellite: "globe.europe.africa.fill"
        case .hybrid: "square.3.layers.3d"
        }
    }

    var mapStyle: MapStyle {
        switch self {
        case .scheme: .standard(elevation: .realistic)
        case .satellite: .imagery(elevation: .realistic)
        case .hybrid: .hybrid(elevation: .realistic)
        }
    }
}

enum RouteTimeFilter: String, CaseIterable, Identifiable {
    case any
    case upToFourHours
    case upToEightHours
    case fullDay

    var id: Self { self }

    var title: String {
        switch self {
        case .any: "Любое"
        case .upToFourHours: "До 4 часов"
        case .upToEightHours: "До 8 часов"
        case .fullDay: "На день"
        }
    }

    func matches(_ route: TrailRoute) -> Bool {
        switch self {
        case .any: true
        case .upToFourHours: route.durationHours <= 4
        case .upToEightHours: route.durationHours <= 8
        case .fullDay: route.durationHours > 8
        }
    }
}

enum RouteRatingFilter: Double, CaseIterable, Identifiable {
    case any = 0
    case threePlus = 3
    case fourPlus = 4
    case fourAndHalfPlus = 4.5

    var id: Self { self }

    var title: String {
        switch self {
        case .any: "Любой"
        case .threePlus: "от 3,0"
        case .fourPlus: "от 4,0"
        case .fourAndHalfPlus: "от 4,5"
        }
    }

    func matches(_ rating: Double) -> Bool {
        self == .any || rating >= rawValue
    }
}

private extension TrailRoute {
    var durationHours: Int {
        if duration.localizedCaseInsensitiveContains("день") { return 12 }
        return Int(duration.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 0
    }
}
