import Foundation

// Все поля читаются «мягко»: неожиданный тип или отсутствие поля даёт nil, а не ошибку разбора всего списка.
extension KeyedDecodingContainer {
    func lossy<T: Decodable>(_ key: Key) -> T? {
        try? decodeIfPresent(T.self, forKey: key)
    }
}

struct Named: Decodable, Hashable {
    var id: Int?
    var name: String?
    enum CodingKeys: String, CodingKey { case id, name }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lossy(.id)
        name = c.lossy(.name)
    }
}

struct Release: Decodable, Identifiable, Hashable {
    var id: Int = 0
    var titleRu: String?
    var titleOriginal: String?
    var titleAlt: String?
    var image: String?
    var desc: String?
    var note: String?
    var genres: String?
    var country: String?
    var studio: String?
    var author: String?
    var director: String?
    var source: String?
    var translators: String?
    var year: Int?
    var season: Int?
    var category: Named?
    var status: Named?
    var statusId: Int?
    var episodesReleased: Int?
    var episodesTotal: Int?
    var duration: Int?
    var grade: Double?
    var voteCount: Int?
    var isFavorite: Bool?
    var profileListStatus: Int?
    var ageRating: Int?
    var airedOnDate: Double?
    var releaseDate: String?
    var watchingCount: Int?
    var planCount: Int?
    var completedCount: Int?
    var holdOnCount: Int?
    var droppedCount: Int?
    var commentCount: Int?
    var related: RelatedInfo?
    var yourVote: Int?

    enum CodingKeys: String, CodingKey {
        case id, titleRu, titleOriginal, titleAlt, image
        case desc = "description"
        case note, genres, country, studio, author, director, source, translators, year, season
        case category, status, statusId, episodesReleased, episodesTotal, duration, grade, voteCount
        case isFavorite, profileListStatus, ageRating, airedOnDate, releaseDate
        case watchingCount, planCount, completedCount, holdOnCount, droppedCount, commentCount, related, yourVote
    }

    init(id: Int) { self.id = id }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lossy(.id) ?? 0
        titleRu = c.lossy(.titleRu)
        titleOriginal = c.lossy(.titleOriginal)
        titleAlt = c.lossy(.titleAlt)
        image = c.lossy(.image)
        desc = c.lossy(.desc)
        note = c.lossy(.note)
        genres = c.lossy(.genres)
        country = c.lossy(.country)
        studio = c.lossy(.studio)
        author = c.lossy(.author)
        director = c.lossy(.director)
        source = c.lossy(.source)
        translators = c.lossy(.translators)
        year = c.lossy(.year)
        season = c.lossy(.season)
        category = c.lossy(.category)
        status = c.lossy(.status)
        statusId = c.lossy(.statusId)
        episodesReleased = c.lossy(.episodesReleased)
        episodesTotal = c.lossy(.episodesTotal)
        duration = c.lossy(.duration)
        grade = c.lossy(.grade)
        voteCount = c.lossy(.voteCount)
        isFavorite = c.lossy(.isFavorite)
        profileListStatus = c.lossy(.profileListStatus)
        ageRating = c.lossy(.ageRating)
        airedOnDate = c.lossy(.airedOnDate)
        releaseDate = c.lossy(.releaseDate)
        watchingCount = c.lossy(.watchingCount)
        planCount = c.lossy(.planCount)
        completedCount = c.lossy(.completedCount)
        holdOnCount = c.lossy(.holdOnCount)
        droppedCount = c.lossy(.droppedCount)
        commentCount = c.lossy(.commentCount)
        related = c.lossy(.related)
        yourVote = c.lossy(.yourVote)
    }

    static func == (a: Release, b: Release) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    // MARK: Для интерфейса

    /// В английском интерфейсе показываем оригинальное (романизированное) название, в русском — русское.
    static var englishUI: Bool { UserDefaults.standard.string(forKey: "app.language") == "en" }

    var displayTitle: String {
        if Self.englishUI { return titleOriginal ?? titleRu ?? L("Без названия") }
        return titleRu ?? titleOriginal ?? L("Без названия")
    }

    /// Второе название под основным (в русском интерфейсе — оригинальное).
    var altTitle: String? {
        guard !Self.englishUI, titleRu != nil else { return nil }
        return titleOriginal
    }

    var gradeText: String? {
        guard let g = grade, g > 0, (voteCount ?? 0) > 0 else { return nil }
        return String(format: "%.1f", g)
    }

    var episodesText: String? {
        switch (episodesReleased, episodesTotal) {
        case let (r?, t?) where t > 0: return r == t ? L("%ld эп.", t) : L("%ld из %ld эп.", r, t)
        case let (r?, _) where r > 0: return L("%ld эп.", r)
        case let (_, t?) where t > 0: return L("%ld эп.", t)
        default: return nil
        }
    }

    var metaLine: String {
        [year.map { "\($0)" }, category?.name, episodesText].compactMap { $0 }.joined(separator: " • ")
    }

    var ageText: String? {
        let t = ["", "0+", "6+", "12+", "16+", "18+"]
        guard let a = ageRating, a > 0, a < t.count else { return nil }
        return t[a]
    }

    var seasonName: String? {
        switch season {
        case 1: return L("зима")
        case 2: return L("весна")
        case 3: return L("лето")
        case 4: return L("осень")
        default: return nil
        }
    }

    var genreList: [String] {
        (genres ?? "").components(separatedBy: ", ").filter { !$0.isEmpty }
    }

    var isAnnounce: Bool { (status?.id ?? statusId) == 3 }
}

