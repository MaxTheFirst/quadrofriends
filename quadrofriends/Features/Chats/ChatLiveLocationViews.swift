import MapKit
import SwiftUI

struct ChatLocationStatusBanner: View {
    let shares: [ChatLiveLocation]
    let openMap: () -> Void
    let stopSharing: () -> Void

    private var ownShare: ChatLiveLocation? { shares.first(where: \.isMine) }
    private var otherShares: [ChatLiveLocation] { shares.filter { !$0.isMine } }

    private var title: String {
        if ownShare != nil {
            return otherShares.isEmpty
                ? "Вы делитесь геопозицией"
                : "Вы и другие участники делитесь геопозицией"
        }
        if otherShares.count == 1 {
            return "\(otherShares[0].name) делится геопозицией"
        }
        return "\(otherShares.count) участников делятся геопозицией"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "location.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 34, height: 34)
                    .background(Color.brandOlive, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(ownShare == nil
                         ? "Местоположение видно участникам этого чата"
                         : "Ваше местоположение видно всем участникам чата")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if shares.contains(where: \.isDemo) {
                    Text("Демо")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.brandOlive)
                }
            }

            HStack(spacing: 16) {
                Button("Открыть карту", systemImage: "map", action: openMap)
                if ownShare != nil {
                    Button("Остановить", systemImage: "stop.circle", action: stopSharing)
                        .foregroundStyle(.red)
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.plain)
            .padding(.leading, 44)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.brandOlive.opacity(0.11), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ChatLocationConsentView: View {
    let chatTitle: String
    let startSharing: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(Color.brandOlive)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)

                    Text("Поделиться местоположением?")
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Все участники чата «\(chatTitle)» смогут видеть ваше текущее местоположение на карте.")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)

                    Label("Передача автоматически закончится через 1 час. Вы можете остановить её раньше в любой момент.", systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Label("Пока сервер не подключён, передача видна только на этом устройстве.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                    startSharing()
                } label: {
                    Text("Начать передачу")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FilledActionButtonStyle())
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(.regularMaterial)
            }
            .navigationTitle("Геопозиция")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Отмена", action: { dismiss() })
                }
            }
        }
    }
}

struct ChatLiveLocationAvatar: View {
    let share: ChatLiveLocation

    var body: some View {
        AvatarView(imageName: share.avatarImage, initials: share.initials, size: 42)
            .overlay(Circle().stroke(Color.brandOlive, lineWidth: 3))
            .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
            .accessibilityLabel("\(share.name), делится геопозицией")
    }
}

struct ChatLiveLocationMapView: View {
    let chatTitle: String
    let shares: [ChatLiveLocation]
    @Environment(\.dismiss) private var dismiss
    @State private var camera: MapCameraPosition

    init(chatTitle: String, shares: [ChatLiveLocation]) {
        self.chatTitle = chatTitle
        self.shares = shares
        let center = shares.first?.coordinate
            ?? CLLocationCoordinate2D(latitude: 59.980, longitude: 30.262)
        _camera = State(initialValue: .region(
            MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
            )
        ))
    }

    var body: some View {
        Map(position: $camera) {
            ForEach(shares) { share in
                Annotation(share.name, coordinate: share.coordinate) {
                    ChatLiveLocationAvatar(share: share)
                }
            }
        }
        .mapControls { MapCompass() }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(shares) { share in
                    HStack(spacing: 10) {
                        AvatarView(imageName: share.avatarImage, initials: share.initials, size: 32)
                        Text(share.isMine ? "Вы делитесь геопозицией" : "\(share.name) делится геопозицией")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        if share.isDemo {
                            Text("Демо")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .padding()
        }
        .navigationTitle(chatTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Готово", action: { dismiss() })
            }
        }
    }
}
