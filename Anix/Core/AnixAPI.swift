import Foundation

/// Эндпоинты бекенда (см. объект `A` в public/js/api.js).
enum AnixAPI {
    private static var c: APIClient { .shared }

    /// config/toggles: оттуда приходит codecProfile для заголовка X-Codec-Profile.
    static func toggles() async {
        let q: [String: Any] = ["version_code": Sign.versionCode, "is_beta": false, "is_api_alt": false]
        guard let data = try? await c.send("GET", "config/toggles", query: q),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        if json["shouldUseMirrorUrls"] as? Bool == true { ImageLoader.preferMirror = true }
        if let cp = json["codecProfile"], !(cp is NSNull) { c.setCodecProfile("\(cp)") }
    }

    // MARK: Лента

    static func interesting() async throws -> [Banner] {
        try await c.post("discover/interesting", as: BannersResponse.self).content
    }

    static func watching(page: Int) async throws -> [Release] {
        try await c.post("discover/watching/\(page)", as: ListResponse.self).items
    }

    static func discussing() async throws -> [Release] {
        try await c.post("discover/discussing", as: ListResponse.self).items
    }

    static func recommendations(page: Int) async throws -> [Release] {
        try await c.post("discover/recommendations/\(page)", query: ["previous_page": -1], as: ListResponse.self).items
    }

    static func emptyFilter() -> [String: Any] {
        let null = NSNull()
        let empty: [Int] = []
        let f: [String: Any] = [
            "age_ratings": empty, "category_id": null, "country": null, "end_year": null,
            "episode_duration_from": null, "episode_duration_to": null,
            "episodes_from": null, "episodes_to": null, "genres": empty, "genres_mode": null,
            "profile_list_exclusions": empty, "season": null, "sort": 0, "source": null,
            "start_year": null, "status_id": null, "studio": null, "types": empty,
            "is_genres_exclude_mode_enabled": false,
        ]
        return f
    }

    static func filter(page: Int, patch: [String: Any]) async throws -> [Release] {
        var body = emptyFilter()
        for (k, v) in patch { body[k] = v }
        return try await c.post("filter/\(page)", json: body, query: ["extended_mode": true], as: ListResponse.self).items
    }

    static func search(page: Int, query: String) async throws -> [Release] {
        let body: [String: Any] = ["query": query, "searchBy": 0]
        return try await c.post("search/releases/\(page)", json: body, apiVersion: "v2", as: ListResponse.self).items
    }

    // MARK: Релиз

    static func release(_ id: Int) async throws -> Release {
        let r = try await c.get("release/\(id)", query: ["extended_mode": true], as: ReleaseResponse.self)
        guard let rel = r.release else {
            throw APIError.decoding(L("релиз недоступен (код %@)", r.code.map(String.init) ?? "—"))
        }
        return rel
    }

    /// Все релизы франшизы по порядку выхода (API v2, как в веб-клиенте).
    static func related(id: Int, page: Int) async throws -> [Release] {
        try await c.get("related/\(id)/\(page)", apiVersion: "v2", as: ListResponse.self).items
    }

    static func comments(releaseId: Int, page: Int, sort: Int = 1) async throws -> [Comment] {
        try await c.get("release/comment/all/\(releaseId)/\(page)", query: ["sort": sort], as: CommentsResponse.self).content
    }

    static func commentReplies(id: Int, page: Int) async throws -> [Comment] {
        try await c.post("release/comment/replies/\(id)/\(page)", query: ["sort": 2], as: CommentsResponse.self).content
    }

    /// Новый комментарий или ответ. Код 0 — принято.
    static func commentAdd(rid: Int, message: String, spoiler: Bool, parent: Int?, replyTo: Int?) async throws -> Int {
        var body: [String: Any] = ["message": message, "spoiler": spoiler]
        body["parentCommentId"] = parent ?? NSNull()
        body["replyToProfileId"] = replyTo ?? NSNull()
        let r = try await c.post("release/comment/add/\(rid)", json: body, as: CodeReply.self)
        return r.code ?? 0
    }

    /// Оценка комментария: 1 — минус, 2 — плюс (повторное нажатие снимает).
    static func commentVote(id: Int, value: Int) async throws -> Int {
        let r = try await c.get("release/comment/vote/\(id)/\(value)", as: CodeReply.self)
        return r.code ?? 0
    }

    static func releaseVote(id: Int, value: Int) async throws -> Int {
        let r = try await c.get("release/vote/add/\(id)/\(value)", as: CodeReply.self)
        return r.code ?? 0
    }

    static func releaseVoteDelete(id: Int) async throws -> Int {
        let r = try await c.get("release/vote/delete/\(id)", as: CodeReply.self)
        return r.code ?? 0
    }

    // MARK: Серии

    static func types(_ rid: Int) async throws -> [EpisodeType] {
        try await c.get("episode/\(rid)", as: TypesResponse.self).types
    }

    static func sources(_ rid: Int, type: Int) async throws -> [EpisodeSource] {
        try await c.get("episode/\(rid)/\(type)", as: SourcesResponse.self).sources
    }

    static func episodes(_ rid: Int, type: Int, source: Int) async throws -> [Episode] {
        try await c.get("episode/\(rid)/\(type)/\(source)", query: ["sort": 1], as: EpisodesResponse.self).episodes
    }

    static func episodeTarget(rid: Int, sid: Int, pos: Int) async throws -> String? {
        try await c.get("episode/target/\(rid)/\(sid)/\(pos)", as: EpisodeTargetResponse.self).episode?.url
    }

    static func episodeWatch(rid: Int, sid: Int, pos: Int) async {
        _ = try? await c.post("episode/watch/\(rid)/\(sid)/\(pos)", as: Empty.self)
    }

    static func historyAdd(rid: Int, sid: Int, pos: Int) async {
        _ = try? await c.get("history/add/\(rid)/\(sid)/\(pos)", as: Empty.self)
    }

    // MARK: Закладки

    static func profileList(status: Int, page: Int) async throws -> [Release] {
        try await c.get("profile/list/all/\(status)/\(page)", query: ["sort": 1, "filter_announce": 0], as: ListResponse.self).items
    }

    static func favorites(page: Int) async throws -> [Release] {
        try await c.get("favorite/all/\(page)", query: ["sort": 1, "filter_announce": 0], as: ListResponse.self).items
    }

    static func listAdd(status: Int, rid: Int) async throws {
        _ = try await c.get("profile/list/add/\(status)/\(rid)", as: Empty.self)
    }

    static func listDelete(status: Int, rid: Int) async throws {
        _ = try await c.get("profile/list/delete/\(status)/\(rid)", as: Empty.self)
    }

    static func favAdd(_ rid: Int) async throws {
        _ = try await c.get("favorite/add/\(rid)", as: Empty.self)
    }

    static func favDelete(_ rid: Int) async throws {
        _ = try await c.get("favorite/delete/\(rid)", as: Empty.self)
    }

    // MARK: Профиль

    static func signIn(login: String, password: String) async throws -> AuthResponse {
        try await c.form("auth/signIn", fields: ["login": login, "password": password], as: AuthResponse.self)
    }

    static func profile(id: Int) async throws -> ProfileBrief? {
        try await c.get("profile/\(id)", as: ProfileResponse.self).profile
    }
}
