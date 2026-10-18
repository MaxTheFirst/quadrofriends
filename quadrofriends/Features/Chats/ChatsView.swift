import SwiftUI
import MapKit

struct ChatsView: View {
    @EnvironmentObject private var locationStore: ChatLocationSharingStore
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
                ChatRow(chat: chat, sharesLocation: !locationStore.shares(in: chat.id).isEmpty)
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
    let sharesLocation: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(imageName: chat.avatarImage, initials: chat.initials, size: 54)
                if sharesLocation {
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
                    if sharesLocation {
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
