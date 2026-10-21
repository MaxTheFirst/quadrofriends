import Foundation
import UIKit

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
    /// Путь относительно базового адреса (`…/api`), например `chats/{id}/messages`.
    var path: String
    var query: [URLQueryItem] = []
    var body: (any Encodable)?
    var multipartFile: Data?
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

    init(configuration: APIConfiguration? = nil, urlSession: URLSession = .shared) {
        self.configuration = configuration ?? .current
        self.urlSession = urlSession
    }

    func send<Response: Decodable>(_ request: APIRequest<Response>) async throws -> Response {
        try await perform(request, retryingUnauthorized: true)
    }

    func uploadImage(_ image: UIImage) async throws -> MediaDTO {
        let longestSide = max(image.size.width, image.size.height)
        let scale = longestSide > 2_048 ? 2_048 / longestSide : 1
        let prepared: UIImage
        if scale < 1 {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            prepared = UIGraphicsImageRenderer(
                size: CGSize(width: image.size.width * scale, height: image.size.height * scale),
                format: format
            ).image { _ in image.draw(in: CGRect(origin: .zero, size: CGSize(
                width: image.size.width * scale, height: image.size.height * scale
            ))) }
        } else {
            prepared = image
        }
        guard let data = prepared.jpegData(compressionQuality: 0.82), data.count <= 20_000_000 else {
            throw APIError.invalidResponse
        }
        return try await send(APIRequest(
            method: .post,
            path: "media",
            multipartFile: data,
            idempotencyKey: UUID().uuidString
        ))
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
        if let file = request.multipartFile {
            let boundary = "Boundary-\(UUID().uuidString)"
            var data = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
            data.append(file)
            data.append(Data("\r\n--\(boundary)--\r\n".utf8))
            urlRequest.httpBody = data
            urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        } else if let body = request.body {
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
            guard let date = APIClient.parseISO8601(string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Неверная дата: \(string)")
            }
            return date
        }
        return decoder
    }

    /// Java `Instant` приходит с 0–9 знаками после секунды (`…:00Z`, `…:00.123456Z`).
    /// Дробную часть приводим к миллисекундам: их формат ISO 8601 разбирает надёжно.
    nonisolated static func parseISO8601(_ string: String) -> Date? {
        var normalized = string
        if let dot = string.firstIndex(of: "."),
           let zoneStart = string[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
            let digits = string[string.index(after: dot)..<zoneStart]
            let milliseconds = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
            normalized = String(string[..<dot]) + "." + milliseconds + String(string[zoneStart...])
        }

        if let date = try? Date(normalized, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date
        }
        return try? Date(normalized, strategy: Date.ISO8601FormatStyle())
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