/// Ответы со списками: поле `content` (большинство) или `releases` (поиск).
/// Франшиза: объединяет связанные релизы (related/{id}).
struct RelatedInfo: Decodable, Hashable {
    var id: Int = 0
    var name: String?
    var nameRu: String?
    var description: String?

    enum CodingKeys: String, CodingKey { case id, name, nameRu, description }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lossy(.id) ?? 0
        name = c.lossy(.name)
        nameRu = c.lossy(.nameRu)
        description = c.lossy(.description)
    }

    var displayName: String {
        if Release.englishUI { return name ?? nameRu ?? L("Связанные релизы") }
        return nameRu ?? name ?? L("Связанные релизы")
    }
}

struct ListResponse: Decodable {
    var items: [Release] = []
    var totalPageCount: Int?
    var currentPage: Int?

    enum CodingKeys: String, CodingKey { case content, releases, totalPageCount, currentPage }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let content: [Release]? = c.lossy(.content)
        let releases: [Release]? = c.lossy(.releases)
        items = content ?? releases ?? []
        totalPageCount = c.lossy(.totalPageCount)
        currentPage = c.lossy(.currentPage)
    }
}

struct ReleaseResponse: Decodable {
    var code: Int?
    var release: Release?
    enum CodingKeys: String, CodingKey { case code, release }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = c.lossy(.code)
        release = c.lossy(.release)
    }
}

struct Banner: Decodable, Identifiable, Hashable {
    var id = UUID()
    var type: Int?
    var action: String?
    var image: String?
    var title: String?
    var subtitle: String?

    enum CodingKeys: String, CodingKey { case type, action, image, title, description }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = c.lossy(.type)
        if let s: String = c.lossy(.action) {
            action = s
        } else if let i: Int = c.lossy(.action) {
            action = String(i)
        }
        image = c.lossy(.image)
        title = c.lossy(.title)
        subtitle = c.lossy(.description)
    }

    var releaseId: Int? { type == 1 ? action.flatMap { Int($0) } : nil }
}

struct BannersResponse: Decodable {
    var content: [Banner] = []
    enum CodingKeys: String, CodingKey { case content }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        content = c.lossy(.content) ?? []
    }
}

// MARK: - Серии

struct EpisodeType: Decodable, Identifiable, Hashable {
    var id: Int = 0
    var name: String?
    var icon: String?
    var workers: String?
    var episodesCount: Int?
    var viewCount: Int?
    var isSub: Bool?
    var pinned: Bool?

    enum CodingKeys: String, CodingKey { case id, name, icon, workers, episodesCount, viewCount, isSub, pinned }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lossy(.id) ?? 0
        name = c.lossy(.name)
        icon = c.lossy(.icon)
        workers = c.lossy(.workers)
        episodesCount = c.lossy(.episodesCount)
        viewCount = c.lossy(.viewCount)
        isSub = c.lossy(.isSub)
        pinned = c.lossy(.pinned)
    }
}

struct EpisodeSource: Decodable, Identifiable, Hashable {
    var id: Int = 0
    var name: String?
    var episodesCount: Int?

