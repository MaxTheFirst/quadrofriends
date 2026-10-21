import SwiftUI
import Combine

@MainActor
final class ProfileStore: ObservableObject {
    @Published var profile: UserProfile {
        didSet { save() }
    }

    private let storageKey = "ownProfile.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(UserProfile.self, from: data) {
            profile = saved
        } else {
            profile = .sample
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
