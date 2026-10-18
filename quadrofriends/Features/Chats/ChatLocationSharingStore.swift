import Combine
import CoreLocation
import Foundation

@MainActor
final class ChatLocationSharingStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var sharesByChat: [String: [ChatLiveLocation]] = [:]
    @Published private(set) var pendingChatIDs: Set<String> = []
    @Published var showingError = false
    @Published var errorMessage = ""

    private let manager = CLLocationManager()
    private var pendingProfiles: [String: UserProfile] = [:]
    private let ownUserID = "me"

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 20
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
        pendingProfiles.removeValue(forKey: chatID)
        pendingChatIDs.remove(chatID)
        sharesByChat[chatID]?.removeAll { $0.isMine }
        if !sharesByChat.values.flatMap({ $0 }).contains(where: \.isMine) && pendingChatIDs.isEmpty {
            manager.stopUpdatingLocation()
        }
    }

    func removeExpiredShares() {
        sharesByChat = sharesByChat.mapValues { $0.filter { $0.expiresAt > Date() } }
        if !sharesByChat.values.flatMap({ $0 }).contains(where: \.isMine) && pendingChatIDs.isEmpty {
            manager.stopUpdatingLocation()
        }
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
                expiresAt: Date().addingTimeInterval(3600),
                isMine: false,
                isDemo: true
            )
        )
    }

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
                    expiresAt: now.addingTimeInterval(3600),
                    isMine: true,
                    isDemo: false
                )
            )
            scheduleExpiration(in: chatID)
        }
        pendingProfiles.removeAll()
        pendingChatIDs.removeAll()

        for chatID in sharesByChat.keys {
            guard let index = sharesByChat[chatID]?.firstIndex(where: { $0.isMine }) else { continue }
            sharesByChat[chatID]?[index].coordinate = location.coordinate
            sharesByChat[chatID]?[index].updatedAt = now
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if !pendingChatIDs.isEmpty {
            failPendingShares("Не удалось определить местоположение. Попробуйте ещё раз.")
        }
    }

    private func scheduleExpiration(in chatID: String) {
        guard let share = sharesByChat[chatID]?.first(where: \.isMine) else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3600))
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
