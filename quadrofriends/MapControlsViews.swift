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

struct MapRouteSearchModal: View {
    @Binding var query: String
    @Binding var maximumDistance: Double
    @Binding var timeFilter: RouteTimeFilter
    @Binding var difficultyRatingFilter: RouteRatingFilter
    @Binding var mudRatingFilter: RouteRatingFilter
    @Binding var fieldsRatingFilter: RouteRatingFilter
    @Binding var forestRatingFilter: RouteRatingFilter
    @Binding var sceneryRatingFilter: RouteRatingFilter
    @Binding var minimumCompletedCount: Int
    let results: [TrailRoute]
    let onSelect: (TrailRoute) -> Void
    let onClose: () -> Void

    @State private var filtersExpanded = false
    @FocusState private var searchFocused: Bool

    private var activeFilterCount: Int {
        var count = 0
        if maximumDistance <= 500 { count += 1 }
        if timeFilter != .any { count += 1 }
        if difficultyRatingFilter != .any { count += 1 }
        if mudRatingFilter != .any { count += 1 }
        if fieldsRatingFilter != .any { count += 1 }
        if forestRatingFilter != .any { count += 1 }
        if sceneryRatingFilter != .any { count += 1 }
        if minimumCompletedCount > 0 { count += 1 }
        return count
    }

    private var distanceValue: String {
        maximumDistance > 500 ? "Любое" : "до \(Int(maximumDistance)) км"
    }

    private var completedCountText: Binding<String> {
        Binding(
            get: {
                minimumCompletedCount == 0 ? "" : String(minimumCompletedCount)
            },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                minimumCompletedCount = min(Int(digits) ?? 0, 999_999)
            }
        )
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Название, описание или тег", text: $query)
                    .textInputAutocapitalization(.never)
                    .focused($searchFocused)
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button("Очистить", systemImage: "xmark.circle.fill") {
                        query = ""
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            DisclosureGroup(isExpanded: $filtersExpanded) {
                VStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Расстояние")
                            Spacer()
                            Text(distanceValue)
                                .foregroundStyle(Color.brandOlive)
                        }
                        Slider(value: $maximumDistance, in: 25...525, step: 25)
                    }

                    TimeFilterRow(selection: $timeFilter)

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Рейтинг по критериям")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)
                            ],
                            spacing: 8
                        ) {
                            RatingFilterMenu(title: "Сложность", selection: $difficultyRatingFilter)
                            RatingFilterMenu(title: "Грязь", selection: $mudRatingFilter)
                            RatingFilterMenu(title: "Поля", selection: $fieldsRatingFilter)
                            RatingFilterMenu(title: "Лес", selection: $forestRatingFilter)
                            RatingFilterMenu(title: "Пейзажи", selection: $sceneryRatingFilter)
                        }
                    }

                    HStack(spacing: 8) {
                        Label("Прошло маршрут от", systemImage: "person.2.fill")
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .layoutPriority(1)
                        Spacer(minLength: 4)
                        HStack(spacing: 5) {
                            TextField("0", text: completedCountText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 52)
                            Text("чел.")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                    }
                }
                .font(.subheadline)
                .padding(.top, 10)
            } label: {
                HStack {
                    Label("Фильтры", systemImage: "line.3.horizontal.decrease")
                    Spacer()
                    if activeFilterCount > 0 {
                        Text("\(activeFilterCount)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.white)
                            .frame(width: 21, height: 21)
                            .background(Color.brandOlive, in: Circle())
                    }
                }
                .fontWeight(.semibold)
            }
            .tint(Color.brandOlive)

            Divider()

            HStack {
                Text("На карте")
                    .font(.headline)
                Spacer()
                Text("\(results.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if results.isEmpty {
                ContentUnavailableView(
                    "Ничего не найдено",
                    systemImage: "map",
                    description: Text("Измените запрос или параметры фильтра.")
                )
                .frame(maxHeight: 180)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(results) { route in
                            Button {
                                onSelect(route)
                            } label: {
                                MapSearchResultRow(route: route)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: filtersExpanded ? 130 : 300)
            }

            Button("Закрыть", action: onClose)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        }
        .padding(18)
        .frame(maxWidth: 370)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 30, y: 12)
        .padding(.horizontal, 20)
        .onAppear { searchFocused = true }
    }
}

private struct MapSearchResultRow: View {
    let route: TrailRoute

    var body: some View {
        HStack(spacing: 10) {
            Image(route.imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 62, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(route.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                HStack(spacing: 7) {
                    Text("\(route.distance) км")
                    Text(route.duration)
                    Label("\(route.completedCount)", systemImage: "person.2.fill")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "location.fill")
                .foregroundStyle(Color.brandOlive)
        }
        .padding(8)
        .background(Color.surfaceCream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct TimeFilterRow: View {
    @Binding var selection: RouteTimeFilter

    var body: some View {
        LabeledContent("Время") {
            Picker("Время", selection: $selection) {
                ForEach(RouteTimeFilter.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            .labelsHidden()
        }
    }
}

private struct RatingFilterMenu: View {
    let title: String
    @Binding var selection: RouteRatingFilter

    var body: some View {
        Menu {
            ForEach(RouteRatingFilter.allCases) { filter in
                Button {
                    selection = filter
                } label: {
                    if selection == filter {
                        Label(filter.title, systemImage: "checkmark")
                    } else {
                        Text(filter.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(selection.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                }
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Color.brandOlive)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

struct MapSettingsView: View {
    @Binding var mapStyle: MapDisplayStyle
    @Binding var appTheme: AppTheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Вид карты") {
                Picker("Вид карты", selection: $mapStyle) {
                    ForEach(MapDisplayStyle.allCases) { style in
                        Label(style.title, systemImage: style.icon).tag(style)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("Тема приложения") {
                Picker("Тема", selection: $appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Label(theme.title, systemImage: theme.icon).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle("Настройки карты")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово", systemImage: "checkmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
