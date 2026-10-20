import Foundation

/// Адрес backend. Задаётся build setting `API_BASE_URL`, который подставляется в `Info.plist`.
struct APIConfiguration {
    static let fallbackBaseURL = URL(string: "https://api.quadro.friends/v1")!

    let baseURL: URL

    /// `wss://…/v1/realtime` для `https`, `ws://…/v1/realtime` для локального `http`.
    var realtimeURL: URL {
        var components = URLComponents(url: baseURL.appending(path: "realtime"), resolvingAgainstBaseURL: false)!
        components.scheme = baseURL.scheme == "http" ? "ws" : "wss"
        return components.url!
    }

    static let current: APIConfiguration = {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
            let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
            url.scheme == "https" || url.scheme == "http"
        else {
            return APIConfiguration(baseURL: fallbackBaseURL)
        }
        return APIConfiguration(baseURL: url)
    }()
}
