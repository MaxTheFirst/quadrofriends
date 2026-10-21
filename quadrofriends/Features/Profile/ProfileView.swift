import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @StateObject private var routesViewModel = DemoRoutesViewModel()
    @EnvironmentObject private var apiSession: APISession
    @StateObject private var accountViewModel = AccountProfileViewModel()
    @AppStorage("sessionKind") private var sessionKind = "none"
    @State private var showingEditor = false
    @State private var showingDemoVehicles = false

    var body: some View {
        Group {
            if sessionKind == "demo" {
                ProfileContent(isOwnProfile: true, profile: profileStore.profile,
                               publicRoutes: routesViewModel.publicRoutes(for: nil, ownProfile: true),
                               edit: { showingEditor = true },
                               editVehicles: { showingDemoVehicles = true })
            } else if let account = accountViewModel.account {
                accountContent(account)
            } else if let accountError = accountViewModel.error {
                ContentUnavailableView {
                    Label("Не удалось загрузить профиль", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(accountError)
                } actions: {
                    Button("Повторить") { Task { await loadAccount() } }
                }
            } else {
                ProgressView("Загружаем профиль")
            }
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
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                if sessionKind == "demo" {
                    EditProfileView(profile: profileStore.profile) { updated in
                        profileStore.profile = updated
                    }
                } else if let account = accountViewModel.account {
                    AccountProfileEditorView(account: account) {
                        await loadAccount()
                    }
                }
            }
        }
        .sheet(isPresented: $showingDemoVehicles) {
            NavigationStack {
                EditProfileView(profile: profileStore.profile, mode: .vehicles) { updated in
                    profileStore.profile = updated
                }
            }
        }
        .task(id: apiSession.currentUserID) {
            if sessionKind != "demo" { await loadAccount() }
        }
    }

    private func loadAccount() async {
        await accountViewModel.load(from: RemoteAccountProfileDataSource(session: apiSession))
    }

    private func accountContent(_ account: AccountProfileDTO) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 18) {
                    ZStack {
                        Circle().fill(Color.brandOlive)
                        if let url = account.avatar?.thumbnailUrl {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                initials(account)
                            }
                        } else {
                            initials(account)
                        }
                    }
                    .frame(width: 96, height: 96)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 3))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(account.firstName) \(account.lastName)")
                            .font(.title2.weight(.bold))
                        Text("@\(account.username)")
                            .foregroundStyle(.secondary)
                        Text([account.birthYear.map { ageDescription($0) }, account.city].compactMap { $0 }.joined(separator: ", "))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 0) {
                    accountStat(account.stats.routeCount, label: "Маршруты")
                    Spacer()
                    accountStat(account.stats.followerCount, label: "Подписчики")
                    Spacer()
                    accountStat(account.stats.followingCount, label: "Подписки")
                }
                .padding()
                .background(Color.surfaceCream, in: RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Техника").font(.title3.bold())
                        Spacer()
                        NavigationLink("Редактировать") {
                            AccountVehiclesView(account: account) { await loadAccount() }
                        }
                        .font(.subheadline)
                    }
                    if account.vehicles.isEmpty {
                        ContentUnavailableView("Техника не добавлена", systemImage: "plus.circle", description: Text("Добавьте свой квадроцикл в профиле"))
                    } else {
                        ForEach(account.vehicles) { vehicle in
                            HStack(spacing: 12) {
                                Group {
                                    if let url = vehicle.image?.thumbnailUrl {
                                        AsyncImage(url: url) { image in
                                            image.resizable().scaledToFill()
                                        } placeholder: {
                                            Image(systemName: "car.side.fill")
                                        }
                                    } else {
                                        Image(systemName: "car.side.fill")
                                    }
                                }
                                .font(.title2)
                                .foregroundStyle(Color.brandOlive)
                                .frame(width: 58, height: 52)
                                .background(Color.brandOlive.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(vehicle.model).font(.subheadline.bold())
                                    Text("\(vehicle.year) г.").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if vehicle.isPrimary {
                                    Text("Основной").font(.caption).foregroundStyle(Color.brandOlive)
                                }
                            }
                            .padding(12)
                            .background(Color.surfaceCream, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }

                if !accountViewModel.publicRoutes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Публичные маршруты").font(.title3.bold())
                        ForEach(accountViewModel.publicRoutes.prefix(3)) { route in
                            NavigationLink {
                                ServerRouteDetailView(routeID: route.id)
                            } label: {
                                ServerRouteRow(route: route)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                signOutButton
            }
            .padding(20)
        }
        .appBackground()
        .refreshable { await loadAccount() }
    }

    private var signOutButton: some View {
        Button("Выйти", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
            Task {
                await accountViewModel.signOut(using: RemoteAccountProfileDataSource(session: apiSession))
                sessionKind = "none"
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private func ageDescription(_ birthYear: Int) -> String {
        let years = max(0, Calendar.current.component(.year, from: Date()) - birthYear)
        let suffix = years % 10 == 1 && years % 100 != 11 ? "год"
            : (2...4).contains(years % 10) && !(12...14).contains(years % 100) ? "года" : "лет"
        return "\(years) \(suffix)"
    }

    private func initials(_ account: AccountProfileDTO) -> some View {
        Text(String(account.firstName.prefix(1)) + String(account.lastName.prefix(1)))
            .font(.system(size: 30, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
    }

    private func accountStat(_ value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value.formatted()).font(.title3.weight(.bold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct MemberProfileView: View {
    let author: RouteAuthor?
    @EnvironmentObject private var profileStore: ProfileStore
    @StateObject private var routesViewModel = DemoRoutesViewModel()

    init(author: RouteAuthor? = nil) {
        self.author = author
    }

    var body: some View {
        ProfileContent(
            isOwnProfile: false,
            profile: profileStore.profile,
            author: author ?? routesViewModel.routes.first?.author,
            publicRoutes: routesViewModel.publicRoutes(
                for: author?.id ?? routesViewModel.routes.first?.author.id,
                ownProfile: false
            )
        ) { }
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
    let publicRoutes: [TrailRoute]
    let edit: () -> Void
    let editVehicles: () -> Void

    init(isOwnProfile: Bool, profile: UserProfile, author: RouteAuthor? = nil,
         publicRoutes: [TrailRoute],
         edit: @escaping () -> Void, editVehicles: @escaping () -> Void = { }) {
        self.isOwnProfile = isOwnProfile
        self.profile = profile
        self.author = author
        self.publicRoutes = publicRoutes
        self.edit = edit
        self.editVehicles = editVehicles
    }

    private var vehicles: [Vehicle] {
        isOwnProfile ? profile.vehicles : (author?.vehicles ?? [])
    }

    private func ageDescription(_ birthYear: Int) -> String {
        let years = max(0, Calendar.current.component(.year, from: Date()) - birthYear)
        let suffix = years % 10 == 1 && years % 100 != 11 ? "год"
            : (2...4).contains(years % 10) && !(12...14).contains(years % 100) ? "года" : "лет"
        return "\(years) \(suffix)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 18) {
                    Group {
                        if isOwnProfile, let data = profile.avatarData, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Image(isOwnProfile ? "RouteForest" : (author?.avatarImage ?? "RouteForest"))
                                .resizable().scaledToFill()
                        }
                    }
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
                        Text(isOwnProfile
                             ? "\(ageDescription(profile.birthYear)), \(profile.city)"
                             : [(author?.birthYear).map(ageDescription), author?.city].compactMap { $0 }.joined(separator: ", "))
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
                                Button("Редактировать", action: editVehicles)
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
                if isOwnProfile {
                    Button("Выйти", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        UserDefaults.standard.set("none", forKey: "sessionKind")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
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
            Group {
                if let data = vehicle.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(vehicle.imageName).resizable().scaledToFill()
                }
            }
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
