import Foundation

struct VideoQuality: Hashable, Identifiable {
    let label: String
    let url: URL
    var id: String { label }
    var height: Int { Int(label.filter(\.isNumber)) ?? 0 }
}

struct ResolvedVideo {
    var qualities: [VideoQuality]
    var headers: [String: String]
    var best: VideoQuality { qualities.max { $0.height < $1.height } ?? qualities[0] }
}

/// Порт парсеров из server/parsers/index.js: ссылка серии → прямые HLS-потоки.
/// Здесь только Kodik (основной источник, без ключа) и AniLibria. Для остальных источников
/// `resolve` вернёт nil — приложение откроет страницу источника во встроенном веб-плеере.
enum VideoResolver {
    static let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"

    private static let kodikHosts: Set<String> = ["kodik.cc", "kodik.info", "aniqit.com", "kodikplayer.com"]
    private static let libriaHosts: Set<String> = ["anilibria.tv", "new.anilib.one", "anixart.libria.fun", "anilibria.top"]

    static func resolve(_ raw: String) async throws -> ResolvedVideo? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("//") { s = "https:" + s }
        guard let url = URL(string: s), let host = url.host else { return nil }
        if kodikHosts.contains(host) { return try await kodik(url, input: s) }
        if libriaHosts.contains(host) { return try await anilibria(input: s) }
        return nil
    }

    // MARK: - Kodik

    /// Ссылки в ответе зашифрованы: буквы сдвинуты на 18 по кругу, затем base64.
    static func decryptKodik(_ src: String) -> String {
        var shifted = ""
        for ch in src.unicodeScalars {
            let v = Int(ch.value)
            if (65...90).contains(v) || (97...122).contains(v) {
                let limit = v <= 90 ? 90 : 122
                var c = v + 18
                if c > limit { c -= 26 }
                shifted.unicodeScalars.append(Unicode.Scalar(UInt8(c)))
            } else {
                shifted.unicodeScalars.append(ch)
            }
        }
        // base64 без паддинга
        while shifted.count % 4 != 0 { shifted += "=" }
        guard let data = Data(base64Encoded: shifted), let out = String(data: data, encoding: .utf8) else { return src }
        return out
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: text).map { String(text[$0]) } ?? ""
        }
    }

    private static func fetch(_ url: URL, headers: [String: String]) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }

    /// Kodik дописывает «720» тем же файлом 480.mp4 — такие пункты пропускаем (fakeQuality в parsers/index.js).
    private static func isFakeQuality(_ src: String, _ q: String) -> Bool {
        guard let path = URL(string: src)?.path,
              let m = firstMatch(#"/(\d{3,4})\.mp4(?::hls:|$)"#, in: path),
              m.count > 1, let real = Int(m[1]), let wanted = Int(q) else { return false }
        return real < wanted
    }

    private static func kodik(_ url: URL, input: String) async throws -> ResolvedVideo? {
        let page = "https://kodikplayer.com" + url.path
        guard let pageURL = URL(string: page) else { return nil }
        let pageHeaders = ["User-Agent": ua, "Referer": "https://kodikplayer.com/"]

        var type: String?
        var id: String?
        var hash: String?
        if let m = firstMatch(#"/(seria|video|movie|anime)/(\d+)/([0-9a-f]+)"#, in: url.path), m.count > 3 {
            type = m[1]; id = m[2]; hash = m[3]
        } else {
            let html = String(decoding: try await fetch(pageURL, headers: pageHeaders), as: UTF8.self)
            type = firstMatch(#"\w+\.type\s=\s'([^']+)';"#, in: html)?.last
            id = firstMatch(#"\w+\.id\s=\s'([^']+)';"#, in: html)?.last
            hash = firstMatch(#"\w+\.hash\s=\s'([^']+)';"#, in: html)?.last
        }
        guard let type, let id, let hash, !type.isEmpty else { return nil }

        var comps = URLComponents(string: "https://kodikplayer.com/ftor")!
        comps.queryItems = [
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "hash", value: hash),
        ]
        guard let ftor = comps.url else { return nil }
        let data = try await fetch(ftor, headers: ["User-Agent": ua, "Referer": page, "Accept": "application/json"])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let links = json["links"] as? [String: Any] else { return nil }

        var qualities: [VideoQuality] = []
        for q in ["360", "480", "720", "1080"] {
            guard let arr = links[q] as? [[String: Any]], var src = arr.first?["src"] as? String, !src.isEmpty else { continue }
            if !(src.hasPrefix("http://") || src.hasPrefix("https://") || src.hasPrefix("//")) {
                src = decryptKodik(src)
            }
            if src.hasPrefix("//") { src = "https:" + src }
            if isFakeQuality(src, q) { continue }
            // прямой MP4 с CDN Kodik часто уводит на недоступный edge — берём его HLS-вариант
            if URL(string: src)?.path.lowercased().hasSuffix(".mp4") == true { src += ":hls:manifest.m3u8" }
            src = src.replacingOccurrences(of: ":hls:hls.m3u8", with: ":hls:manifest.m3u8")
            if let u = URL(string: src) { qualities.append(VideoQuality(label: "\(q)p", url: u)) }
        }
        guard !qualities.isEmpty else { return nil }
        return ResolvedVideo(qualities: qualities, headers: ["User-Agent": ua, "Referer": input])
    }

    // MARK: - AniLibria

    private static func anilibria(input: String) async throws -> ResolvedVideo? {
        guard let m = firstMatch(#"id=(\d+)&ep=(\d+)"#, in: input), m.count > 2,
              let url = URL(string: "https://anilibria.top/api/v1/anime/releases/\(m[1])") else { return nil }
        let data = try await fetch(url, headers: ["User-Agent": ua])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eps = json["episodes"] as? [[String: Any]] else { return nil }
        let ep = eps.first { e in
            if let n = e["ordinal"] as? Int { return String(n) == m[2] }
            if let n = e["ordinal"] as? Double { return String(Int(n)) == m[2] }
            return false
        }
        guard let ep else { return nil }
        var qualities: [VideoQuality] = []
        for (key, label) in [("hls_480", "480p"), ("hls_720", "720p"), ("hls_1080", "1080p")] {
            if let s = (ep[key] as? String)?.trimmingCharacters(in: .whitespaces), !s.isEmpty, let u = URL(string: s) {
                qualities.append(VideoQuality(label: label, url: u))
            }
        }
        guard !qualities.isEmpty else { return nil }
        return ResolvedVideo(qualities: qualities, headers: ["User-Agent": ua])
    }
}
