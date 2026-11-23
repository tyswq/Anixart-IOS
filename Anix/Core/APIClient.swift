import Foundation

enum APIError: LocalizedError {
    case http(Int)
    case badURL
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .http(let code): return L("Ошибка сервера (HTTP %ld)", code)
        case .badURL: return L("Неверный адрес запроса")
        case .decoding(let m): return L("Не удалось разобрать ответ: %@", m)
        }
    }
}

struct Empty: Decodable {
    init(from decoder: Decoder) throws {}
}

/// Клиент бекенда Anixart: адрес берётся из urls.json, каждый запрос подписывается заголовками мобильного приложения,
/// токен передаётся query-параметром `token` (как в public/js/api.js).
final class APIClient: @unchecked Sendable {
    static let shared = APIClient()

    private let lock = NSLock()
    private var _token = ""
    private var _codecProfile: String?
    private var baseTask: Task<URL, Never>?
    private let session: URLSession
    private let decoder: JSONDecoder

    private let defaultBase = "https://api-s.anixsekai.com/"
    private let urlsJSON = "https://anixhelper.github.io/pages/urls.json"

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.waitsForConnectivity = false
        // ответы API никогда не берём из кеша: иначе страница и списки показывают старое состояние
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
        session = URLSession(configuration: cfg)
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    var token: String {
        get { lock.lock(); defer { lock.unlock() }; return _token }
        set { lock.lock(); _token = newValue; lock.unlock() }
    }

    func setCodecProfile(_ value: String?) {
        lock.lock(); _codecProfile = value; lock.unlock()
    }

    private func codecProfile() -> String? {
        lock.lock(); defer { lock.unlock() }
        return _codecProfile
    }

    private func headers() -> [String: String] {
        [
            "User-Agent": Sign.userAgent,
            "Sign": Sign.sign(),
            "X-Media-Session": "",
            "X-Codec-Profile": Sign.codecProfileHeader(codecProfile()),
        ]
    }

    // MARK: - Адрес бекенда

    private func baseTaskLocked() -> Task<URL, Never> {
        lock.lock(); defer { lock.unlock() }
        if let t = baseTask { return t }
        let t = Task { await self.resolveBase() }
        baseTask = t
        return t
    }

    private func ensureBase() async -> URL {
        await baseTaskLocked().value
    }

    private func normalized(_ s: String) -> URL? {
        URL(string: s.hasSuffix("/") ? s : s + "/")
    }

    private func resolveBase() async -> URL {
        var candidates: [String] = []
        if let u = URL(string: urlsJSON),
           let (data, _) = try? await session.data(from: u),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let entry = (json["default"] as? [String: Any]) ?? (json.values.first as? [String: Any])
            if let s = entry?["api_url"] as? String { candidates.append(s) }
        }
        candidates.append(defaultBase)

