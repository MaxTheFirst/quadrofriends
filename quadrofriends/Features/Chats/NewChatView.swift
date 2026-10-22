import SwiftUI

struct ChatCreateRequest: Encodable {
    let kind: String
    let participantUserIds: [String]
    let title: String?
}

struct NewChatView: View {
    @Environment(\.dismiss) private var dismiss
    private let hasAccount: Bool
    let onCreated: (ChatPreview) -> Void
    @StateObject private var viewModel: NewChatViewModel
    @State private var query = ""
    @State private var selected: Set<String> = []
    @State private var isGroup = false
    @State private var groupTitle = ""

    init(session: APISession? = nil, onCreated: @escaping (ChatPreview) -> Void = { _ in }) {
        hasAccount = session != nil
        self.onCreated = onCreated
        _viewModel = StateObject(wrappedValue: NewChatViewModel(
            people: session.map(RemoteChatPeopleDataSource.init(session:))
        ))
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^@", with: "", options: .regularExpression)
    }

    private var canCreate: Bool {
        if isGroup { return selected.count >= 2 && !groupTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return selected.count == 1
    }

    var body: some View {
        List {
            if hasAccount {
                Section {
                    Toggle("Создать группу", isOn: $isGroup)
                    if isGroup { TextField("Название группы", text: $groupTitle) }
                }
                Section("Пользователи") {
                    if normalizedQuery.isEmpty {
                        Text("Введите имя или @username").foregroundStyle(.secondary)
                    } else if viewModel.isLoading {
                        ProgressView("Ищем пользователей")
                    } else if let error = viewModel.error {
                        Text(error).foregroundStyle(.red)
                        Button("Повторить") { Task { await search() } }
                    } else if viewModel.users.isEmpty {
                        Text("Пользователи не найдены").foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.users, id: \.id) { user in
                            Button { choose(user.id) } label: {
                                HStack(spacing: 12) {
                                    AvatarView(imageName: nil, initials: user.initials, size: 42)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(user.displayName).foregroundStyle(.primary)
                                        Text("@\(user.username)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    EmptySelectionCircle(selected: selected.contains(user.id))
                                }
                            }
                        }
                    }
                }
                if let error = viewModel.error, !viewModel.users.isEmpty {
                    Section { Text(error).foregroundStyle(.red) }
                }
            } else {
                Section("Деморежим") {
                    Text("Поиск людей доступен после входа в аккаунт")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .searchable(text: $query, prompt: "Имя или @username")
        .navigationTitle("Новое сообщение")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Начать", systemImage: "arrow.right") { Task { await createChat() } }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCreate || viewModel.isCreating || !hasAccount)
            }
        }
        .task(id: normalizedQuery) {
            guard hasAccount else { return }
            if !normalizedQuery.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            await search()
        }
    }

    private func choose(_ userID: String) {
        if isGroup {
            if selected.contains(userID) { selected.remove(userID) } else { selected.insert(userID) }
        } else {
            selected = selected.contains(userID) ? [] : [userID]
        }
    }

    private func search() async {
        await viewModel.search(query: normalizedQuery)
    }

    private func createChat() async {
        guard canCreate else { return }
        let title = isGroup ? groupTitle.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        if let chat = await viewModel.createChat(participantIDs: Array(selected), groupTitle: title) {
            onCreated(chat)
        }
    }
}
