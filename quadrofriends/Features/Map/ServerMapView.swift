import MapKit
import SwiftUI

struct ServerMapView: View {
    @EnvironmentObject private var session: APISession
    @EnvironmentObject private var chatLocationStore: ChatLocationSharingStore
    @Binding var appTheme: AppTheme
    @StateObject private var location = MapLocationRecordingStore()
    @State private var camera: MapCameraPosition = .region(Self.initialRegion)
    @State private var visibleRegion = Self.initialRegion
    @State private var mapDisplayStyle = MapDisplayStyle.scheme
    @State private var routes: [ServerRoute] = []
    @State private var selectedRoute: ServerRoute?
    @State private var selectedGeometry: ServerRouteGeometry?
    @State private var isLoading = false
    @State private var error: String?
    @State private var showingSearch = false
    @State private var showingMapSettings = false
    @State private var showingMarkerEditor = false
    @State private var showingPublish = false
    @State private var localMarkers: [RouteMapMarker] = []
    @State private var didLoad = false
    @State private var followsUser = true
    @State private var didCenterOnUser = false

    private static let initialRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 60.011, longitude: 30.254),
        span: MKCoordinateSpan(latitudeDelta: 0.105, longitudeDelta: 0.105)
    )

    var body: some View {
        Map(position: $camera) {
            if let coordinate = location.coordinate {
                Annotation("Вы", coordinate: coordinate) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Color.brandOlive, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                }
                .annotationTitles(.hidden)
            }
            ForEach(chatLocationStore.visibleShares) { share in
                Annotation(share.name, coordinate: share.coordinate) {
                    ChatLiveLocationAvatar(share: share)
                }
                .annotationTitles(.hidden)
            }
            if let selectedGeometry, selectedGeometry.coordinates.count > 1 {
                MapPolyline(coordinates: selectedGeometry.coordinates)
                    .stroke(Color.brandOrange, lineWidth: 5)
            }
            if location.recordedTrack.count > 1 {
                MapPolyline(coordinates: location.recordedTrack)
                    .stroke(Color.brandOrange, lineWidth: 5)
            }
            ForEach(localMarkers) { marker in
                Annotation(marker.title, coordinate: marker.coordinate) {
                    RouteMapMarkerBadge(marker: marker)
                }
                .annotationTitles(.hidden)
            }
            ForEach(routes) { route in
                Annotation(route.title, coordinate: route.coordinate) {
                    Button {
                        Task { await select(route) }
                    } label: {
                        Image(systemName: selectedRoute?.id == route.id ? "mappin.circle.fill" : "mappin.circle")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.brandOlive)
                            .background(.white, in: Circle())
                    }
                    .accessibilityLabel(route.title)
                }
            }
        }
        .mapStyle(mapDisplayStyle.mapStyle)
        .mapControls { MapCompass() }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
            if camera.positionedByUser { followsUser = false }
            Task { await loadRoutes() }
        }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 12) {
                MapControlButton(title: "Поиск маршрутов", icon: "magnifyingglass", tint: Color.brandOlive) {
                    showingSearch = true
                }
                MapControlButton(
                    title: location.isRecording ? "Остановить запись маршрута" : "Начать запись маршрута",
                    icon: location.isRecording ? "stop.fill" : "record.circle",
                    tint: location.isRecording ? .red : Color.brandOrange
                ) {
                    if location.isRecording {
                        Task { await location.finishRecording() }
                    } else {
                        selectedRoute = nil
                        selectedGeometry = nil
                        location.startRecording()
                    }
                }
                if location.isRecording, location.coordinate != nil {
                    MapControlButton(title: "Добавить метку", icon: "mappin.and.ellipse", tint: Color.brandOlive) {
                        showingMarkerEditor = true
                    }
                }
                if isLoading || location.isBusy { ProgressView().padding(8) }
            }
            .padding(.top, 12)
            .padding(.trailing, MapControlLayout.edgeInset)
        }
        .overlay(alignment: .trailing) {
            VStack(spacing: 12) {
                MapControlButton(title: "Приблизить", icon: "plus", tint: Color.brandOlive) { zoom(by: 0.55) }
                MapControlButton(title: "Отдалить", icon: "minus", tint: Color.brandOlive) { zoom(by: 1.8) }
            }
            .padding(.trailing, MapControlLayout.edgeInset)
        }
        .overlay(alignment: .bottom) {
            HStack {
                MapControlButton(title: "Настройки карты", icon: "map.fill", tint: Color.brandOlive) {
                    showingMapSettings = true
                }
                Spacer()
                MapControlButton(title: "Найти меня", icon: "paperplane.fill", tint: Color.brandOlive) {
                    followsUser = true
                    selectedRoute = nil
                    selectedGeometry = nil
                    if let coordinate = location.coordinate { centerOnUser(coordinate) }
                    location.locate()
                }
            }
            .padding(.horizontal, MapControlLayout.edgeInset)
            .padding(.bottom, 16)
        }
        .overlay(alignment: .topLeading) {
            if let error = location.error ?? error {
                Button {
                    location.error = nil
                    Task { await loadRoutes() }
                } label: {
                    Label(error, systemImage: "wifi.exclamationmark")
                        .font(.caption)
                        .lineLimit(2)
                }
                .buttonStyle(.bordered)
                .padding()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if location.isRecording, let startedAt = location.startedAt {
                RecordingRouteSummary(startedAt: startedAt)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            } else if let completed = location.completedRecording {
                Button("Сохранить записанный маршрут") { showingPublish = true }
                    .buttonStyle(FilledActionButtonStyle())
                    .disabled(completed.pointCount < 2)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            } else if let selectedRoute {
                NavigationLink {
                    ServerRouteDetailView(routeID: selectedRoute.id)
                } label: {
                    ServerRouteRow(route: selectedRoute)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle("Карта")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingSearch) {
            NavigationStack {
                ServerRouteSearchView { route in
                    showingSearch = false
                    Task { await select(route) }
                }
            }
        }
        .sheet(isPresented: $showingMapSettings) {
            NavigationStack {
                MapSettingsView(mapStyle: $mapDisplayStyle, appTheme: $appTheme)
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingMarkerEditor) {
            NavigationStack {
                ServerRecordingMarkerEditor { title, details in
                    guard let coordinate = location.coordinate else { return false }
                    let saved = await location.addMarker(title: title, description: details, at: coordinate)
                    if saved {
                        localMarkers.append(RouteMapMarker(title: title, details: details, coordinate: coordinate, photoData: nil))
                    }
                    return saved
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingPublish) {
            if let completed = location.completedRecording {
                NavigationStack {
                    PublishRecordingView(recordingID: completed.id) {
                        location.clearCompletedRecording()
                        localMarkers = []
                        await loadRoutes()
                    }
                }
            }
        }
        .onReceive(location.$coordinate) { coordinate in
            guard let coordinate, followsUser, !camera.positionedByUser else { return }
            centerOnUser(coordinate)
        }
        .onAppear {
            location.startObservingLocation()
        }
        .onDisappear {
            location.stopObservingLocation()
        }
        .task {
            location.connect(session)
            await loadRoutes()
        }
    }

    private func loadRoutes() async {
        isLoading = true
        error = nil
        let region = visibleRegion
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let bbox = "\(minLon),\(minLat),\(maxLon),\(maxLat)"
        do {
            routes = try await ServerRoutesAPI.list(session.client, path: "routes", query: [
                URLQueryItem(name: "bbox", value: bbox),
                URLQueryItem(name: "sort", value: "recommended")
            ])
        } catch {
            self.error = error.localizedDescription
        }
        didLoad = true
        isLoading = false
    }

    private func zoom(by factor: Double) {
        var region = visibleRegion
        region.span.latitudeDelta = min(max(region.span.latitudeDelta * factor, 0.002), 1.0)
        region.span.longitudeDelta = min(max(region.span.longitudeDelta * factor, 0.002), 1.0)
        camera = .region(region)
    }

    private func centerOnUser(_ coordinate: CLLocationCoordinate2D) {
        let span = didCenterOnUser ? visibleRegion.span : MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
        didCenterOnUser = true
        camera = .region(MKCoordinateRegion(center: coordinate, span: span))
    }

    private func select(_ route: ServerRoute) async {
        followsUser = false
        selectedRoute = route
        selectedGeometry = nil
        camera = .region(MKCoordinateRegion(
            center: route.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        ))
        do {
            selectedGeometry = try await session.client.send(APIRequest(
                method: .get, path: "routes/\(route.id)/geometry"
            ))
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct ServerRouteSearchView: View {
    @EnvironmentObject private var session: APISession
    @Environment(\.dismiss) private var dismiss
    let onSelect: (ServerRoute) -> Void
    @State private var query = ""
    @State private var filter = RouteSearchFilter.all
    @State private var routes: [ServerRoute] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var filtersExpanded = false
    @State private var maximumDistance = 525.0
    @State private var timeFilter = RouteTimeFilter.any
    @State private var difficultyFilter = RouteRatingFilter.any
    @State private var mudFilter = RouteRatingFilter.any
    @State private var fieldsFilter = RouteRatingFilter.any
    @State private var forestFilter = RouteRatingFilter.any
    @State private var sceneryFilter = RouteRatingFilter.any
    @State private var minimumCompletedCount = ""

    private var searchKey: String {
        "\(filter.id)-\(query)-\(maximumDistance)-\(timeFilter.id)-\(difficultyFilter.rawValue)-\(mudFilter.rawValue)-\(fieldsFilter.rawValue)-\(forestFilter.rawValue)-\(sceneryFilter.rawValue)-\(minimumCompletedCount)"
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                Picker("Доступ", selection: $filter) {
                    ForEach(RouteSearchFilter.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                DisclosureGroup("Фильтры", isExpanded: $filtersExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Длина маршрута")
                            Spacer()
                            Text(maximumDistance > 500 ? "Любая" : "до \(Int(maximumDistance)) км")
                                .foregroundStyle(Color.brandOlive)
                        }
                        Slider(value: $maximumDistance, in: 25...525, step: 25)
                        Picker("Время", selection: $timeFilter) {
                            ForEach(RouteTimeFilter.allCases) { value in
                                Text(value.title).tag(value)
                            }
                        }
                        .pickerStyle(.menu)
                        ratingPicker("Сложность", selection: $difficultyFilter)
                        ratingPicker("Грязь", selection: $mudFilter)
                        ratingPicker("Поля", selection: $fieldsFilter)
                        ratingPicker("Лес", selection: $forestFilter)
                        ratingPicker("Пейзажи", selection: $sceneryFilter)
                        HStack {
                            Text("Прошло маршрут от")
                            Spacer()
                            TextField("0", text: $minimumCompletedCount)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                        }
                    }
                    .font(.subheadline)
                    .padding(.top, 10)
                }
                .tint(Color.brandOlive)

                if isLoading {
                    ProgressView("Ищем маршруты")
                } else if let error {
                    ContentUnavailableView {
                        Label("Не удалось найти маршруты", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Повторить") { Task { await load() } }
                    }
                } else if routes.isEmpty {
                    ContentUnavailableView("Маршруты не найдены", systemImage: "magnifyingglass")
                } else {
                    ForEach(routes) { route in
                        Button { onSelect(route) } label: {
                            ServerRouteRow(route: route)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .appBackground()
        .navigationTitle("Поиск маршрутов")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Название или описание")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Закрыть") { dismiss() }
            }
        }
        .task(id: searchKey) {
            if !query.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            await load()
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        let visibility: String
        switch filter {
        case .all: visibility = "all"
        case .publicRoutes: visibility = "public"
        case .privateRoutes: visibility = "private"
        }
        let durationBucket: String?
        switch timeFilter {
        case .any: durationBucket = nil
        case .upToFourHours: durationBucket = "up_to_4h"
        case .upToEightHours: durationBucket = "up_to_8h"
        case .fullDay: durationBucket = "full_day"
        }
        func ratingValue(_ filter: RouteRatingFilter) -> String? {
            filter == .any ? nil : String(filter.rawValue)
        }
        do {
            routes = try await ServerRoutesAPI.list(session.client, path: "routes", query: [
                URLQueryItem(name: "query", value: query.isEmpty ? nil : query),
                URLQueryItem(name: "visibility", value: visibility),
                URLQueryItem(name: "sort", value: "recommended"),
                URLQueryItem(name: "max_distance_m", value: maximumDistance > 500 ? nil : String(Int(maximumDistance) * 1_000)),
                URLQueryItem(name: "duration_bucket", value: durationBucket),
                URLQueryItem(name: "min_difficulty", value: ratingValue(difficultyFilter)),
                URLQueryItem(name: "min_mud", value: ratingValue(mudFilter)),
                URLQueryItem(name: "min_fields", value: ratingValue(fieldsFilter)),
                URLQueryItem(name: "min_forest", value: ratingValue(forestFilter)),
                URLQueryItem(name: "min_scenery", value: ratingValue(sceneryFilter)),
                URLQueryItem(name: "min_completed_count", value: Int(minimumCompletedCount).map(String.init))
            ])
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func ratingPicker(_ title: String, selection: Binding<RouteRatingFilter>) -> some View {
        Picker(title, selection: selection) {
            ForEach(RouteRatingFilter.allCases) { value in
                Text(value.title).tag(value)
            }
        }
        .pickerStyle(.menu)
    }
}
