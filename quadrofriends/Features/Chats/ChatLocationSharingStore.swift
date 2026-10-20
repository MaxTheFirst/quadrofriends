import Combine
import CoreLocation
import Foundation

@MainActor
final class ChatLocationSharingStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    /// Сервер принимает позиции не чаще одного раза в 5 секунд на передачу.
    private static let positionInterval: TimeInterval = 5
    private static let shareDuration: TimeInterval = 3600

    @Published private(set) var sharesByChat: [String: [ChatLiveLocation]] = [:]
    @Published private(set) var pendingChatIDs: Set<String> = []
    @Published var showingError = false
    @Published var errorMessage = ""

    private let manager = CLLocationManager()
    private var pendingProfiles: [String: UserProfile] = [:]
    private let ownUserID = "me"

    // Сервер: без сессии передача остаётся только на этом устройстве.
    private var api: ChatsAPI?
    private var currentUserID: String?
    private var realtimeSubscriptions = Set<AnyCancellable>()
    /// ID собственной передачи на сервере для каждого чата.
    private var remoteShareIDs: [String: String] = [:]
    private var lastPositionSentAt = Date.distantPast

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 20
    }

    /// Подключает сервер и WebSocket после входа; `nil` — локальный и демо-режим.
    func connect(session: APISession?, realtime: RealtimeClient?) {
        realtimeSubscriptions.removeAll()
        api = session.map { ChatsAPI(client: $0.client) }
        currentUserID = session?.currentUserID

        guard api != nil else {
            remoteShareIDs.removeAll()
            sharesByChat = sharesByChat.mapValues { $0.filter { $0.isDemo || $0.isMine } }
            return
        }

        realtime?.events
            .sink { [weak self] event in self?.apply(event) }
            .store(in: &realtimeSubscriptions)
        realtime?.connectionRestored
            .sink { [weak self] in self?.refreshVisibleShares() }
            .store(in: &realtimeSubscriptions)
        refreshVisibleShares()
    }

    func shares(in chatID: String) -> [ChatLiveLocation] {
        (sharesByChat[chatID] ?? []).filter { $0.expiresAt > Date() }
    }

    var visibleShares: [ChatLiveLocation] {
        var latestByUser: [String: ChatLiveLocation] = [:]
        for share in sharesByChat.values.flatMap({ $0 }) where share.expiresAt > Date() {
            if let previous = latestByUser[share.userID], previous.updatedAt > share.updatedAt {
                continue
            }
            latestByUser[share.userID] = share
        }
        return latestByUser.values.sorted { $0.name < $1.name }
    }

    func isSharing(in chatID: String) -> Bool {
        shares(in: chatID).contains(where: \.isMine)
    }

    func startSharing(in chatID: String, profile: UserProfile) {
        guard !isSharing(in: chatID), !pendingChatIDs.contains(chatID) else { return }
        pendingProfiles[chatID] = profile
        pendingChatIDs.insert(chatID)

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            failPendingShares("Разрешите доступ к геопозиции в настройках iPhone, чтобы делиться ею в чате.")
        @unknown default:
            failPendingShares("Не удалось получить доступ к геопозиции.")
        }
    }

    func stopSharing(in chatID: String) {
        if let shareID = remoteShareIDs[chatID], let api {
            Task { try? await api.stopLocationShare(shareID: shareID) }
        }
        removeOwnShare(in: chatID)
    }

    func removeExpiredShares() {
        sharesByChat = sharesByChat.mapValues { $0.filter { $0.expiresAt > Date() } }
        stopLocationUpdatesIfIdle()
    }

    func setDemoDataEnabled(_ enabled: Bool) {
        for chatID in sharesByChat.keys {
            sharesByChat[chatID]?.removeAll { $0.isDemo }
        }
        guard enabled else { return }
        sharesByChat["wolves", default: []].append(
            ChatLiveLocation(
                id: "demo-wolves-alexey",
                chatID: "wolves",
                userID: "demo-alexey",
                name: "Алексей",
                initials: "АС",
                avatarImage: nil,
                coordinate: CLLocationCoordinate2D(latitude: 59.980, longitude: 30.262),
                updatedAt: Date(),
                expiresAt: Date().addingTimeInterval(Self.shareDuration),
                isMine: false,
                isDemo: true
            )
        )
    }

    // MARK: - Сервер

    /// Передачи участников конкретного чата — для плашки над сообщениями.
    func refreshShares(in chatID: String) {
        guard let api else { return }
        Task { [weak self] in
            guard let page = try? await api.chatLocationShares(chatID: chatID) else { return }
            self?.replaceRemoteShares(page.items, inChats: [chatID])
        }
    }

    /// Все доступные передачи: после входа и после переподключения WebSocket.
    private func refreshVisibleShares() {
        guard let api else { return }
        Task { [weak self] in
            guard let page = try? await api.visibleLocationShares() else { return }
            guard let self else { return }
            let chatIDs = Set(self.sharesByChat.keys).union(page.items.flatMap(\.chatIds))
            self.replaceRemoteShares(page.items, inChats: chatIDs)
        }
    }

    private func replaceRemoteShares(_ items: [VisibleLocationShareDTO], inChats chatIDs: Set<String>) {
        for chatID in chatIDs {
            let incoming = items.filter { $0.chatIds.contains(chatID) }
            var updated = (sharesByChat[chatID] ?? []).filter { $0.isDemo || $0.isMine }

            for dto in incoming where dto.owner.id != currentUserID {
                updated.append(liveLocation(from: dto, chatID: chatID, isMine: false))
            }
            // Своя передача, начатая до перезапуска приложения: продолжаем отправлять позиции.
            if !updated.contains(where: \.isMine),
               let own = incoming.first(where: { $0.owner.id == currentUserID }) {
                remoteShareIDs[chatID] = own.id
                updated.append(liveLocation(from: own, chatID: chatID, isMine: true))
                resumeLocationUpdatesIfAuthorized()
            }
            sharesByChat[chatID] = updated
        }
    }

    private func apply(_ event: RealtimeEvent) {
        switch event.payload {
        case .locationShareUpdated(let dto):
            guard dto.owner.id != currentUserID else { return }
            for chatID in dto.chatIds {
                var shares = sharesByChat[chatID] ?? []
                let share = liveLocation(from: dto, chatID: chatID, isMine: false)
                if let index = shares.firstIndex(where: { $0.id == dto.id }) {
                    shares[index] = share
                } else {
                    shares.append(share)
                }
                sharesByChat[chatID] = shares
            }
        case .locationShareStopped(let shareID):
            // Свою передачу могли остановить с другого устройства.
            for (chatID, ownID) in remoteShareIDs where ownID == shareID {
                removeOwnShare(in: chatID)
            }
            for chatID in sharesByChat.keys {
                sharesByChat[chatID]?.removeAll { !$0.isMine && $0.id == shareID }
            }
        default:
            break
        }
    }

    private func createRemoteShare(in chatID: String, location: CLLocation, expiresAt: Date) {
        guard let api else { return }
        Task { [weak self] in
            do {
                let share = try await api.createLocationShare(
                    chatID: chatID,
                    expiresAt: expiresAt,
                    idempotencyKey: UUID().uuidString
                )
                guard let self, self.isSharing(in: chatID) else {
                    // Пользователь успел остановить передачу, пока шёл запрос.
                    try? await api.stopLocationShare(shareID: share.id)
                    return
                }
                self.remoteShareIDs[chatID] = share.id
                _ = try? await api.sendPosition(shareID: share.id, Self.position(from: location))
            } catch {
                guard let self else { return }
                self.removeOwnShare(in: chatID)
                self.errorMessage = "Не удалось начать передачу геопозиции. \(error.localizedDescription)"
                self.showingError = true
            }
        }
    }

    private func sendPositionIfNeeded(_ location: CLLocation) {
        guard let api, !remoteShareIDs.isEmpty,
              Date().timeIntervalSince(lastPositionSentAt) >= Self.positionInterval else { return }
        lastPositionSentAt = Date()
        let position = Self.position(from: location)
        for shareID in Set(remoteShareIDs.values) {
            Task { _ = try? await api.sendPosition(shareID: shareID, position) }
        }
    }

    private func liveLocation(from dto: VisibleLocationShareDTO, chatID: String, isMine: Bool) -> ChatLiveLocation {
        ChatLiveLocation(
            id: dto.id,
            chatID: chatID,
            userID: isMine ? ownUserID : dto.owner.id,
            name: isMine ? "Вы" : dto.owner.displayName,
            initials: dto.owner.initials,
            avatarImage: nil,
            coordinate: dto.lastPosition.coordinate.coordinate,
            updatedAt: dto.lastPosition.recordedAt,
            expiresAt: dto.expiresAt,
            isMine: isMine,
            isDemo: false
        )
    }

    private static func position(from location: CLLocation) -> LocationPositionWriteDTO {
        LocationPositionWriteDTO(
            coordinate: CoordinateDTO(location.coordinate),
            accuracyM: max(location.horizontalAccuracy, 0),
            recordedAt: location.timestamp
        )
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard !pendingChatIDs.isEmpty else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            failPendingShares("Разрешите доступ к геопозиции в настройках iPhone, чтобы делиться ею в чате.")
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        removeExpiredShares()
        let now = Date()

        for (chatID, profile) in pendingProfiles {
            let initials = String(profile.firstName.prefix(1)) + String(profile.lastName.prefix(1))
            let expiresAt = now.addingTimeInterval(Self.shareDuration)
            sharesByChat[chatID, default: []].append(
                ChatLiveLocation(
                    id: UUID().uuidString,
                    chatID: chatID,
                    userID: ownUserID,
                    name: "Вы",
                    initials: initials,
                    avatarImage: nil,
                    coordinate: location.coordinate,
                    updatedAt: now,
                    expiresAt: expiresAt,
                    isMine: true,
                    isDemo: false
                )
            )
            scheduleExpiration(in: chatID)
            createRemoteShare(in: chatID, location: location, expiresAt: expiresAt)
        }
        pendingProfiles.removeAll()
        pendingChatIDs.removeAll()

        for chatID in sharesByChat.keys {
            guard let index = sharesByChat[chatID]?.firstIndex(where: { $0.isMine }) else { continue }
            sharesByChat[chatID]?[index].coordinate = location.coordinate
            sharesByChat[chatID]?[index].updatedAt = now
        }
        sendPositionIfNeeded(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if !pendingChatIDs.isEmpty {
            failPendingShares("Не удалось определить местоположение. Попробуйте ещё раз.")
        }
    }

    // MARK: - Внутреннее

    private func removeOwnShare(in chatID: String) {
        remoteShareIDs.removeValue(forKey: chatID)
        pendingProfiles.removeValue(forKey: chatID)
        pendingChatIDs.remove(chatID)
        sharesByChat[chatID]?.removeAll { $0.isMine }
        stopLocationUpdatesIfIdle()
    }

    private func stopLocationUpdatesIfIdle() {
        if !sharesByChat.values.flatMap({ $0 }).contains(where: \.isMine) && pendingChatIDs.isEmpty {
            manager.stopUpdatingLocation()
        }
    }

    private func resumeLocationUpdatesIfAuthorized() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    private func scheduleExpiration(in chatID: String) {
        guard let share = sharesByChat[chatID]?.first(where: \.isMine) else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.shareDuration))
            guard let self,
                  self.sharesByChat[chatID]?.contains(where: { $0.id == share.id }) == true else { return }
            self.stopSharing(in: chatID)
        }
    }

    private func failPendingShares(_ message: String) {
        pendingProfiles.removeAll()
        pendingChatIDs.removeAll()
        errorMessage = message
        showingError = true
    }
}
