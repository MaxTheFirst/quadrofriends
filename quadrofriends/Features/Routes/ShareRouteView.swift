import SwiftUI

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
