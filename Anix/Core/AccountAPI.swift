import Foundation

// Регистрация и настройки профиля. Эндпоинты и коды ответов — как в public/js/screens/auth.js и profile-settings.js.

/// Универсальный ответ auth/* и profile/preference/*: нужные поля читаются «мягко».
struct Reply: Decodable {
    var code: Int?
    var hash: String?
    var codeTimestampExpires: Double?
    var timestampExpires: Double?
    var suggestedLogins: [String]?
    var available: Bool?
    var avatar: String?
    var token: String?
    var profile: ProfileBrief?
    var profileToken: TokenInfo?

    enum CodingKeys: String, CodingKey {
        case code, hash, codeTimestampExpires, timestampExpires, suggestedLogins, available, avatar, token, profile, profileToken
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = c.lossy(.code)
        hash = c.lossy(.hash)
        codeTimestampExpires = c.lossy(.codeTimestampExpires)
        timestampExpires = c.lossy(.timestampExpires)
        suggestedLogins = c.lossy(.suggestedLogins)
        available = c.lossy(.available)
        avatar = c.lossy(.avatar)
        token = c.lossy(.token)
        profile = c.lossy(.profile)
        profileToken = c.lossy(.profileToken)
    }
}

/// profile/preference/my
struct MyPreference: Decodable {
    var code: Int?
    var status: String?
    var avatar: String?
    var privacyStats: Int?
    var privacyCounts: Int?
    var privacySocial: Int?
    var privacyFriendRequests: Int?
    var isChangeAvatarBanned: Bool?
    var isChangeLoginBanned: Bool?
    var emailHint: String?

    enum CodingKeys: String, CodingKey {
        case code, status, avatar, privacyStats, privacyCounts, privacySocial, privacyFriendRequests
        case isChangeAvatarBanned, isChangeLoginBanned, emailHint
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = c.lossy(.code)
        status = c.lossy(.status)
        avatar = c.lossy(.avatar)
        privacyStats = c.lossy(.privacyStats)
        privacyCounts = c.lossy(.privacyCounts)
        privacySocial = c.lossy(.privacySocial)
        privacyFriendRequests = c.lossy(.privacyFriendRequests)
        isChangeAvatarBanned = c.lossy(.isChangeAvatarBanned)
        isChangeLoginBanned = c.lossy(.isChangeLoginBanned)
        emailHint = c.lossy(.emailHint)
    }
}

/// profile/preference/social
struct SocialPages: Decodable {
    var code: Int?
    var vkPage: String?
    var tgPage: String?
    var discordPage: String?
    var ttPage: String?
    var instPage: String?

    enum CodingKeys: String, CodingKey { case code, vkPage, tgPage, discordPage, ttPage, instPage }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = c.lossy(.code)
        vkPage = c.lossy(.vkPage)
        tgPage = c.lossy(.tgPage)
        discordPage = c.lossy(.discordPage)
        ttPage = c.lossy(.ttPage)
        instPage = c.lossy(.instPage)
    }
}

/// profile/preference/login/info
struct LoginInfo: Decodable {
    var code: Int?
    var login: String?
    var isChangeAvailable: Bool?
    var nextChangeAvailableAt: Double?

    enum CodingKeys: String, CodingKey { case code, login, isChangeAvailable, nextChangeAvailableAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = c.lossy(.code)
        login = c.lossy(.login)
        isChangeAvailable = c.lossy(.isChangeAvailable)
        nextChangeAvailableAt = c.lossy(.nextChangeAvailableAt)
    }
}

enum AccountAPI {
    private static var c: APIClient { .shared }

    // MARK: Регистрация

    static func checkLogin(_ login: String) async throws -> Reply {
        try await c.form("auth/checkLogin", fields: ["login": login], as: Reply.self)
    }

    static func signUp(login: String, email: String, password: String) async throws -> Reply {
        try await c.form("auth/signUp", fields: ["login": login, "email": email, "password": password], as: Reply.self)
    }

    static func verify(login: String, email: String, password: String, hash: String, code: String) async throws -> Reply {
        try await c.form(
            "auth/verify",
            fields: ["login": login, "email": email, "password": password, "hash": hash, "code": code],
            as: Reply.self
        )
    }

    static func resend(login: String, email: String, password: String, hash: String) async throws -> Reply {
        try await c.form(
            "auth/resend",
            fields: ["login": login, "email": email, "password": password, "hash": hash],
            as: Reply.self
        )
    }

    // MARK: Настройки профиля

    static func preferences() async throws -> MyPreference {
        try await c.get("profile/preference/my", as: MyPreference.self)
    }

    static func setStatus(_ status: String) async throws -> Reply {
        try await c.post("profile/preference/status/edit", json: ["status": status], as: Reply.self)
    }

    /// kind: stats, counts, social, friendRequests; permission — номер пункта (0 — все, 1 — друзья, 2 — только я).
    static func setPrivacy(kind: String, permission: Int) async throws -> Reply {
        try await c.post("profile/preference/privacy/\(kind)/edit", json: ["permission": permission], as: Reply.self)
    }

    static func socialPages() async throws -> SocialPages {
        try await c.get("profile/preference/social", as: SocialPages.self)
    }

    static func setSocial(_ body: [String: String]) async throws -> Reply {
        try await c.post("profile/preference/social/edit", json: body, as: Reply.self)
    }

    static func loginInfo() async throws -> LoginInfo {
        try await c.post("profile/preference/login/info", as: LoginInfo.self)
    }

    static func changeLogin(_ login: String) async throws -> Reply {
        try await c.post("profile/preference/login/change", query: ["login": login], as: Reply.self)
    }

    static func changePassword(current: String, new: String) async throws -> Reply {
        try await c.form(
            "profile/preference/password/change",
            fields: ["current": current, "new": new], withToken: true, as: Reply.self
        )
    }

    static func uploadAvatar(jpeg: Data) async throws -> Reply {
        try await c.multipart(
            "profile/preference/avatar/edit",
            fields: ["name": "image"],
            file: .init(field: "image", filename: "image_\(Int(Date().timeIntervalSince1970)).jpg", mime: "image/*", data: jpeg),
            as: Reply.self
        )
    }

    static func deleteAvatar() async throws -> Reply {
        try await c.get("profile/preference/avatar/delete", as: Reply.self)
    }
}
