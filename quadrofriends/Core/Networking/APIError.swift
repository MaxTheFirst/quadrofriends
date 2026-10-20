import Foundation

/// Тело единой ошибки backend: `{ "error": { "code", "message", "details", "request_id" } }`.
struct APIErrorBody: Decodable {
    struct Detail: Decodable {
        let field: String?
        let code: String
    }

    let code: String
    let message: String
    let details: [Detail]?
    let requestId: String?

    private enum WrapperKeys: String, CodingKey {
        case error
    }

    private enum CodingKeys: String, CodingKey {
        case code, message, details, requestId
    }

    init(from decoder: Decoder) throws {
        let wrapper = try decoder.container(keyedBy: WrapperKeys.self)
        let container = try wrapper.nestedContainer(keyedBy: CodingKeys.self, forKey: .error)
        code = try container.decode(String.self, forKey: .code)
        message = try container.decode(String.self, forKey: .message)
        details = try container.decodeIfPresent([Detail].self, forKey: .details)
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId)
    }
}

enum APIError: LocalizedError {
    /// Нет сессии backend или её не удалось обновить — нужен повторный вход.
    case unauthorized
    case network(URLError)
    case server(status: Int, body: APIErrorBody?)
    case invalidResponse
    case decoding(Error)

    var status: Int? {
        if case .server(let status, _) = self { return status }
        return nil
    }

    var code: String? {
        if case .server(_, let body) = self { return body?.code }
        return nil
    }

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Сессия истекла. Войдите снова."
        case .network(let error):
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "Нет подключения к интернету."
            case .timedOut:
                return "Сервер не отвечает. Попробуйте ещё раз."
            case .cannotConnectToHost, .cannotFindHost:
                return "Не удалось подключиться к серверу."
            default:
                return "Ошибка сети: \(error.localizedDescription)"
            }
        case .server(let status, let body):
            if let message = body?.message, !message.isEmpty { return message }
            switch status {
            case 403: return "Недостаточно прав."
            case 404: return "Не найдено."
            case 429: return "Слишком много запросов. Попробуйте позже."
            case 500...: return "Ошибка сервера. Попробуйте позже."
            default: return "Ошибка запроса (\(status))."
            }
        case .invalidResponse:
            return "Некорректный ответ сервера."
        case .decoding:
            return "Не удалось разобрать ответ сервера."
        }
    }
}
