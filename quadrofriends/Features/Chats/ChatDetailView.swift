import SwiftUI
import MapKit

struct ChatDetailView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var locationStore: ChatLocationSharingStore
    let chat: ChatPreview
    @State private var draft = ""
    @State private var messages: [ChatMessage]
    @State private var showingLocationWarning = false
    @State private var showingLocationMap = false

    private var activeShares: [ChatLiveLocation] { locationStore.shares(in: chat.id) }

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
            ToolbarItem(placement: .topBarTrailing) {
                Button("Поделиться геопозицией", systemImage: "location.circle") {
                    showingLocationWarning = true
                }
                .labelStyle(.iconOnly)
                .disabled(locationStore.isSharing(in: chat.id) || locationStore.pendingChatIDs.contains(chat.id))
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    MemberProfileView()
                } label: {
                    Image(systemName: "person.crop.circle")
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !activeShares.isEmpty {
                ChatLocationStatusBanner(
                    shares: activeShares,
                    openMap: { showingLocationMap = true },
                    stopSharing: { locationStore.stopSharing(in: chat.id) }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.warmBackground)
            } else if locationStore.pendingChatIDs.contains(chat.id) {
                Label("Определяем ваше местоположение…", systemImage: "location")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(Color.warmBackground)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(alignment: .center, spacing: 8) {
                Menu {
                    Button("Поделиться геопозицией", systemImage: "location.fill") {
                        showingLocationWarning = true
                    }
                    .disabled(locationStore.isSharing(in: chat.id) || locationStore.pendingChatIDs.contains(chat.id))
                    Button("Поделиться маршрутом", systemImage: "map") { }
                    Button("Добавить фото", systemImage: "photo") { }
                } label: {
                    Image(systemName: "paperclip")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }

                TextField("Сообщение", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "mic.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 9)
            .background(.regularMaterial)
        }
        .sheet(isPresented: $showingLocationWarning) {
            ChatLocationConsentView(chatTitle: chat.title) {
                locationStore.startSharing(in: chat.id, profile: profileStore.profile)
            }
            .presentationDetents([.height(520), .large])
        }
        .sheet(isPresented: $showingLocationMap) {
            NavigationStack {
                ChatLiveLocationMapView(chatTitle: chat.title, shares: activeShares)
            }
        }
        .alert("Геопозиция", isPresented: $locationStore.showingError) {
            Button("Понятно", role: .cancel) { }
        } message: {
            Text(locationStore.errorMessage)
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
