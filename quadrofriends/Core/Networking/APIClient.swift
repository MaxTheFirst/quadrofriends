import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// Описание одного вызова REST API с типом ожидаемого ответа.
struct APIRequest<Response: Decodable> {
    var method: HTTPMethod
    /// Путь относительно `/v1`, например `chats/{id}/messages`.
    var path: String
    var query: [URLQueryItem] = []
    var body: (any Encodable)?
    /// Для повторяемых `POST`: повтор с тем же ключом вернёт тот же результат.
    var idempotencyKey: String?
    var requiresAuth = true
}

/// Выдаёт действующий access token и обновляет сессию по refresh token.
@MainActor
protocol AccessTokenProvider: AnyObject {
    func validAccessToken() async throws -> String
    func refreshAccessToken() async throws
}

@MainActor
final class APIClient {
    let configuration: APIConfiguration
    weak var tokenProvider: (any AccessTokenProvider)?

    private let urlSession: URLSession
    private let decoder = APIClient.makeDecoder()
    private let encoder = APIClient.makeEncoder()

    init(configuration: APIConfiguration = .current, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    func send<Response: Decodable>(_ request: APIRequest<Response>) async throws -> Response {
        try await perform(request, retryingUnauthorized: true)
    }

    private func perform<Response: Decodable>(
        _ request: APIRequest<Response>,
        retryingUnauthorized: Bool
    ) async throws -> Response {
        var urlRequest = try makeURLRequest(for: request)
        if request.requiresAuth {
            guard let tokenProvider else { throw APIError.unauthorized }
            let token = try await tokenProvider.validAccessToken()
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: urlRequest)
        } catch let error as URLError {
            throw APIError.network(error)
        }
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        // Access token мог истечь раньше срока: обновляем сессию и повторяем запрос один раз.
        if httpResponse.statusCode == 401, request.requiresAuth, retryingUnauthorized, let tokenProvider {
            try await tokenProvider.refreshAccessToken()
            return try await perform(request, retryingUnauthorized: false)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.server(
                status: httpResponse.statusCode,
                body: try? decoder.decode(APIErrorBody.self, from: data)
            )
        }

        if Response.self == EmptyResponse.self || data.isEmpty, let empty = EmptyResponse() as? Response {
            return empty
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func makeURLRequest<Response>(for request: APIRequest<Response>) throws -> URLRequest {
        var components = URLComponents(
            url: configuration.baseURL.appending(path: request.path),
            resolvingAgainstBaseURL: false
        )
        let query = request.query.filter { $0.value != nil }
        if !query.isEmpty {
            components?.queryItems = query
        }
        guard let url = components?.url else { throw APIError.invalidResponse }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = request.body {
            urlRequest.httpBody = try encoder.encode(body)
            let contentType = request.method == .patch ? "application/merge-patch+json" : "application/json; charset=utf-8"
            urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if let idempotencyKey = request.idempotencyKey {
            urlRequest.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        return urlRequest
    }

    // MARK: - JSON

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            // Сервер может присылать время как с долями секунды, так и без них.
            if let date = try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                return date
            }
            if let date = try? Date(string, strategy: Date.ISO8601FormatStyle()) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Неверная дата: \(string)")
        }
        return decoder
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
