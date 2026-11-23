import Observation
import SwiftUI
import UIKit

/// Последняя ошибка загрузки картинки — показывается в профиле, чтобы было видно причину.
@MainActor
@Observable
final class ImageDiagnostics {
    static let shared = ImageDiagnostics()
    var lastFailure: String?
    var failures = 0
    var successes = 0
    var viaMirror = 0
    var noURL = 0
    var lastSync: String?
}

/// Загрузчик картинок: адрес приводится к нормальному виду, запрос идёт с несколькими вариантами заголовков
/// (некоторые CDN режут стандартный запрос iOS), результат кэшируется в памяти и на диске.
final class ImageLoader: @unchecked Sendable {
    static let shared = ImageLoader()

    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession

    private static let safariUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 300 << 20)
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: cfg)
        cache.countLimit = 300
    }

    /// Очищает память и диск, где лежат загруженные картинки.
    func clearCache() {
        cache.removeAllObjects()
        session.configuration.urlCache?.removeAllCachedResponses()
    }

    /// Зеркало статики: s.anixmirai.com → mirror-s.anixmirai.com (как «Альтернативное соединение» в веб-клиенте).
    static func mirror(_ url: URL) -> URL? {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = c.host, !host.hasPrefix("mirror") else { return nil }
        let parts = host.split(separator: ".")
        c.host = parts.count > 2 ? "mirror-\(parts[0]).\(parts.dropFirst().joined(separator: "."))" : "mirror.\(host)"
        return c.url
    }

    /// Сервер (config/toggles) или пользователь просят сразу ходить на зеркало.
    static var preferMirror: Bool {
        get { UserDefaults.standard.bool(forKey: "preferMirror") }
        set { UserDefaults.standard.set(newValue, forKey: "preferMirror") }
    }

    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("//") { s = "https:" + s }
        if let u = URL(string: s), u.scheme != nil { return u }
        // адрес с пробелами или кириллицей
        if let enc = s.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed.union(CharacterSet(charactersIn: "%#"))),
           let u = URL(string: enc), u.scheme != nil {
            return u
        }
        return nil
    }

    func image(for raw: String) async -> UIImage? {
        let key = raw as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let url = Self.normalize(raw) else {
            await report("Неверный адрес картинки: \(raw.prefix(80))")
            return nil
        }

        let safari = ["User-Agent": Self.safariUA, "Accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8"]
        let app = ["User-Agent": Sign.userAgent]
        var variants: [(URL, [String: String], Bool)] = []
        let mirrored = Self.mirror(url)
        if Self.preferMirror, let m = mirrored { variants.append((m, safari, true)) }
        variants.append((url, safari, false))
        variants.append((url, app, false))
        if !Self.preferMirror, let m = mirrored { variants.append((m, safari, true)) }
        if url.scheme == "http", var c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            c.scheme = "https"
            if let https = c.url { variants.append((https, safari, false)) }
        }

        var reason = ""
        for (u, headers, isMirror) in variants {
            if Task.isCancelled { return nil }
            var req = URLRequest(url: u)
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
            do {
                let (data, resp) = try await session.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(code), let img = UIImage(data: data) {
                    cache.setObject(img, forKey: key)
                    await success(mirror: isMirror)
                    return img
                }
                reason = (200..<300).contains(code)
                    ? "не картинка (\(data.count) байт, \(resp.mimeType ?? "?")) — \(u.host ?? "")"
                    : "HTTP \(code) — \(u.host ?? "")"
            } catch {
                if (error as? URLError)?.code == .cancelled { return nil }
                reason = "\(error.localizedDescription) — \(u.host ?? "")"
            }
        }
        await report(reason)
        return nil
    }

    @MainActor private func report(_ text: String) {
        ImageDiagnostics.shared.lastFailure = text
        ImageDiagnostics.shared.failures += 1
    }

    @MainActor private func success(mirror: Bool) {
        ImageDiagnostics.shared.successes += 1
        if mirror { ImageDiagnostics.shared.viaMirror += 1 }
    }
}

struct RemoteImage: View {
    let url: String?

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.primary.opacity(0.06)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else if failed {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .animation(.easeOut(duration: 0.2), value: image == nil)
        .task(id: url) {
            image = nil
            failed = false
            guard let url, !url.isEmpty else {
                failed = true
                ImageDiagnostics.shared.noURL += 1
                return
            }
            if let img = await ImageLoader.shared.image(for: url) {
                image = img
            } else if !Task.isCancelled {
                failed = true
            }
        }
    }
}
