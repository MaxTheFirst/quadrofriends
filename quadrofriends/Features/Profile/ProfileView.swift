import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var vkAuth: VKAuthManager
    @AppStorage("sessionKind") private var sessionKind = "none"
    @State private var showingEditor = false

    var body: some View {
        ProfileContent(isOwnProfile: true, profile: profileStore.profile) {
            showingEditor = true
        }
        .navigationTitle("Мой профиль")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Редактировать", systemImage: "pencil") {
                    showingEditor = true
                }
                .labelStyle(.iconOnly)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Вернуться к экрану входа", systemImage: "rectangle.portrait.and.arrow.right") {
                        vkAuth.signOut()
                        sessionKind = "none"
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                EditProfileView(profile: profileStore.profile) { updated in
                    profileStore.profile = updated
                }
            }
        }
    }
}

struct MemberProfileView: View {
    let author: RouteAuthor

    init(author: RouteAuthor = MockData.alex) {
        self.author = author
    }

    var body: some View {
        ProfileContent(isOwnProfile: false, profile: .sample, author: author) { }
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Ещё", systemImage: "ellipsis") { }
                        .labelStyle(.iconOnly)
                }
            }
    }
}

private struct ProfileContent: View {
    let isOwnProfile: Bool
    let profile: UserProfile
    let author: RouteAuthor?
    let edit: () -> Void

    init(isOwnProfile: Bool, profile: UserProfile, author: RouteAuthor? = nil, edit: @escaping () -> Void) {
        self.isOwnProfile = isOwnProfile
        self.profile = profile
        self.author = author
        self.edit = edit
    }

    private var vehicles: [Vehicle] {
        isOwnProfile ? profile.vehicles : (author?.vehicles ?? [])
    }

    private var publicRoutes: [TrailRoute] {
        let routes = MockData.routes.filter { !$0.isPrivate }
        return isOwnProfile ? Array(routes.prefix(3)) : routes.filter { $0.author.id == author?.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 18) {
                    Image(isOwnProfile ? "RouteForest" : (author?.avatarImage ?? "RouteForest"))
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 96)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white, lineWidth: 3))
                        .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(isOwnProfile ? "\(profile.firstName) \(profile.lastName)" : (author?.name ?? ""))
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(isOwnProfile ? "@\(profile.username)" : "@\(author?.username ?? "")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(isOwnProfile ? "\(profile.birthYear) г. р., \(profile.city)" : "\(author?.birthYear ?? 0) г. р., \(author?.city ?? "")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    ProfileStat(value: "18", label: "Маршруты")
                    Spacer()
                    ProfileStat(value: "112", label: "Подписчики")
                    Spacer()
                    ProfileStat(value: "64", label: "Подписки")
                }
                .padding()
                .background(Color.surfaceCream, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                if !isOwnProfile {
                    HStack(spacing: 10) {
                        Button("Подписаться", systemImage: "person.badge.plus") { }
                            .buttonStyle(FilledActionButtonStyle())
                        Button("Написать", systemImage: "message.fill") { }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.brandOlive.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                if isOwnProfile || !vehicles.isEmpty {
                    VStack(spacing: 10) {
                        HStack {
                            Text("Техника")
                                .font(.title3)
                                .fontWeight(.bold)
                            Spacer()
                            if isOwnProfile {
                                Button("Редактировать", action: edit)
                                    .font(.subheadline)
                            }
                        }
                        if isOwnProfile && profile.vehicles.isEmpty {
                            ContentUnavailableView("Техника не добавлена", systemImage: "plus.circle", description: Text("Добавьте свой квадроцикл в профиле"))
                        }
                        ForEach(vehicles) { vehicle in
                            VehicleRow(vehicle: vehicle)
                        }
                    }
                }

                VStack(spacing: 10) {
                    SectionTitle(title: "Публичные маршруты", action: "Смотреть все")
                    ForEach(publicRoutes) { route in
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
    }
}

private struct ProfileStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct VehicleRow: View {
    let vehicle: Vehicle

    var body: some View {
        HStack(spacing: 12) {
            Image(vehicle.imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 112, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(vehicle.model)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(String(vehicle.year))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if vehicle.isPrimary {
                    Label("Основной", systemImage: "checkmark.seal.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.brandOlive)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(Color.surfaceCream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
