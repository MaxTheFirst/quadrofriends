import SwiftUI

struct NewChatView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected: Set<String> = []

    private let users = [
        ("@atv_rider", "Иван Петров", "ИП"),
        ("@kvadro_life", "Алексей Смирнов", "АС"),
        ("@mud_queen", "Мария Иванова", "МИ"),
        ("@north_trail", "Дмитрий Орлов", "ДО")
    ]

    var body: some View {
        List {
            Section {
                Button("Создать группу", systemImage: "person.3.fill") { }
            }
            Section("Пользователи") {
                ForEach(users, id: \.0) { user in
                    Button {
                        if selected.contains(user.0) { selected.remove(user.0) } else { selected.insert(user.0) }
                    } label: {
                        HStack(spacing: 12) {
                            AvatarView(imageName: nil, initials: user.2, size: 42)
                            VStack(alignment: .leading) {
                                Text(user.1)
                                    .foregroundStyle(.primary)
                                Text(user.0)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            EmptySelectionCircle(selected: selected.contains(user.0))
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Юзернейм")
        .navigationTitle("Новое сообщение")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Начать", systemImage: "arrow.right") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .disabled(selected.isEmpty)
            }
        }
    }
}
