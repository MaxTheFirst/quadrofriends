import SwiftUI

struct ChatCreateRequest: Encodable {
    let kind: String
    let participantUserIds: [String]
    let title: String?
}

struct NewChatView: View {
    @Environment(\.dismiss) private var dismiss
    let session: APISession?
    let onCreated: (ChatPreview) -> Void
    @State private var query = ""
    @State private var users: [UserSummaryDTO] = []
    @State private var selected: Set<String> = []
    @State private var isGroup = false
    @State private var groupTitle = ""
    @State private var isLoading = false
    @State private var isCreating = false
    @State private var error: String?

    init(session: APISession? = nil, onCreated: @escaping (ChatPreview) -> Void = { _ in }) {
        self.session = session
        self.onCreated = onCreated
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
            if session != nil {
                Section {
                    Toggle("Создать группу", isOn: $isGroup)
                    if isGroup { TextField("Название группы", text: $groupTitle) }
                }
                Section("Пользователи") {
                    if normalizedQuery.isEmpty {
                        Text("Введите имя или @username").foregroundStyle(.secondary)
                    } else if isLoading {
                        ProgressView("Ищем пользователей")
                    } else if let error {
                        Text(error).foregroundStyle(.red)
                        Button("Повторить") { Task { await search() } }
                    } else if users.isEmpty {
                        Text("Пользователи не найдены").foregroundStyle(.secondary)
                    } else {
                        ForEach(users, id: \.id) { user in
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
                if let error, !users.isEmpty {
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
                    .disabled(!canCreate || isCreating || session == nil)
            }
        }
        .task(id: normalizedQuery) {
            guard session != nil else { return }
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
        guard let session else { return }
        guard !normalizedQuery.isEmpty else {
            users = []
            error = nil
            return
        }
        isLoading = true
        error = nil
        do {
            let page: Page<UserSummaryDTO> = try await session.client.send(APIRequest(
                method: .get,
                path: "users",
                query: [URLQueryItem(name: "query", value: normalizedQuery), URLQueryItem(name: "limit", value: "50")]
            ))
            guard !Task.isCancelled else { return }
            users = page.items.filter { $0.id != session.currentUserID }
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func createChat() async {
        guard let session, canCreate else { return }
        isCreating = true
        error = nil
        do {
            let chat: ChatSummaryDTO = try await session.client.send(APIRequest(
                method: .post,
                path: "chats",
                body: ChatCreateRequest(
                    kind: isGroup ? "group" : "direct",
                    participantUserIds: Array(selected),
                    title: isGroup ? groupTitle.trimmingCharacters(in: .whitespacesAndNewlines) : nil
                ),
                idempotencyKey: UUID().uuidString
            ))
            onCreated(ChatPreview(
                id: chat.id,
                title: chat.title,
                subtitle: "Нет сообщений",
                time: "Сейчас",
                unread: chat.unreadCount,
                avatarImage: nil,
                initials: String(chat.title.prefix(2)).uppercased(),
                avatarURL: chat.avatar?.thumbnailUrl,
                sharesLocation: chat.sharesLocation
            ))
        } catch {
            self.error = error.localizedDescription
        }
        isCreating = false
    }
}