        for c in candidates {
            guard let base = normalized(c),
                  var comps = URLComponents(url: base.appendingPathComponent("config/urls"), resolvingAgainstBaseURL: false)
            else { continue }
            comps.queryItems = [
                URLQueryItem(name: "version_code", value: String(Sign.versionCode)),
                URLQueryItem(name: "is_beta", value: "false"),
            ]
            guard let url = comps.url else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 8
            for (k, v) in headers() { req.setValue(v, forHTTPHeaderField: k) }
            guard let (data, resp) = try? await session.data(for: req) else { continue }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else { continue }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let list = json["api_urls"] as? [String],
               let first = list.first, let u = normalized(first) {
                return u
            }
            return base
        }
        return normalized(defaultBase)!
    }

    // MARK: - Запросы

    func send(
        _ method: String,
        _ path: String,
        query: [String: Any] = [:],
        body: Data? = nil,
        contentType: String? = nil,
        apiVersion: String? = nil,
        withToken: Bool = true
    ) async throws -> Data {
        let base = await ensureBase()
        var items: [URLQueryItem] = []
        for (k, v) in query { items.append(URLQueryItem(name: k, value: "\(v)")) }
        let tok = token
        if withToken, !tok.isEmpty, query["token"] == nil {
            items.append(URLQueryItem(name: "token", value: tok))
        }
        guard let rel = URL(string: path, relativeTo: base),
              var comps = URLComponents(url: rel.absoluteURL, resolvingAgainstBaseURL: true)
        else { throw APIError.badURL }
        if !items.isEmpty { comps.queryItems = items }
        guard let url = comps.url else { throw APIError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        for (k, v) in headers() { req.setValue(v, forHTTPHeaderField: k) }
        if let contentType { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let apiVersion { req.setValue(apiVersion, forHTTPHeaderField: "API-Version") }
        // мобильный клиент всегда шлёт тело POST, даже пустое
        if method == "POST" { req.httpBody = body ?? Data() }

        var lastError: Error = APIError.badURL
        for attempt in 0..<3 {
            do {
                let (data, resp) = try await session.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if method == "GET", [502, 503, 504].contains(code), attempt < 2 {
                    try await Task.sleep(nanoseconds: 300_000_000 * UInt64(attempt * 2 + 1))
                    continue
                }
                guard (200..<300).contains(code) else { throw APIError.http(code) }
                return data
            } catch let e as APIError {
                throw e
            } catch {
                if Task.isCancelled { throw error }
                lastError = error
                if method != "GET" || attempt == 2 { throw error }
                try? await Task.sleep(nanoseconds: 300_000_000 * UInt64(attempt * 2 + 1))
            }
        }
        throw lastError
    }

    /// Ответ → ссылки @id раскрыты → Decodable.
    func decode<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        let src = data.isEmpty ? Data("{}".utf8) : data
        do {
            let obj = try JSONSerialization.jsonObject(with: src, options: [.fragmentsAllowed])
            let fixed = RefResolver.resolve(obj)
            let out = try JSONSerialization.data(withJSONObject: fixed, options: [.fragmentsAllowed])
            return try decoder.decode(T.self, from: out)
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    func get<T: Decodable>(_ path: String, query: [String: Any] = [:], apiVersion: String? = nil, as type: T.Type) async throws -> T {
        let data = try await send("GET", path, query: query, apiVersion: apiVersion)
        return try decode(data, as: type)
    }

    func post<T: Decodable>(_ path: String, json: [String: Any]? = nil, query: [String: Any] = [:], apiVersion: String? = nil, as type: T.Type) async throws -> T {
        var body: Data?
        var ct: String?
        if let json {
            body = try JSONSerialization.data(withJSONObject: json)
            ct = "application/json; charset=UTF-8"
        }
        let data = try await send("POST", path, query: query, body: body, contentType: ct, apiVersion: apiVersion)
        return try decode(data, as: type)
    }

    struct UploadFile {
        var field: String
        var filename: String
        var mime: String
        var data: Data
    }

    /// multipart/form-data: текстовые поля и один файл (загрузка фото профиля).
    func multipart<T: Decodable>(_ path: String, fields: [String: String], file: UploadFile, as type: T.Type) async throws -> T {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        for (k, v) in fields {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(file.field)\"; filename=\"\(file.filename)\"\r\nContent-Type: \(file.mime)\r\n\r\n".utf8))
        body.append(file.data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let data = try await send("POST", path, body: body, contentType: "multipart/form-data; boundary=\(boundary)")
        return try decode(data, as: type)
    }

    func form<T: Decodable>(_ path: String, fields: [String: String], withToken: Bool = false, as type: T.Type) async throws -> T {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let body = fields.map { k, v in
            let ek = k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
        let data = try await send(
            "POST", path, body: Data(body.utf8),
            contentType: "application/x-www-form-urlencoded", withToken: withToken
        )
        return try decode(data, as: type)
    }
}

/// Бекенд повторно встречающийся объект присылает числом (`@id`). Восстанавливаем ссылки так же, как `resolveRefs` в api.js:
/// число заменяется объектом, только если по этому ключу где-то в ответе уже лежал объект с тем же набором полей.
enum RefResolver {
    static func intValue(_ x: Any?) -> Int? {
        guard let n = x as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        guard n.doubleValue == Double(n.intValue) else { return nil }
        return n.intValue
    }

    static func resolve(_ root: Any) -> Any {
        var byId: [Int: [String: Any]] = [:]
        var shapes: [String: Set<String>] = [:]

        func sig(_ d: [String: Any]) -> String {
            d.keys.filter { $0 != "@id" }.sorted().joined(separator: ",")
        }

        func collect(_ v: Any, _ key: String?) {
            if let arr = v as? [Any] {
                for x in arr { collect(x, key) }
                return
            }
            if let d = v as? [String: Any] {
                if let id = intValue(d["@id"]) { byId[id] = d }
                if let key { shapes[key, default: []].insert(sig(d)) }
                for (k, x) in d { collect(x, k) }
            }
        }
        collect(root, nil)
        if byId.isEmpty { return root }

        func substitute(_ x: Any, _ key: String?) -> [String: Any]? {
            guard let key, key != "@id", let id = intValue(x),
                  let known = shapes[key], let target = byId[id],
                  known.contains(sig(target)) else { return nil }
            return target
        }

        func fix(_ v: Any, _ key: String?, _ depth: Int) -> Any {
            if let arr = v as? [Any] {
                return arr.map { el -> Any in
                    if depth < 6, let t = substitute(el, key) { return fix(t, key, depth + 1) }
                    return fix(el, key, depth)
                }
            }
            if let d = v as? [String: Any] {
                var out: [String: Any] = [:]
                for (k, x) in d {
                    if depth < 6, let t = substitute(x, k) {
                        out[k] = fix(t, k, depth + 1)
                    } else {
                        out[k] = fix(x, k, depth)
                    }
                }
                return out
            }
            return v
        }
        return fix(root, nil, 0)
    }
}
