import Foundation
import SwiftUI
import MapKit
import PhotosUI

struct MapHomeView: View {
    @EnvironmentObject private var chatLocationStore: ChatLocationSharingStore
    @StateObject private var routesViewModel = DemoRoutesViewModel()
    @Binding var appTheme: AppTheme
    @State private var camera: MapCameraPosition = .region(Self.region)
    @State private var visibleRegion = Self.region
    @State private var mapDisplayStyle = MapDisplayStyle.scheme
    @State private var showingSearch = false
    @State private var showingMapSettings = false
    @State private var showingMarkerEditor = false
    @State private var markerDraftCoordinate: CLLocationCoordinate2D?
    @State private var isRecording = false
    @State private var isFollowingRoute = false
    @State private var recordingStartedAt = Date()
    @State private var selectedRoute: TrailRoute?
    @State private var routeMarkers: [RouteMapMarker] = []
    @State private var searchQuery = ""
    @State private var maximumDistance = 525.0
    @State private var timeFilter = RouteTimeFilter.any
    @State private var difficultyRatingFilter = RouteRatingFilter.any
    @State private var mudRatingFilter = RouteRatingFilter.any
    @State private var fieldsRatingFilter = RouteRatingFilter.any
    @State private var forestRatingFilter = RouteRatingFilter.any
    @State private var sceneryRatingFilter = RouteRatingFilter.any
    @State private var minimumCompletedCount = 0

