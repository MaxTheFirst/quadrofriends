import Combine
import SwiftUI
import UIKit
import VKID

@MainActor
final class VKAuthManager: ObservableObject {
    @Published var errorMessage = ""
    @Published var showingError = false

    private(set) var isConfigured = false

    init() {
        guard
            let clientID = Bundle.main.object(forInfoDictionaryKey: "VK_CLIENT_ID") as? String,
            let clientSecret = Bundle.main.object(forInfoDictionaryKey: "VK_CLIENT_SECRET") as? String,
            !clientID.isEmpty,
            clientID != "0000000",
            !clientSecret.isEmpty
        else { return }

        do {
            try VKID.shared.set(
                config: Configuration(
                    appCredentials: AppCredentials(clientId: clientID, clientSecret: clientSecret)
                )
            )
            isConfigured = true
        } catch {
            showError("Не удалось настроить VK ID: \(error.localizedDescription)")
        }
    }

    var hasAuthorizedSession: Bool {
        isConfigured && VKID.shared.currentAuthorizedSession != nil
    }

    /// Передаёт в `onSuccess` access token VK ID для обмена на сессию backend (`POST /sessions`).
    func authorize(onSuccess: @escaping (String) -> Void) {
        guard isConfigured else {
            showError("Для входа нужны ID приложения VK, защищённый ключ и адрес возврата. Пока можно открыть деморежим.")
            return
        }
        guard let controller = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController else {
            showError("Не удалось открыть окно авторизации VK ID.")
            return
        }

        VKID.shared.authorize(using: .uiViewController(controller)) { [weak self] result in
            DispatchQueue.main.async {
                do {
                    let session = try result.get()
                    onSuccess(session.accessToken.value)
                } catch AuthError.cancelled {
                    // Пользователь закрыл окно входа.
                } catch {
                    self?.showError("Ошибка входа через VK ID: \(error.localizedDescription)")
                }
            }
        }
    }

    func handleOpenURL(_ url: URL) {
        guard isConfigured else { return }
        _ = VKID.shared.open(url: url)
    }

    func signOut() {
        guard hasAuthorizedSession else { return }
        VKID.shared.currentAuthorizedSession?.logout { _ in }
    }

    func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}
