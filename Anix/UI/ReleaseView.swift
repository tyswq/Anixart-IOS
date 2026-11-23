import Observation
import SwiftUI
import Translation

private let listNames = ["Не смотрю", "Смотрю", "В планах", "Просмотрено", "Отложено", "Брошено"]

struct ReleaseView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(AppSettings.self) private var settings
    @State private var trConfig: TranslationSession.Configuration?
    @State private var trVersion = 0
    @State private var release: Release
    @State private var expanded = false
    @State private var showLogin = false
    @State private var loaded = false
    @State private var loadError: String?
    @State private var note: String?
    // избранное и папка живут в отдельной модели: экран перерисовывается сразу, запросы уходят следом
    @State private var acts: ReleaseActions

    init(release: Release) {
        _release = State(initialValue: release)
        _acts = State(initialValue: ReleaseActions(release))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if !loaded, let loadError {
                    ErrorState(message: loadError) { Task { await reload() } }
                }
                header
                actions
                ratingCard
                stats
                description
                info
                genres
                if let rel = release.related {
                    NavigationLink(value: RelatedRoute(info: rel)) {
                        HStack {
                            Image(systemName: "rectangle.stack.fill")
                            Text("Связанные релизы").font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .glassCard(radius: 22, interactive: true)
                        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                NavigationLink(value: CommentsRoute(release: release)) {
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                        Text("Комментарии").font(.headline)
                        if let n = release.commentCount, n > 0 { Text("\(n)").foregroundStyle(.secondary) }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .glassCard(radius: 22, interactive: true)
                    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background { AmbientBackground(image: release.image) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let url = URL(string: "https://anixart.tv/release/\(release.id)") {
                    ShareLink(item: url)
                }
            }
        }
        .task { await reload() }
        .translationTask(trConfig) { session in await translate(with: session) }
        .banner($note)
        .sheet(isPresented: $showLogin) { LoginView() }
    }

    // MARK: Блоки

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            Poster(url: release.image, radius: 22)
                .frame(width: 132, height: 198)
                .shadow(color: .black.opacity(0.5), radius: 18, y: 10)
            VStack(alignment: .leading, spacing: 8) {
                Text(headerTitle).font(.title2.weight(.bold)).lineLimit(4)
                if let o = release.altTitle {
                    Text(o).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 6) {
                    if let c = release.category?.name { tag(tr(c)) }
                    if let s = release.status?.name { tag(tr(s)) }
                    if let a = release.ageText { tag(a) }
                }
                if let g = release.gradeText {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                        Text(g).font(.title3.weight(.bold))
                        if let v = release.voteCount {
                            Text("· \(v.formatted()) оценок").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private var headerTitle: String {
        if release.titleRu == nil && release.titleOriginal == nil && !loaded { return L("Загрузка…") }
        return release.displayTitle
    }

    private func tag(_ s: String) -> some View {
        Text(s)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .glassBackground(Capsule())
    }

    private var currentStatus: Int { acts.listStatus }

    private var actions: some View {
        GlassGroup(spacing: 12) {
            HStack(spacing: 12) {
                NavigationLink(value: WatchRoute(release: release)) {
                    Label(LocalizedStringKey(release.isAnnounce && (release.episodesReleased ?? 0) == 0 ? "Анонс" : "Смотреть"), systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .glassBackground(Capsule(), interactive: true, tint: Theme.accent)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                Menu {
                    Picker("Список", selection: Binding(
                        get: { acts.listStatus },
                        set: { v in setList(v) }
                    )) {
                        ForEach(0..<listNames.count, id: \.self) { i in
                            Text(LocalizedStringKey(listNames[i])).tag(i)
                        }
                    }
                } label: {
                    Image(systemName: currentStatus == 0 ? "bookmark" : "bookmark.fill")
                        .font(.title3)
                        .foregroundStyle(Color.primary)
                        .frame(width: 54, height: 54)
                        .glassBackground(Circle(), interactive: true)
                }
                .id(currentStatus)

                Button {
                    toggleFavorite()
                } label: {
                    Image(systemName: acts.isFavorite ? "heart.fill" : "heart")
                        .font(.title3)
                        .foregroundStyle(acts.isFavorite ? Theme.accent : Color.primary)
                        .frame(width: 54, height: 54)
                        .glassBackground(Circle(), interactive: true)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact, trigger: acts.isFavorite)
            }
        }
    }

    /// Оценка релиза звёздами: нажатие ставит, повторное нажатие на ту же звезду снимает.
    private var ratingCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text(acts.yourVote > 0 ? L("Ваша оценка: %ld из 5", acts.yourVote) : L("Оцените релиз"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { i in
                    Button {
                        guard auth.isLoggedIn else { showLogin = true; return }
                        acts.setVote(i)
                    } label: {
                        Image(systemName: i <= acts.yourVote ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(i <= acts.yourVote ? Color.orange : Color.secondary)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .sensoryFeedback(.selection, trigger: acts.yourVote)
        }
        .padding(16)
        .glassCard(radius: 22)
    }

    @ViewBuilder
    private var stats: some View {
        let items: [(String, Int?)] = [
            ("Смотрят", release.watchingCount), ("В планах", release.planCount),
            ("Просмотрено", release.completedCount), ("Отложено", release.holdOnCount), ("Брошено", release.droppedCount),
        ]
        if items.contains(where: { ($0.1 ?? 0) > 0 }) {
            HStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { i in
                    VStack(spacing: 3) {
                        Text((items[i].1 ?? 0).formatted(.number.notation(.compactName))).font(.headline.monospacedDigit())
                        Text(LocalizedStringKey(items[i].0)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 14)
            .glassCard(radius: 22)
        }
    }

    @ViewBuilder
    private var description: some View {
        if let d = release.desc, !d.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(tr(d))
                    .font(.callout)
                    .lineLimit(expanded ? nil : 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(LocalizedStringKey(expanded ? "Свернуть" : "Читать полностью"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(16)
            .glassCard(radius: 22)
            .onTapGesture { withAnimation(.smooth) { expanded.toggle() } }
        }
    }

    @ViewBuilder
    private var info: some View {
        let rows = infoRows
        if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: rows[i].0).frame(width: 22).foregroundStyle(Theme.accent)
                        Text(rows[i].1).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 11)
                    if i < rows.count - 1 { Divider().opacity(0.4) }
                }
            }
            .padding(.horizontal, 16)
            .glassCard(radius: 22)
        }
    }

    private var infoRows: [(String, String)] {
        var rows: [(String, String)] = []
        let ep = [release.episodesText, release.duration.map { L("%ld мин.", $0) }].compactMap { $0 }.joined(separator: " · ")
        if !ep.isEmpty { rows.append(("film.stack", ep)) }
        let seasonYear = [release.seasonName, release.year.map { L("%ld г.", $0) }].compactMap { $0 }.joined(separator: " ")
        let when = [release.country.map { tr($0) }, seasonYear].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        if !when.isEmpty { rows.append(("calendar", when)) }
        if let s = release.studio, !s.isEmpty { rows.append(("building.2", L("Студия %@", s))) }
        if let s = release.source, !s.isEmpty { rows.append(("book.closed", L("Первоисточник: %@", s))) }
        if let s = release.translators, !s.isEmpty { rows.append(("mic", s)) }
        if let s = release.releaseDate, !s.isEmpty { rows.append(("clock", s)) }
        return rows
    }

    @ViewBuilder
    private var genres: some View {
        let list = release.genreList
        if !list.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(list, id: \.self) { g in
                    Text(tr(g))
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .glassBackground(Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Перевод (английский интерфейс)

    /// Текст на языке интерфейса: в английском — перевод, если он уже готов.
    private func tr(_ text: String) -> String {
        _ = trVersion
        guard settings.language == .en else { return text }
        return TranslationCache.store[text] ?? text
    }

    private var translatableTexts: [String] {
        var out: [String] = []
        if let d = release.desc { out.append(d) }
        out += release.genreList
        if let c = release.category?.name { out.append(c) }
        if let s = release.status?.name { out.append(s) }
        if let c = release.country { out.append(c) }
        var seen = Set<String>()
        return out.filter { !$0.isEmpty && !TranslationCache.store.keys.contains($0) && seen.insert($0).inserted }
    }

    private func startTranslation() {
        guard settings.language == .en, !translatableTexts.isEmpty else { return }
        trConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: "ru"),
            target: Locale.Language(identifier: "en")
        )
    }

    @MainActor
    private func translate(with session: TranslationSession) async {
        let texts = translatableTexts
        guard !texts.isEmpty else { return }
        let requests = texts.enumerated().map { TranslationSession.Request(sourceText: $1, clientIdentifier: "\($0)") }
        guard let responses = try? await session.translations(from: requests) else { return }
        for r in responses {
            if let id = r.clientIdentifier, let i = Int(id), texts.indices.contains(i) {
                TranslationCache.store[texts[i]] = r.targetText
            }
        }
        trVersion += 1
    }

    // MARK: Действия

    private func reload() async {
        for _ in 0..<2 {
            do {
                let full = try await AnixAPI.release(release.id)
                release = full
                acts.apply(server: full)
                loaded = true
                loadError = nil
                startTranslation()
                return
            } catch {
                if Task.isCancelled { return }
                loadError = error.localizedDescription
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }
    }

    /// Папка меняется на экране сразу, ответ сервера не ждём.
    private func setList(_ new: Int) {
        guard auth.isLoggedIn else { showLogin = true; return }
        acts.setList(new)
    }

    /// Сердечко меняется сразу, ответ сервера не ждём.
    private func toggleFavorite() {
        guard auth.isLoggedIn else { showLogin = true; return }
        acts.toggleFavorite()
    }
}

/// Состояние сердечка и папки одного релиза. Класс с наблюдением: любое изменение сразу перерисовывает экран,
/// а запросы к серверу идут в фоне и ничего не откатывают.
@MainActor
@Observable
final class ReleaseActions {
    private let id: Int
    var isFavorite: Bool
    var listStatus: Int
    var yourVote: Int
    private var voteServer: Int
    private var voteTouched = false
    private var voteBusy = false
    private var favServer: Bool?
    private var listServer: Int?
    private var favTouched = false
    private var listTouched = false
    private var favBusy = false
    private var listBusy = false

    init(_ r: Release) {
        id = r.id
        isFavorite = r.isFavorite == true
        listStatus = r.profileListStatus ?? 0
        yourVote = r.yourVote ?? 0
        voteServer = r.yourVote ?? 0
        favServer = isFavorite
        listServer = listStatus
    }

    /// Ответ загрузки страницы: не затирает то, что пользователь уже поменял на экране.
    func apply(server r: Release) {
        if !favTouched { isFavorite = r.isFavorite == true; favServer = isFavorite }
        if !listTouched { listStatus = r.profileListStatus ?? 0; listServer = listStatus }
        if !voteTouched { yourVote = r.yourVote ?? 0; voteServer = yourVote }
    }

    /// Оценка 1...5; та же оценка ещё раз — снять.
    func setVote(_ v: Int) {
        voteTouched = true
        yourVote = (v == yourVote) ? 0 : v
        guard !voteBusy else { return }
        voteBusy = true
        Task { await syncVote() }
    }

    private func syncVote() async {
        var failures = 0
        while failures < 3 {
            let want = yourVote
            if want == voteServer { break }
            do {
                let code: Int
                if want == 0 {
                    code = try await AnixAPI.releaseVoteDelete(id: id)
                } else {
                    code = try await AnixAPI.releaseVote(id: id, value: want)
                }
                if code != 0 { throw APIError.http(code) }
                voteServer = want
                failures = 0
                ImageDiagnostics.shared.lastSync = "оценка: \(want) — ок"
            } catch {
                failures += 1
                ImageDiagnostics.shared.lastSync = "оценка: \(error.localizedDescription)"
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
        }
        // не удалось сохранить — возвращаем то, что знает сервер
        if yourVote != voteServer { yourVote = voteServer }
        voteBusy = false
    }

    func toggleFavorite() {
        favTouched = true
        isFavorite.toggle()
        guard !favBusy else { return }
        favBusy = true
        Task { await syncFavorite() }
    }

    func setList(_ new: Int) {
        guard new != listStatus else { return }
        listTouched = true
        listStatus = new
        guard !listBusy else { return }
        listBusy = true
        Task { await syncList() }
    }

    private func syncFavorite() async {
        var failures = 0
        while failures < 3 {
            let want = isFavorite
            if let server = favServer, server == want { break }
            do {
                if want { try await AnixAPI.favAdd(id) } else { try await AnixAPI.favDelete(id) }
                favServer = want
                failures = 0
                ImageDiagnostics.shared.lastSync = "избранное: \(want ? "добавлено" : "убрано") — ок"
                LibraryEvents.shared.changed()
            } catch {
                failures += 1
                ImageDiagnostics.shared.lastSync = "избранное: \(error.localizedDescription)"
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
        }
        favBusy = false
    }

    private func syncList() async {
        var failures = 0
        while failures < 3 {
            let want = listStatus
            let server = listServer ?? 0
            if server == want { break }
            do {
                if want == 0 {
                    try await AnixAPI.listDelete(status: server, rid: id)
                } else {
                    try await AnixAPI.listAdd(status: want, rid: id)
                }
                listServer = want
                failures = 0
                ImageDiagnostics.shared.lastSync = "папка: \(want) — ок"
                LibraryEvents.shared.changed()
            } catch {
                failures += 1
                ImageDiagnostics.shared.lastSync = "папка: \(error.localizedDescription)"
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
        }
        listBusy = false
    }
}

// MARK: - Связанные релизы

/// Вся франшиза списком, как в поиске.
struct RelatedView: View {
    let info: RelatedInfo

    init(info: RelatedInfo) { self.info = info }

    var body: some View {
        PagedList(
            loader: { try await AnixAPI.related(id: info.id, page: $0) },
            emptyTitle: "Связанных релизов нет",
            emptyIcon: "rectangle.stack"
        )
        .background { AmbientBackground() }
        .navigationTitle(info.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Комментарии

struct SpoilerText: View {
    let text: String
    let isSpoiler: Bool

    init(text: String, isSpoiler: Bool) {
        self.text = text
        self.isSpoiler = isSpoiler
    }

    @State private var revealed = false

    var body: some View {
        Text(text)
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .blur(radius: isSpoiler && !revealed ? 7 : 0)
            .overlay {
                if isSpoiler && !revealed {
                    Text("Спойлер").font(.caption.weight(.bold)).padding(.horizontal, 10).padding(.vertical, 4).glassBackground(Capsule())
                }
            }
            .onTapGesture { withAnimation(.smooth) { revealed = true } }
    }
}

/// Переводы описаний и жанров, уже полученные за сеанс.
@MainActor
enum TranslationCache {
    static var store: [String: String] = [:]
}