    private static let region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 60.011, longitude: 30.254),
        span: MKCoordinateSpan(latitudeDelta: 0.105, longitudeDelta: 0.105)
    )

    private static let userCoordinate = CLLocationCoordinate2D(latitude: 59.988, longitude: 30.199)

    private static let routeCoordinates: [String: CLLocationCoordinate2D] = [
        "forest-adventure": CLLocationCoordinate2D(latitude: 60.026, longitude: 30.251),
        "mud-weekend": CLLocationCoordinate2D(latitude: 59.996, longitude: 30.292),
        "mountain-paths": CLLocationCoordinate2D(latitude: 60.018, longitude: 30.218),
        "fields-forest": CLLocationCoordinate2D(latitude: 59.981, longitude: 30.231)
    ]

    private static let defaultTrail = [
        CLLocationCoordinate2D(latitude: 59.979, longitude: 30.211),
        CLLocationCoordinate2D(latitude: 59.994, longitude: 30.231),
        CLLocationCoordinate2D(latitude: 60.010, longitude: 30.217),
        CLLocationCoordinate2D(latitude: 60.027, longitude: 30.251),
        CLLocationCoordinate2D(latitude: 60.018, longitude: 30.287),
        CLLocationCoordinate2D(latitude: 59.995, longitude: 30.296)
    ]

    private static let routePaths: [String: [CLLocationCoordinate2D]] = [
        "forest-adventure": defaultTrail,
        "mud-weekend": [
            CLLocationCoordinate2D(latitude: 59.984, longitude: 30.273),
            CLLocationCoordinate2D(latitude: 59.991, longitude: 30.284),
            CLLocationCoordinate2D(latitude: 60.000, longitude: 30.296),
            CLLocationCoordinate2D(latitude: 60.010, longitude: 30.304),
            CLLocationCoordinate2D(latitude: 60.003, longitude: 30.313),
            CLLocationCoordinate2D(latitude: 59.991, longitude: 30.307),
            CLLocationCoordinate2D(latitude: 59.984, longitude: 30.273)
        ],
        "mountain-paths": [
            CLLocationCoordinate2D(latitude: 60.003, longitude: 30.201),
            CLLocationCoordinate2D(latitude: 60.011, longitude: 30.208),
            CLLocationCoordinate2D(latitude: 60.018, longitude: 30.218),
            CLLocationCoordinate2D(latitude: 60.027, longitude: 30.229),
            CLLocationCoordinate2D(latitude: 60.035, longitude: 30.220)
        ],
        "fields-forest": [
            CLLocationCoordinate2D(latitude: 59.967, longitude: 30.214),
            CLLocationCoordinate2D(latitude: 59.975, longitude: 30.224),
            CLLocationCoordinate2D(latitude: 59.981, longitude: 30.231),
            CLLocationCoordinate2D(latitude: 59.989, longitude: 30.239),
            CLLocationCoordinate2D(latitude: 59.995, longitude: 30.228)
        ]
    ]

    private var displayedTrail: [CLLocationCoordinate2D] {
        guard let selectedRoute else { return Self.defaultTrail }
        return Self.routePaths[selectedRoute.id] ?? Self.defaultTrail
    }

    private var searchResults: [TrailRoute] {
        routesViewModel.routes.filter { route in
            let normalizedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesText = normalizedQuery.isEmpty
                || route.title.localizedCaseInsensitiveContains(normalizedQuery)
                || route.description.localizedCaseInsensitiveContains(normalizedQuery)
                || route.tags.contains { $0.localizedCaseInsensitiveContains(normalizedQuery) }
            return matchesText
                && (maximumDistance > 500 || route.distance <= Int(maximumDistance))
                && timeFilter.matches(route)
                && difficultyRatingFilter.matches(route.ratings.difficulty)
                && mudRatingFilter.matches(route.ratings.mud)
                && fieldsRatingFilter.matches(route.ratings.fields)
                && forestRatingFilter.matches(route.ratings.forest)
                && sceneryRatingFilter.matches(route.ratings.scenery)
                && route.completedCount >= minimumCompletedCount
        }
    }

    private var markerDraftCoordinateBinding: Binding<CLLocationCoordinate2D> {
        Binding(
            get: { markerDraftCoordinate ?? Self.userCoordinate },
            set: { markerDraftCoordinate = $0 }
        )
    }

    var body: some View {
        ZStack {
            mapLayer

            if showingSearch {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture { showingSearch = false }

                MapRouteSearchModal(
                    query: $searchQuery,
                    maximumDistance: $maximumDistance,
                    timeFilter: $timeFilter,
                    difficultyRatingFilter: $difficultyRatingFilter,
                    mudRatingFilter: $mudRatingFilter,
                    fieldsRatingFilter: $fieldsRatingFilter,
                    forestRatingFilter: $forestRatingFilter,
                    sceneryRatingFilter: $sceneryRatingFilter,
                    minimumCompletedCount: $minimumCompletedCount,
                    results: searchResults,
                    onSelect: selectRoute,
                    onClose: { showingSearch = false }
                )
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: showingSearch)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isRecording {
                RecordingRouteSummary(startedAt: recordingStartedAt)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let selectedRoute, !showingSearch {
                NavigationLink {
                    RouteDetailView(route: selectedRoute) {
                        isRecording = false
                        isFollowingRoute = true
                    }
                } label: {
                    Label(
                        isFollowingRoute ? "Маршрут активен" : "Открыть маршрут",
                        systemImage: isFollowingRoute ? "location.fill" : "arrow.up.right.square"
                    )
                }
                .buttonStyle(FilledActionButtonStyle())
                .padding(.horizontal)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle("Карта")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingMapSettings) {
            NavigationStack {
                MapSettingsView(mapStyle: $mapDisplayStyle, appTheme: $appTheme)
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingMarkerEditor, onDismiss: {
            markerDraftCoordinate = nil
        }) {
            NavigationStack {
                AddRouteMarkerView(
                    markerCoordinate: markerDraftCoordinateBinding
                ) { title, details, coordinate, photoData in
                    routeMarkers.append(
                        RouteMapMarker(
                            title: title,
                            details: details,
                            coordinate: coordinate,
                            photoData: photoData
                        )
                    )
                }
            }
            .presentationDetents([.medium])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
    }

    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $camera) {
            MapPolyline(coordinates: displayedTrail)
                .stroke(Color.brandOrange, style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [3, 7]))

            ForEach(Array(displayedTrail.enumerated()), id: \.offset) { index, point in
                Annotation("Точка \(index + 1)", coordinate: point) {
                    Text("\(index + 1)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.white)
                        .frame(width: 28, height: 28)
                        .background(Color.brandOrange, in: Circle())
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                }
                .annotationTitles(.hidden)
            }

            if !chatLocationStore.visibleShares.contains(where: \.isMine) {
                Annotation("Вы", coordinate: Self.userCoordinate) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(Color.white)
                        .padding(10)
                        .background(Color.brandOlive, in: Circle())
                        .overlay(Circle().stroke(Color.white, lineWidth: 3))
                }
                .annotationTitles(.hidden)
            }

            ForEach(chatLocationStore.visibleShares) { share in
                Annotation(share.name, coordinate: share.coordinate) {
                    ChatLiveLocationAvatar(share: share)
                }
                .annotationTitles(.hidden)
            }

            if showingSearch {
                ForEach(searchResults) { route in
                    Annotation(route.title, coordinate: coordinate(for: route)) {
                        Button {
                            selectRoute(route)
                        } label: {
                            Image(route.imageName)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 42, height: 42)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white, lineWidth: 3))
                                .shadow(radius: 4, y: 2)
                        }
                        .accessibilityLabel(route.title)
                    }
                    .annotationTitles(.hidden)
                }
            }

            if let selectedRoute, !showingSearch {
                Annotation(selectedRoute.title, coordinate: coordinate(for: selectedRoute)) {
                    SelectedRouteMarker(route: selectedRoute)
                }
                .annotationTitles(.hidden)
            }

                ForEach(routeMarkers) { marker in
                    Annotation(marker.title, coordinate: marker.coordinate) {
                        RouteMapMarkerBadge(marker: marker)
                    }
                    .annotationTitles(.hidden)
                }

                if let markerDraftCoordinate {
                    Annotation("Новая метка", coordinate: markerDraftCoordinate) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 42, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.white, Color.brandOlive)
                            .shadow(color: Color.black.opacity(0.25), radius: 6, y: 3)
                            .gesture(
                                DragGesture(
                                    minimumDistance: 0,
                                    coordinateSpace: .named("mainRouteMap")
                                )
                                .onChanged { value in
                                    guard let coordinate = proxy.convert(
                                        value.location,
                                        from: .named("mainRouteMap")
                                    ) else { return }
                                    self.markerDraftCoordinate = coordinate
                                }
                            )
                            .accessibilityLabel("Положение новой метки")
                            .accessibilityHint("Перетащите метку по основной карте")
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(mapDisplayStyle.mapStyle)
            .mapControls { MapCompass() }
            .coordinateSpace(.named("mainRouteMap"))
            .onMapCameraChange(frequency: .continuous) { context in
                visibleRegion = context.region
            }
            .overlay(alignment: .topTrailing) {
                VStack(spacing: 12) {
                    MapControlButton(
                        title: "Поиск маршрутов",
                        icon: "magnifyingglass",
                        tint: Color.brandOlive
                    ) {
                        showingSearch = true
                    }

                    recordButton

                    if isRecording || isFollowingRoute {
                        MapControlButton(
                            title: "Добавить метку",
                            icon: "mappin.and.ellipse",
                            tint: markerDraftCoordinate == nil ? Color.brandOlive : Color.brandOrange
                        ) {
                            beginAddingMarker()
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.top, 12)
                .padding(.trailing, MapControlLayout.edgeInset)
            }
            .overlay(alignment: .trailing) {
                VStack(spacing: 12) {
                    MapControlButton(
                        title: "Приблизить",
                        icon: "plus",
                        tint: Color.brandOlive
                    ) {
                        zoom(by: 0.55)
                    }

                    MapControlButton(
                        title: "Отдалить",
                        icon: "minus",
                        tint: Color.brandOlive
                    ) {
                        zoom(by: 1.8)
                    }
                }
                .padding(.trailing, MapControlLayout.edgeInset)
            }
            .overlay(alignment: .bottom) {
                HStack {
                    MapControlButton(
                        title: "Настройки карты",
                        icon: "map.fill",
                        tint: Color.brandOlive
                    ) {
                        showingMapSettings = true
                    }

                    Spacer()

                    MapControlButton(
                        title: "Найти меня",
                        icon: "paperplane.fill",
                        tint: Color.brandOlive
                    ) {
                        centerOnUser()
                    }
                }
                .padding(.horizontal, MapControlLayout.edgeInset)
                .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private var recordButton: some View {
        MapControlButton(
            title: isRecording ? "Остановить запись маршрута" : "Начать запись маршрута",
            icon: isRecording ? "stop.fill" : "record.circle",
            tint: isRecording ? Color.red : Color.brandOrange
        ) {
            if isRecording {
                isRecording = false
            } else {
                recordingStartedAt = Date()
                isFollowingRoute = false
                selectedRoute = nil
                isRecording = true
            }
        }
    }

    private func coordinate(for route: TrailRoute) -> CLLocationCoordinate2D {
        Self.routeCoordinates[route.id] ?? Self.region.center
    }

    private func selectRoute(_ route: TrailRoute) {
        selectedRoute = route
        isFollowingRoute = false
        showingSearch = false
        camera = .region(
            MKCoordinateRegion(
                center: coordinate(for: route),
                span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
            )
        )
    }

    private func centerOnUser() {
        camera = .region(
            MKCoordinateRegion(
                center: Self.userCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
            )
        )
    }

    private func beginAddingMarker() {
        markerDraftCoordinate = Self.userCoordinate
        camera = .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: Self.userCoordinate.latitude - 0.009,
                    longitude: Self.userCoordinate.longitude
                ),
                span: MKCoordinateSpan(latitudeDelta: 0.045, longitudeDelta: 0.045)
            )
        )
        showingMarkerEditor = true
    }

    private func zoom(by factor: Double) {
        var region = visibleRegion
        region.span.latitudeDelta = min(max(region.span.latitudeDelta * factor, 0.002), 1.0)
        region.span.longitudeDelta = min(max(region.span.longitudeDelta * factor, 0.002), 1.0)
        camera = .region(region)
    }
}
