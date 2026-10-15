import SwiftUI

struct ProfileView: View {
    @State private var showingEditor = false

    var body: some View {
        ProfileContent(isOwnProfile: true)
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
                    EditProfileView()
                }
            }
    }
}

struct MemberProfileView: View {
    var body: some View {
        ProfileContent(isOwnProfile: false)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 18) {
                    Image("RouteForest")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 96)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white, lineWidth: 3))
                        .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(isOwnProfile ? "Иван Петров" : "Алексей Смирнов")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(isOwnProfile ? "@ivan_atv" : "@kvadro_life")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(isOwnProfile ? "31 год, Санкт-Петербург" : "29 лет, Ленинградская область")
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

                VStack(spacing: 10) {
                    SectionTitle(title: "Техника", action: isOwnProfile ? "Редактировать" : nil)
                    ForEach(MockData.vehicles) { vehicle in
                        VehicleRow(vehicle: vehicle)
                    }
                }

                VStack(spacing: 10) {
                    SectionTitle(title: "Публичные маршруты", action: "Смотреть все")
                    ForEach(MockData.routes.filter { !$0.isPrivate }.prefix(3)) { route in
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

private struct VehicleRow: View {
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
                Text(vehicle.year)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("Основной", systemImage: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.brandOlive)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.surfaceCream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var firstName = "Иван"
    @State private var lastName = "Петров"
    @State private var username = "ivan_atv"
    @State private var age = 31
    @State private var city = "Санкт-Петербург"

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Image("RouteForest")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 104, height: 104)
                            .clipShape(Circle())
                        Button("Изменить фото", systemImage: "camera") { }
                    }
                    Spacer()
                }
            }

            Section("Основное") {
                TextField("Имя", text: $firstName)
                TextField("Фамилия", text: $lastName)
                TextField("Юзернейм", text: $username)
                    .textInputAutocapitalization(.never)
                Stepper("Возраст: \(age)", value: $age, in: 16...90)
                TextField("Город", text: $city)
            }

            Section("Моя техника") {
                ForEach(MockData.vehicles) { vehicle in
                    VehicleRow(vehicle: vehicle)
                }
                Button("Добавить квадроцикл", systemImage: "plus") { }
            }
        }
        .navigationTitle("Редактировать профиль")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить", systemImage: "checkmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