    enum CodingKeys: String, CodingKey { case id, name, episodesCount }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lossy(.id) ?? 0
        name = c.lossy(.name)
        episodesCount = c.lossy(.episodesCount)
    }
}

struct Episode: Decodable, Identifiable, Hashable {
    var position: Int = 0
    var name: String?
    var url: String?
    var iframe: Bool?
    var isFiller: Bool?
    var addedDate: Double?

    var id: Int { position }

    enum CodingKeys: String, CodingKey { case position, name, url, iframe, isFiller, addedDate }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        position = c.lossy(.position) ?? 0
        name = c.lossy(.name)
        url = c.lossy(.url)
        iframe = c.lossy(.iframe)
        isFiller = c.lossy(.isFiller)
        addedDate = c.lossy(.addedDate)
    }
}

struct TypesResponse: Decodable {
    var types: [EpisodeType] = []
    enum CodingKeys: String, CodingKey { case types }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        types = c.lossy(.types) ?? []
    }
}

struct SourcesResponse: Decodable {
    var sources: [EpisodeSource] = []
    enum CodingKeys: String, CodingKey { case sources }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sources = c.lossy(.sources) ?? []
    }
}

struct EpisodesResponse: Decodable {
    var episodes: [Episode] = []
    enum CodingKeys: String, CodingKey { case episodes }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        episodes = c.lossy(.episodes) ?? []
    }
}

struct EpisodeTargetResponse: Decodable {
    var episode: Episode?
    enum CodingKeys: String, CodingKey { case episode }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        episode = c.lossy(.episode)
    }
}

// MARK: - Профиль и вход

struct ProfileBrief: Codable, Hashable {
    var id: Int = 0
    var login: String?
    var avatar: String?
    var status: String?
    var watchingCount: Int?
    var planCount: Int?
    var completedCount: Int?
    var holdOnCount: Int?
    var droppedCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, login, avatar, status, watchingCount, planCount, completedCount, holdOnCount, droppedCount
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lossy(.id) ?? 0
        login = c.lossy(.login)
        avatar = c.lossy(.avatar)
        status = c.lossy(.status)
        watchingCount = c.lossy(.watchingCount)
        planCount = c.lossy(.planCount)
        completedCount = c.lossy(.completedCount)
        holdOnCount = c.lossy(.holdOnCount)
        droppedCount = c.lossy(.droppedCount)
    }
}

struct TokenInfo: Decodable {
    var token: String?
    enum CodingKeys: String, CodingKey { case token }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = c.lossy(.token)
    }
}

struct AuthResponse: Decodable {
    var code: Int?
    var profile: ProfileBrief?
    var profileToken: TokenInfo?
    enum CodingKeys: String, CodingKey { case code, profile, profileToken }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = c.lossy(.code)
        profile = c.lossy(.profile)
        profileToken = c.lossy(.profileToken)
    }
}

struct ProfileResponse: Decodable {
    var profile: ProfileBrief?
    enum CodingKeys: String, CodingKey { case profile }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profile = c.lossy(.profile)
    }
}

// MARK: - Комментарии

struct Comment: Decodable, Identifiable, Hashable {
    var id: Int = 0
    var message: String?
    var timestamp: Double?
    var voteCount: Int?
    var isSpoiler: Bool?
    var isDeleted: Bool?
    var profile: ProfileBrief?
    var vote: Int?
    var replyCount: Int?
    var isReply: Bool?

    enum CodingKeys: String, CodingKey { case id, message, timestamp, voteCount, isSpoiler, isDeleted, profile, vote, replyCount, isReply }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lossy(.id) ?? 0
        message = c.lossy(.message)
        timestamp = c.lossy(.timestamp)
        voteCount = c.lossy(.voteCount)
        isSpoiler = c.lossy(.isSpoiler)
        isDeleted = c.lossy(.isDeleted)
        profile = c.lossy(.profile)
        vote = c.lossy(.vote)
        replyCount = c.lossy(.replyCount)
        isReply = c.lossy(.isReply)
    }
}

/// Ответ, где важен только код результата (оценки, комментарии).
struct CodeReply: Decodable {
    var code: Int?
    enum CodingKeys: String, CodingKey { case code }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = c.lossy(.code)
    }
}

struct CommentsResponse: Decodable {
    var content: [Comment] = []
    enum CodingKeys: String, CodingKey { case content }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        content = c.lossy(.content) ?? []
    }
}
