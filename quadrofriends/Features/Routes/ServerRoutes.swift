import CoreLocation
import Foundation
import MapKit
import SwiftUI

// Models for the live route API. Demo route models remain confined to demo screens.
struct ServerRoute: Decodable, Identifiable {
    struct Ratings: Decodable {
        let difficulty: Double?
        let mud: Double?
        let fields: Double?
        let forest: Double?
        let scenery: Double?
    }

    let id: String
    let title: String
    let cover: MediaDTO?
    let distanceM: Double
    let durationS: Int
    let rating: Double?
    let reviewCount: Int
    let completedCount: Int
    let ratings: Ratings
    let visibility: String
    let tags: [String]
    let author: UserSummaryDTO
    let startPoint: CoordinateDTO
    let isBookmarked: Bool
    let description: String?
    let markerCount: Int?

    var coordinate: CLLocationCoordinate2D { startPoint.coordinate }
    var distanceText: String { (distanceM / 1_000).formatted(.number.precision(.fractionLength(1))) + " км" }
    var durationText: String {
        if durationS >= 3_600 { return "\(durationS / 3_600) ч \((durationS % 3_600) / 60) мин" }
        return "\(durationS / 60) мин"
    }
}

struct ServerRouteGeometry: Decodable {
    let points: [CoordinateDTO]
    var coordinates: [CLLocationCoordinate2D] { points.map(\.coordinate) }
}

struct ServerRouteFolder: Decodable, Identifiable {
    let id: String
    let name: String
    let routeCount: Int
}

@MainActor
enum ServerRoutesAPI {
    static func list(_ client: APIClient, path: String, query: [URLQueryItem] = [], authenticated: Bool = true) async throws -> [ServerRoute] {
        var routes: [ServerRoute] = []
        var cursor: String?
        repeat {
            let page: Page<ServerRoute> = try await client.send(APIRequest(
                method: .get,
                path: path,
                query: query + [URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "cursor", value: cursor)],
                requiresAuth: authenticated
            ))
            routes.append(contentsOf: page.items)
            cursor = page.nextCursor
        } while cursor != nil && routes.count < 500
        return routes
    }
}

struct ServerRouteRow: View {
    let route: ServerRoute

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.title3)
                .foregroundStyle(Color.brandOlive)
                .frame(width: 52, height: 52)
                .background(Color.brandOlive.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(route.title).font(.headline).foregroundStyle(.primary)
                Text("\(route.distanceText) · \(route.durationText)")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(route.author.displayName)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color.surfaceCream, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ServerRouteDetailView: View {
    @EnvironmentObject private var session: APISession
    let routeID: String
    @State private var route: ServerRoute?
    @State private var geometry: ServerRouteGeometry?
    @State private var error: String?
    @State private var isLoading = true
    @State private var isUpdatingBookmark = false

    var body: some View {
        Group {
            if let route {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(route.title).font(.title2.bold())
                        Label(route.author.displayName, systemImage: "person.crop.circle")
                        HStack {
                            Label(route.distanceText, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            Label(route.durationText, systemImage: "clock")
                        }
                        .font(.subheadline)
                        if let rating = route.rating {
                            Label("\(rating.formatted(.number.precision(.fractionLength(1)))) · \(route.reviewCount) отзывов", systemImage: "star.fill")
                                .foregroundStyle(Color.brandOrange)
                        }
                        if let description = route.description, !description.isEmpty {
                            Text(description)
                        }
                        if !route.tags.isEmpty {
                            Text(route.tags.joined(separator: " · "))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let geometry, geometry.coordinates.count > 1 {
                            Map {
                                MapPolyline(coordinates: geometry.coordinates)
                                    .stroke(Color.brandOrange, lineWidth: 5)
                            }
                            .frame(height: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .padding()
                }
            } else if let error {
                ContentUnavailableView {
                    Label("Не удалось загрузить маршрут", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Повторить") { Task { await load() } }
                }
            } else if isLoading {
                ProgressView("Загружаем маршрут")
            }
        }
        .appBackground()
        .navigationTitle("Маршрут")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let route {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await toggleBookmark(currentlySaved: route.isBookmarked) }
                    } label: {
                        Image(systemName: route.isBookmarked ? "bookmark.fill" : "bookmark")
                    }
                    .disabled(isUpdatingBookmark)
                }
            }
        }
        .task(id: routeID) { await load() }
        .alert("Ошибка", isPresented: Binding(get: { error != nil && route != nil }, set: { if !$0 { error = nil } })) {
            Button("ОК", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func load() async {
        error = nil
        isLoading = true
        do {
            route = try await session.client.send(APIRequest(method: .get, path: "routes/\(routeID)"))
            geometry = try await session.client.send(APIRequest(method: .get, path: "routes/\(routeID)/geometry"))
            // Opening a card updates the server-side recent routes list.
            let _: EmptyResponse = try await session.client.send(APIRequest(method: .put, path: "users/me/recent-routes/\(routeID)"))
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func toggleBookmark(currentlySaved: Bool) async {
        isUpdatingBookmark = true
        defer { isUpdatingBookmark = false }
        do {
            if currentlySaved {
                let _: EmptyResponse = try await session.client.send(APIRequest(method: .delete, path: "users/me/bookmarks/\(routeID)"))
            } else {
                // The API returns a bookmark object for PUT; only the success status matters here.
                let _: ServerRouteBookmark = try await session.client.send(APIRequest(method: .put, path: "users/me/bookmarks/\(routeID)"))
            }
            route = try await session.client.send(APIRequest(method: .get, path: "routes/\(routeID)"))
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct ServerRouteBookmark: Decodable {
    let routeId: String
}
