import SwiftUI
import MapKit

struct ChatsView: View {
    @State private var query = ""
    @State private var showingComposer = false

    private var chats: [ChatPreview] {
        guard !query.isEmpty else { return MockData.chats }
        return MockData.chats.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List(chats) { chat in
            NavigationLink {
                ChatDetailView(chat: chat)
            } label: {
                ChatRow(chat: chat)
            }
            .listRowBackground(Color.warmBackground)
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("Чаты")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Поиск по чатам и пользователям")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Новое сообщение", systemImage: "square.and.pencil") {
                    showingComposer = true
                }
                .labelStyle(.iconOnly)
            }
        }
        .sheet(isPresented: $showingComposer) {
            NavigationStack {
                NewChatView()
            }
        }
    }
}

private struct ChatRow: View {
    let chat: ChatPreview

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(imageName: chat.avatarImage, initials: chat.initials, size: 54)
                if chat.sharesLocation {
                    Image(systemName: "location.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.white)
                        .padding(5)
                        .background(Color.brandOlive, in: Circle())
                        .overlay(Circle().stroke(Color.warmBackground, lineWidth: 2))
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(chat.title)
                    .font(.headline)
                HStack(spacing: 4) {
                    if chat.sharesLocation {
                        Image(systemName: "location.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.brandOlive)
                    }
                    Text(chat.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 8) {
                Text(chat.time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if chat.unread > 0 {
                    Text("\(chat.unread)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.white)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Color.brandOlive, in: Circle())
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct ChatDetailView: View {
    let chat: ChatPreview
    @State private var draft = ""
    @State private var messages: [ChatMessage]

    init(chat: ChatPreview) {
        self.chat = chat
        _messages = State(initialValue: [
            ChatMessage(author: "Иван Петров", isMine: false, time: "09:15", kind: .text("Кто на покатушку в эти выходные?")),
            ChatMessage(author: "Вы", isMine: true, time: "09:17", kind: .text("Я в деле! Куда едем?")),
            ChatMessage(author: "Алексей Смирнов", isMine: false, time: "09:18", kind: .text("Вот координаты старта")),
            ChatMessage(author: "Алексей Смирнов", isMine: false, time: "09:18", kind: .location)
        ])
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                Text("Сегодня")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)

                ForEach(messages) { message in
                    MessageBubble(message: message)
                }
            }
            .padding()
        }
        .appBackground()
        .navigationTitle(chat.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Позвонить", systemImage: "phone") { }
                    .labelStyle(.iconOnly)
                NavigationLink {
                    MemberProfileView()
                } label: {
                    Image(systemName: "person.crop.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(alignment: .bottom, spacing: 10) {
                Menu {
                    Button("Отправить геопозицию", systemImage: "location.fill") {
                        messages.append(ChatMessage(author: "Вы", isMine: true, time: "Сейчас", kind: .location))
                    }
                    Button("Поделиться маршрутом", systemImage: "map") { }
                    Button("Добавить фото", systemImage: "photo") { }
                } label: {
                    Image(systemName: "paperclip")
                        .font(.title3)
                }

                TextField("Сообщение", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color(.secondarySystemBackground), in: Capsule())

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "mic.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 9)
            .background(.regularMaterial)
        }
    }

    private func sendMessage() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(ChatMessage(author: "Вы", isMine: true, time: "Сейчас", kind: .text(text)))
        draft = ""
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isMine { Spacer(minLength: 46) }
            VStack(alignment: .leading, spacing: 5) {
                if !message.isMine {
                    Text(message.author)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.brandOlive)
                }
                switch message.kind {
                case .text(let text):
                    Text(text)
                        .font(.body)
                case .location:
                    SharedLocationCard()
                }
                HStack(spacing: 3) {
                    Spacer()
                    Text(message.time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if message.isMine {
                        Image(systemName: "checkmark")
                            .font(.caption2)
                            .foregroundStyle(Color.brandOlive)
                    }
                }
            }
            .padding(message.kind.isLocation ? 6 : 11)
            .background(message.isMine ? Color.brandOlive.opacity(0.14) : Color.surfaceCream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if !message.isMine { Spacer(minLength: 46) }
        }
    }
}

private extension ChatMessageKind {
    var isLocation: Bool {
        if case .location = self { return true }
        return false
    }
}

private struct SharedLocationCard: View {
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 59.980, longitude: 30.262),
            span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
        )
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Map(position: $camera, interactionModes: []) {
                Marker("Старт", coordinate: CLLocationCoordinate2D(latitude: 59.980, longitude: 30.262))
                    .tint(Color.brandOlive)
            }
            .frame(width: 245, height: 130)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Label("Координаты старта", systemImage: "location.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.brandOlive)
            Text("59.980, 30.262")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct NewChatView: View {
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
