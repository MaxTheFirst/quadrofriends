import UIKit

/// Загрузка картинок по URL из `MediaDTO` с кешем в памяти.
@MainActor
final class RemoteImageLoader {
    static let shared = RemoteImageLoader()

    private let cache = NSCache<NSURL, UIImage>()
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        cache.countLimit = 200
    }

    func cachedImage(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = cachedImage(for: url) { return cached }
        guard let result = try? await urlSession.data(from: url) else { return nil }
        let (data, response) = result
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data) else { return nil }
        let prepared = await image.byPreparingForDisplay() ?? image
        cache.setObject(prepared, forKey: url as NSURL)
        return prepared
    }
}
