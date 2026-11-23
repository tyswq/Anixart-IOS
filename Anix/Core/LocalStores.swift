import Foundation

/// Запись «Продолжить просмотр»: что смотрели последним, на какой серии и сколько просмотрено.
struct ContinueEntry: Codable, Identifiable, Hashable {
    var rid: Int
    var title: String
    var image: String?
    var sid: Int
    var position: Int
    /// доля просмотренного в серии, 0...1
    var fraction: Double = 0
    var date: Double

    var id: Int { rid }

    /// Серия досмотрена почти до конца — продолжать нужно со следующей.
    var finished: Bool { fraction > 0.95 }
}

/// Последние начатые релизы (хранятся на телефоне, `UserDefaults`).
enum ContinueStore {
    private static let key = "anix.continue"
    private static let limit = 20

    static func load() -> [ContinueEntry] {
        guard let d = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([ContinueEntry].self, from: d) else { return [] }
        return list
    }

    private static func save(_ list: [ContinueEntry]) {
        if let d = try? JSONEncoder().encode(list) { UserDefaults.standard.set(d, forKey: key) }
    }

    /// Запуск серии: релиз поднимается в начало списка.
    static func record(rid: Int, title: String?, image: String?, sid: Int, position: Int) {
        var list = load()
        let old = list.first { $0.rid == rid }
        list.removeAll { $0.rid == rid }
        let sameEpisode = old?.position == position && old?.sid == sid
        let entry = ContinueEntry(
            rid: rid,
            title: (title?.isEmpty == false ? title : nil) ?? old?.title ?? "",
            image: image ?? old?.image,
            sid: sid,
            position: position,
            fraction: sameEpisode ? (old?.fraction ?? 0) : 0,
            date: Date().timeIntervalSince1970
        )
        list.insert(entry, at: 0)
        save(Array(list.prefix(limit)))
    }

    /// Прогресс текущей серии (вызывается плеером).
    static func progress(rid: Int, sid: Int, position: Int, seconds: Double, duration: Double) {
        guard duration > 0 else { return }
        var list = load()
        guard let i = list.firstIndex(where: { $0.rid == rid }) else { return }
        guard list[i].position == position, list[i].sid == sid else { return }
        list[i].fraction = max(0, min(seconds / duration, 1))
        save(list)
    }

    static func remove(_ rid: Int) {
        save(load().filter { $0.rid != rid })
    }
}

/// История поисковых запросов.
enum SearchHistory {
    private static let key = "anix.searchHistory"
    private static let limit = 15

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func add(_ raw: String) {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }
        var list = load().filter { $0.caseInsensitiveCompare(q) != .orderedSame }
        list.insert(q, at: 0)
        UserDefaults.standard.set(Array(list.prefix(limit)), forKey: key)
    }

    static func remove(_ q: String) {
        UserDefaults.standard.set(load().filter { $0 != q }, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
