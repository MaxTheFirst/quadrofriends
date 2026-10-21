import MapKit
import SwiftUI

struct ChatLocationConsentView: View {
    let chatTitle: String
    /// Нет сессии backend: передача видна только на этом устройстве.
    var isLocalOnly = true
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

                    if isLocalOnly {
                        Label("В демо-режиме передача видна только на этом устройстве.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
        Group {
            if share.isMine {
                AvatarView(imageName: share.avatarImage, initials: share.initials, size: 42)
                    .overlay(Circle().stroke(Color.brandOlive, lineWidth: 4))
            } else {
                ZStack {
                    Circle().fill(Color.brandOrange)
                    Text(share.initials)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }
                .frame(width: 42, height: 42)
                .overlay(Circle().stroke(.white, lineWidth: 3))
            }
        }
            .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
            .accessibilityLabel("\(share.name), делится геопозицией")
    }
}

struct ChatLocationParticipantsView: View {
    let chatID: String
    @ObservedObject var locationStore: ChatLocationSharingStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(locationStore.shares(in: chatID)) { share in
                HStack(spacing: 12) {
                    ChatLiveLocationAvatar(share: share)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(share.isMine ? "Вы" : share.name).font(.headline)
                        Text("Делится геопозицией").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Участники")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } }
            }
        }
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
