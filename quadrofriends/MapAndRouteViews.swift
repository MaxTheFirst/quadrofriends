import Foundation
import SwiftUI
import MapKit
import PhotosUI

struct MapHomeView: View {
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
        MockData.routes.filter { route in
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

            Annotation("Вы", coordinate: Self.userCoordinate) {
                Image(systemName: "location.fill")
                    .foregroundStyle(Color.white)
                    .padding(10)
                    .background(Color.brandOlive, in: Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 3))
            }
            .annotationTitles(.hidden)

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

private enum MapControlLayout {
    static let size: CGFloat = 58
    static let edgeInset: CGFloat = 16
}

private struct MapControlButton: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: MapControlLayout.size, height: MapControlLayout.size)
                .background(tint, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.18), radius: 8, y: 3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct SelectedRouteMarker: View {
    let route: TrailRoute

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(route.imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 54, height: 54)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(Color.brandOrange, lineWidth: 4)
                }
                .shadow(color: Color.black.opacity(0.2), radius: 7, y: 3)

            Image(systemName: "checkmark")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(Color.white)
                .frame(width: 20, height: 20)
                .background(Color.brandOlive, in: Circle())
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Выбран маршрут: \(route.title)")
    }
}

private struct RouteMapMarker: Identifiable {
    let id = UUID()
    let title: String
    let details: String
    let coordinate: CLLocationCoordinate2D
    let photoData: Data?
}

private struct RouteMapMarkerBadge: View {
    let marker: RouteMapMarker

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.brandOlive)

            if let photoData = marker.photoData,
               let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else {
                Image(systemName: "mappin.and.ellipse")
                    .font(.title3)
                    .foregroundStyle(Color.white)
            }
        }
        .frame(width: 46, height: 46)
        .overlay(Circle().stroke(Color.white, lineWidth: 3))
        .shadow(color: Color.black.opacity(0.2), radius: 6, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(marker.title)
        .accessibilityHint(marker.details)
    }
}

