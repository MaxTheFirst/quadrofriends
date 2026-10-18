import SwiftUI

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

                    NavigationLink {
                        MemberProfileView(author: route.author)
                    } label: {
                        HStack(spacing: 12) {
                            AvatarView(
                                imageName: route.author.avatarImage,
                                initials: route.author.initials,
                                size: 48
                            )
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Автор маршрута")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(route.author.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("@\(route.author.username)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.brandOlive)
                        }
                        .padding(12)
                        .background(Color.surfaceCream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Открыть профиль автора \(route.author.name)")

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