private struct AddRouteMarkerView: View {
    @Binding var markerCoordinate: CLLocationCoordinate2D
    let onSave: (String, String, CLLocationCoordinate2D, Data?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var details = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section {
                Label("Перетащите метку на основной карте", systemImage: "hand.draw.fill")
                    .foregroundStyle(Color.brandOlive)

                HStack {
                    Text("Координаты")
                    Spacer()
                    Text(coordinateText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Положение")
            } footer: {
                Text("Начальная точка — ваша текущая геопозиция. Карта остаётся активной над этой панелью.")
            }

            Section("Метка") {
                TextField("Название", text: $title)
                TextField("Описание", text: $details, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section("Фото") {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    HStack(spacing: 12) {
                        photoPreview
                        VStack(alignment: .leading, spacing: 3) {
                            Text(photoData == nil ? "Добавить фото" : "Заменить фото")
                                .font(.headline)
                            Text("Фото поможет другим узнать это место")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Новая метка")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть", systemImage: "xmark") {
                    dismiss()
                }
                .labelStyle(.iconOnly)
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить", systemImage: "checkmark") {
                    onSave(
                        trimmedTitle,
                        details.trimmingCharacters(in: .whitespacesAndNewlines),
                        markerCoordinate,
                        photoData
                    )
                    dismiss()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderedProminent)
                .disabled(trimmedTitle.isEmpty)
            }
        }
        .task(id: selectedPhoto) {
            guard let selectedPhoto else { return }
            photoData = try? await selectedPhoto.loadTransferable(type: Data.self)
        }
    }

    private var coordinateText: String {
        String(
            format: "%.5f, %.5f",
            markerCoordinate.latitude,
            markerCoordinate.longitude
        )
    }

    @ViewBuilder
    private var photoPreview: some View {
        if let photoData, let image = UIImage(data: photoData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            Image(systemName: "photo.badge.plus")
                .font(.title2)
                .foregroundStyle(Color.brandOlive)
                .frame(width: 64, height: 52)
                .background(Color.brandOlive.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

private struct RecordingRouteSummary: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            let elapsed = max(0, Int(context.date.timeIntervalSince(startedAt)))
            let distance = Double(elapsed) * 0.0032
            let elevationGain = Int(distance * 28)

            HStack(spacing: 0) {
                RecordingMetric(
                    icon: "clock.fill",
                    value: duration(elapsed),
                    label: "Время"
                )

                Divider()
                    .frame(height: 38)

                RecordingMetric(
                    icon: "point.topleft.down.to.point.bottomright.curvepath",
                    value: String(format: "%.2f км", distance),
                    label: "Дистанция"
                )

                Divider()
                    .frame(height: 38)

                RecordingMetric(
                    icon: "arrow.up.forward",
                    value: "+\(elevationGain) м",
                    label: "Набор"
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 13)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .padding(12)
            }
            .shadow(color: Color.black.opacity(0.14), radius: 14, y: 5)
        }
    }

    private func duration(_ elapsed: Int) -> String {
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        return hours > 0
            ? String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct RecordingMetric: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(Color.brandOrange)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .monospacedDigit()
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

enum RouteSearchFilter: String, CaseIterable, Identifiable {
    case all = "Все"
    case publicRoutes = "Публичные"
    case privateRoutes = "Приватные"

    var id: Self { self }
}

struct RouteSearchView: View {
    @State private var query = ""
    @State private var filter = RouteSearchFilter.all

    private var results: [TrailRoute] {
        MockData.routes.filter { route in
            let matchesQuery = query.isEmpty || route.title.localizedCaseInsensitiveContains(query) || route.description.localizedCaseInsensitiveContains(query)
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .publicRoutes: matchesFilter = !route.isPrivate
            case .privateRoutes: matchesFilter = route.isPrivate
            }
            return matchesQuery && matchesFilter
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                Picker("Доступ", selection: $filter) {
                    ForEach(RouteSearchFilter.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                if query.isEmpty && filter == .all {
                    VStack(spacing: 12) {
                        SectionTitle(title: "Рекомендуемые", action: "Смотреть все")
                        ForEach(MockData.routes.prefix(2)) { route in
                            NavigationLink {
                                RouteDetailView(route: route)
                            } label: {
                                RouteRow(route: route)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(spacing: 12) {
                    SectionTitle(title: query.isEmpty ? "Новые маршруты" : "Результаты", action: "\(results.count)")
                    ForEach(results) { route in
                        NavigationLink {
                            RouteDetailView(route: route)
                        } label: {
                            RouteRow(route: route)
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
                Button("Фильтры", systemImage: "line.3.horizontal.decrease.circle") { }
                    .labelStyle(.iconOnly)
            }
        }
    }
}

struct RouteDetailView: View {
    let route: TrailRoute
    var onStart: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var isFavorite = false
    @State private var showingStarted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RoutePhoto(imageName: route.imageName, height: 235, cornerRadius: 0)

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(route.title)
                                .font(.title2)
                                .fontWeight(.bold)
                            HStack(spacing: 12) {
                                RatingLabel(rating: route.rating, count: route.reviewCount)
                                RouteMeta(route: route)
                            }
                        }
                        Spacer()
                        TagPill(text: route.isPrivate ? "Приватный" : "Публичный", selected: true)
                    }

                    Text(route.description)
                        .font(.body)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(route.tags, id: \.self) { tag in
                                TagPill(text: tag)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "Рейтинг по критериям")
                        RatingCriterionRow(title: "Сложность", rating: route.ratings.difficulty)
                        RatingCriterionRow(title: "Грязь", rating: route.ratings.mud)
                        RatingCriterionRow(title: "Поля", rating: route.ratings.fields)
                        RatingCriterionRow(title: "Лес", rating: route.ratings.forest)
                        RatingCriterionRow(title: "Пейзажи", rating: route.ratings.scenery)
                    }
                    .padding()
                    .background(Color.surfaceCream, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "Метки на маршруте", action: "2")
                        NavigationLink {
                            RouteMarkerView(route: route)
                        } label: {
                            MarkerRow(imageName: route.imageName, title: "Смотровая площадка", subtitle: "Отличный вид на долину", distance: "2,3 км")
                        }
                        .buttonStyle(.plain)
                        NavigationLink {
                            RouteMarkerView(route: MockData.routes[1])
                        } label: {
                            MarkerRow(imageName: "RouteMud", title: "Брод", subtitle: "Глубокий брод, будь осторожен", distance: "7,8 км")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
        .appBackground()
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isFavorite.toggle()
                } label: {
                    Image(systemName: isFavorite ? "bookmark.fill" : "bookmark")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                NavigationLink {
                    ShareRouteView(route: route)
                } label: {
                    Label("Поделиться", systemImage: "person.2.fill")
                        .font(.headline)
                        .foregroundStyle(Color.brandOlive)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.brandOlive.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Button {
                    if let onStart {
                        onStart()
                        dismiss()
                    } else {
                        showingStarted = true
                    }
                } label: {
                    Label("Старт", systemImage: "play.fill")
                }
                .buttonStyle(FilledActionButtonStyle())
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
        .alert("Маршрут запущен", isPresented: $showingStarted) {
            Button("Хорошо", role: .cancel) { }
        } message: {
            Text("Трек записывается. Геопозиция доступна выбранным участникам.")
        }
    }
}

private struct RatingCriterionRow: View {
    let title: String
    let rating: Double

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { index in
                    Image(systemName: Double(index) <= rating.rounded() ? "star.fill" : "star")
                        .foregroundStyle(Color.brandOrange)
                        .font(.caption)
                }
            }
            Text(rating, format: .number.precision(.fractionLength(1)))
                .font(.caption)
                .frame(width: 28, alignment: .trailing)
        }
    }
}

private struct MarkerRow: View {
    let imageName: String
    let title: String
    let subtitle: String
    let distance: String

    var body: some View {
        HStack(spacing: 10) {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 58, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(distance)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct RouteMarkerPhoto: Identifiable {
    enum Source {
        case asset(String)
        case data(Data)
    }

    let id: UUID
    let source: Source

    init(id: UUID = UUID(), source: Source) {
        self.id = id
        self.source = source
    }

    static let samples = [
        RouteMarkerPhoto(source: .asset("RouteFields")),
        RouteMarkerPhoto(source: .asset("RouteForest")),
        RouteMarkerPhoto(source: .asset("RouteMountain"))
    ]
}

private struct RouteMarkerPhotoThumbnail: View {
    let photo: RouteMarkerPhoto

    var body: some View {
        photoImage
            .resizable()
            .scaledToFill()
            .clipped()
    }

    private var photoImage: Image {
        switch photo.source {
        case .asset(let name):
            return Image(name)
        case .data(let data):
            if let image = UIImage(data: data) {
                return Image(uiImage: image)
            }
            return Image(systemName: "photo")
        }
    }
}

struct RouteMarkerView: View {
    let route: TrailRoute

    @State private var markerTitle = "Смотровая площадка"
    @State private var markerDetails = "Отличное место, чтобы сделать перерыв и насладиться видом на долину. Есть скамейка и стол."
    @State private var markerPhotos = RouteMarkerPhoto.samples
    @State private var showingEditor = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RoutePhoto(imageName: route.imageName, height: 270, cornerRadius: 0)
                VStack(alignment: .leading, spacing: 14) {
                    Text(markerTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                    Label("2,3 км от старта", systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(Color.brandOrange)
                    Text(markerDetails)
                    SectionTitle(title: "Фото")
                    if markerPhotos.isEmpty {
                        Label("Фото не добавлены", systemImage: "photo")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 8) {
                                ForEach(markerPhotos) { photo in
                                    RouteMarkerPhotoThumbnail(photo: photo)
                                        .frame(width: 112, height: 92)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                        .frame(height: 92)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
        .appBackground()
        .navigationTitle("Метка")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Редактировать", systemImage: "pencil") {
                    showingEditor = true
                }
                    .labelStyle(.iconOnly)
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                EditRouteMarkerView(
                    title: $markerTitle,
                    details: $markerDetails,
                    photos: $markerPhotos
                )
            }
            .presentationDetents([.medium, .large])
        }
    }
}

private struct EditRouteMarkerView: View {
    @Binding var title: String
    @Binding var details: String
    @Binding var photos: [RouteMarkerPhoto]

    @Environment(\.dismiss) private var dismiss
    @State private var draftTitle: String
    @State private var draftDetails: String
    @State private var draftPhotos: [RouteMarkerPhoto]
    @State private var selectedPhotos: [PhotosPickerItem] = []

    init(
        title: Binding<String>,
        details: Binding<String>,
        photos: Binding<[RouteMarkerPhoto]>
    ) {
        _title = title
        _details = details
        _photos = photos
        _draftTitle = State(initialValue: title.wrappedValue)
        _draftDetails = State(initialValue: details.wrappedValue)
        _draftPhotos = State(initialValue: photos.wrappedValue)
    }

    var body: some View {
        Form {
            Section("Метка") {
                TextField("Название", text: $draftTitle)
                TextField("Описание", text: $draftDetails, axis: .vertical)
                    .lineLimit(4...8)
            }

            Section("Фото") {
                if draftPhotos.isEmpty {
                    Label("Фото не добавлены", systemImage: "photo")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(draftPhotos) { photo in
                                ZStack(alignment: .topTrailing) {
                                    RouteMarkerPhotoThumbnail(photo: photo)
                                        .frame(width: 112, height: 92)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                    Button("Удалить фото", systemImage: "xmark.circle.fill", role: .destructive) {
                                        draftPhotos.removeAll { $0.id == photo.id }
                                    }
                                    .labelStyle(.iconOnly)
                                    .font(.title3)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(Color.white, Color.red)
                                    .padding(5)
                                }
                            }
                        }
                    }
                    .frame(height: 92)
                }

                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: 10,
                    matching: .images
                ) {
                    Label("Добавить фото", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle("Редактировать метку")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть", systemImage: "xmark") {
                    dismiss()
                }
                .labelStyle(.iconOnly)
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить", systemImage: "checkmark") {
                    title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    details = draftDetails.trimmingCharacters(in: .whitespacesAndNewlines)
                    photos = draftPhotos
                    dismiss()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderedProminent)
                .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .task(id: selectedPhotos) {
            guard !selectedPhotos.isEmpty else { return }

            let items = selectedPhotos
            var loadedPhotos: [RouteMarkerPhoto] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    loadedPhotos.append(RouteMarkerPhoto(source: .data(data)))
                }
            }

            draftPhotos.append(contentsOf: loadedPhotos)
            selectedPhotos.removeAll()
        }
    }
}

struct RouteEditorView: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Покатушка выходного дня"
    @State private var description = "Классный кольцевой маршрут недалеко от города. Много грязи и отличные виды!"
    @State private var isPrivate = true
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 60.011, longitude: 30.254),
            span: MKCoordinateSpan(latitudeDelta: 0.11, longitudeDelta: 0.11)
        )
    )

    private let points = [
        CLLocationCoordinate2D(latitude: 59.979, longitude: 30.211),
        CLLocationCoordinate2D(latitude: 60.005, longitude: 30.236),
        CLLocationCoordinate2D(latitude: 60.027, longitude: 30.251),
        CLLocationCoordinate2D(latitude: 60.011, longitude: 30.292),
        CLLocationCoordinate2D(latitude: 59.985, longitude: 30.274)
    ]

    var body: some View {
        Form {
            Section {
                routeMap
                HStack {
                    Button("Добавить точку", systemImage: "plus") { }
                    Spacer()
                    Button("Отменить", systemImage: "arrow.uturn.backward") { }
                }
            } header: {
                Text("Трек")
            }

            Section {
                TextField("Название", text: $name)
                TextEditor(text: $description)
                    .frame(minHeight: 90)
            } header: {
                Text("О маршруте")
            }

            Section {
                photoPicker
            } header: {
                Text("Фото")
            }

            Section {
                Toggle(isOn: $isPrivate) {
                    Label(isPrivate ? "Приватный маршрут" : "Публичный маршрут", systemImage: isPrivate ? "lock.fill" : "globe")
                }
            } header: {
                Text("Доступ")
            } footer: {
                Text(isPrivate ? "Маршрут виден только вам и тем, с кем вы им поделитесь." : "Маршрут смогут найти все пользователи.")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть", systemImage: "xmark") {
                    dismiss()
                }
                .labelStyle(.iconOnly)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить", systemImage: "checkmark") {
                    dismiss()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var routeMap: some View {
        Map(position: $camera) {
            MapPolyline(coordinates: points + [points[0]])
                .stroke(Color.brandOrange, style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [3, 7]))
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                Annotation("\(index + 1)", coordinate: point) {
                    Text("\(index + 1)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.white)
                        .frame(width: 24, height: 24)
                        .background(Color.brandOrange, in: Circle())
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var photoPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(["RouteForest", "RouteMud", "RouteFields"], id: \.self) { image in
                    Image(image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 92, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                Button("Добавить", systemImage: "plus") { }
                    .labelStyle(.iconOnly)
                    .frame(width: 72, height: 72)
                    .background(Color(.quaternarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

struct ShareRouteView: View {
    let route: TrailRoute
    @State private var linkEnabled = true
    @State private var selectedUsers: Set<String> = ["@kvadro_life"]
    @State private var copied = false

    private let users = [
        ("@atv_rider", "Иван Петров", "ИП"),
        ("@kvadro_life", "Алексей Смирнов", "АС"),
        ("@mud_queen", "Мария Иванова", "МИ")
    ]

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(route.imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 76, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(route.title)
                            .font(.headline)
                        Text("\(route.distance) км")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Toggle("Доступ по ссылке", isOn: $linkEnabled)
                if linkEnabled {
                    HStack {
                        Text("quadro.friends/route/\(route.id)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button(copied ? "Скопировано" : "Копировать", systemImage: copied ? "checkmark" : "doc.on.doc") {
                            copied = true
                        }
                        .labelStyle(.iconOnly)
                    }
                }
            } header: {
                Text("Доступ по ссылке")
            } footer: {
                Text("По ссылке маршрут смогут открыть только пользователи приложения.")
            }

            Section("Доступ для пользователей") {
                ForEach(users, id: \.0) { user in
                    Button {
                        if selectedUsers.contains(user.0) {
                            selectedUsers.remove(user.0)
                        } else {
                            selectedUsers.insert(user.0)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            AvatarView(imageName: nil, initials: user.2, size: 42)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.0)
                                    .foregroundStyle(.primary)
                                    .fontWeight(.semibold)
                                Text(user.1)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            EmptySelectionCircle(selected: selectedUsers.contains(user.0))
                        }
                    }
                }
            }
        }
        .navigationTitle("Поделиться маршрутом")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            ShareLink(item: "Маршрут \(route.title): quadro.friends/route/\(route.id)") {
                Label("Поделиться", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(FilledActionButtonStyle())
            .padding()
            .background(.regularMaterial)
        }
    }
}
