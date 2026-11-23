import SwiftUI
import WebKit

struct PlayerItem: Identifiable {
    let id = UUID()
    let title: String
    let episode: String
    let video: ResolvedVideo
    let rid: Int
    let sid: Int
    let position: Int
}

struct WebItem: Identifiable {
    let id = UUID()
    let url: URL
}

private enum Playable {
    case player(PlayerItem)
    case web(WebItem)
}

private enum PlaybackError: LocalizedError {
    case noLink
    var errorDescription: String? { L("У этой серии нет ссылки на видео") }
}

private struct Choice: Codable {
    var typeId: Int
    var sourceId: Int

    static func load(_ rid: Int) -> Choice? {
        guard let d = UserDefaults.standard.data(forKey: "choice.\(rid)") else { return nil }
        return try? JSONDecoder().decode(Choice.self, from: d)
    }

    func save(_ rid: Int) {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: "choice.\(rid)") }
    }
}

struct EpisodesView: View {
    let release: Release
    /// Номер серии, которую запустить сразу после загрузки («Продолжить просмотр»).
    let autoplay: Int?

    init(release: Release, autoplay: Int? = nil) {
        self.release = release
        self.autoplay = autoplay
    }

    @Environment(AuthStore.self) private var auth

    private enum Phase {
        case loading
        case ready
        case failed(String)
    }

    @State private var types: [EpisodeType] = []
    @State private var sources: [EpisodeSource] = []
    @State private var episodes: [Episode] = []
    @State private var type: EpisodeType?
    @State private var source: EpisodeSource?
    @State private var phase: Phase = .loading
    @State private var resolving: Int?
    @State private var player: PlayerItem?
    @State private var web: WebItem?
    @State private var message: String?
    @State private var watched: Set<Int> = []
    @State private var autoplayDone = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                switch phase {
                case .loading:
                    ProgressView().padding(.top, 80)
                case .failed(let text):
                    ErrorState(message: text) { Task { await bootstrap() } }
                case .ready:
                    pickers
                    ForEach(episodes) { ep in row(ep) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .background { AmbientBackground(image: release.image) }
        .navigationTitle(release.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            watched = Set(UserDefaults.standard.array(forKey: "watched.\(release.id)") as? [Int] ?? [])
            await bootstrap()
            if let a = autoplay, !autoplayDone, case .ready = phase {
                autoplayDone = true
                if let ep = episodes.first(where: { $0.position == a }) ?? episodes.first(where: { $0.position == a - 1 }) {
                    await play(ep)
                }
            }
        }
        .fullScreenCover(item: $player) { item in
            PlayerScreen(initial: item, loadNext: { await next(after: $0) })
        }
        .sheet(item: $web) { WebPlayerView(url: $0.url) }
        .alert(
            "Не удалось запустить",
            isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    // MARK: Выбор озвучки и источника

    private var pickers: some View {
        GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(types) { t in
                        Button {
                            Task { await choose(type: t) }
                        } label: {
                            if t.id == type?.id {
                                Label(t.name ?? "—", systemImage: "checkmark")
                            } else {
                                Text(t.name ?? "—")
                            }
                        }
                    }
                } label: {
                    pickerLabel(icon: "mic.fill", text: type?.name ?? L("Озвучка"))
                }

                Menu {
                    ForEach(sources) { s in
                        Button {
                            Task { await choose(source: s) }
                        } label: {
                            if s.id == source?.id {
                                Label(s.name ?? "—", systemImage: "checkmark")
                            } else {
                                Text(s.name ?? "—")
                            }
                        }
                    }
                } label: {
                    pickerLabel(icon: "play.rectangle.fill", text: source?.name ?? L("Источник"))
                }
            }
        }
        .padding(.bottom, 4)
    }

    private func pickerLabel(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.caption2)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .glassBackground(Capsule(), interactive: true)
    }

    // MARK: Строка серии

    private func row(_ ep: Episode) -> some View {
        let isWatched = watched.contains(ep.position)
        return HStack(spacing: 14) {
            // Кружок с номером: нажатие отмечает серию просмотренной и обратно
            Button {
                toggleWatched(ep)
            } label: {
                Text("\(ep.position)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .glassBackground(Circle(), interactive: true, tint: isWatched ? Theme.accent.opacity(0.55) : nil)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: isWatched)

            // Остальная часть строки запускает серию
            Button {
                Task { await play(ep) }
            } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ep.name ?? L("Серия %ld", ep.position)).font(.body.weight(.medium)).lineLimit(1)
                        HStack(spacing: 6) {
                            if ep.isFiller == true {
                                Text("филлер").font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2)
                                    .glassBackground(Capsule())
                            }
                            if let d = Self.date(ep.addedDate) {
                                Text(d, format: .dateTime.day().month().year())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                    if resolving == ep.position {
                        ProgressView()
                    } else {
                        Image(systemName: isWatched ? "checkmark" : "play.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(resolving != nil)
        }
        .padding(12)
        .glassCard(radius: 24)
    }

    /// Дата серии; нулевое или пустое значение (1 января 1970) не показываем.
    private static func date(_ raw: Double?) -> Date? {
        guard let raw, raw > 0 else { return nil }
        let seconds = raw > 1e11 ? raw / 1000 : raw
        return Date(timeIntervalSince1970: seconds)
    }

    // MARK: Загрузка

    private func bootstrap() async {
        phase = .loading
        do {
            types = try await AnixAPI.types(release.id)
            guard !types.isEmpty else {
                phase = .failed(L("Для этого аниме пока нет серий"))
                return
            }
            let saved = Choice.load(release.id)
            let savedType = saved.flatMap { s in types.first { $0.id == s.typeId } }
            let chosen = savedType
                ?? types.first(where: { $0.pinned == true })
                ?? types.first(where: { ($0.episodesCount ?? 1) > 0 })
                ?? types[0]
            try await load(type: chosen, preferredSource: saved?.sourceId)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func load(type t: EpisodeType, preferredSource: Int?) async throws {
        type = t
        sources = try await AnixAPI.sources(release.id, type: t.id)
        let s = sources.first(where: { $0.id == preferredSource })
            ?? sources.first(where: { ($0.episodesCount ?? 1) > 0 })
            ?? sources.first
        guard let s else {
            episodes = []
            source = nil
            phase = .failed(L("У этой озвучки нет источников"))
            return
        }
        try await load(source: s)
    }

    private func load(source s: EpisodeSource) async throws {
        guard let t = type else { return }
        source = s
        episodes = try await AnixAPI.episodes(release.id, type: t.id, source: s.id)
        Choice(typeId: t.id, sourceId: s.id).save(release.id)
        phase = .ready
    }

    private func choose(type t: EpisodeType) async {
        do { try await load(type: t, preferredSource: source?.id) } catch { message = error.localizedDescription }
    }

    private func choose(source s: EpisodeSource) async {
        do { try await load(source: s) } catch { message = error.localizedDescription }
    }

    // MARK: Воспроизведение

    private func resolve(_ ep: Episode, source: EpisodeSource) async throws -> Playable {
        var link = ep.url ?? ""
        if link.isEmpty {
            link = try await AnixAPI.episodeTarget(rid: release.id, sid: source.id, pos: ep.position) ?? ""
        }
        guard !link.isEmpty else { throw PlaybackError.noLink }
        if let video = try await VideoResolver.resolve(link) {
            return .player(PlayerItem(
                title: release.displayTitle,
                episode: L("Серия %ld", ep.position),
                video: video, rid: release.id, sid: source.id, position: ep.position
            ))
        }
        // источник без своего парсера — открываем страницу плеера
        guard let url = URL(string: link.hasPrefix("//") ? "https:" + link : link) else { throw PlaybackError.noLink }
        return .web(WebItem(url: url))
    }

    private func play(_ ep: Episode) async {
        guard let source else { return }
        resolving = ep.position
        defer { resolving = nil }
        do {
            switch try await resolve(ep, source: source) {
            case .player(let item):
                markWatched(ep.position, sid: source.id)
                recordContinue(position: ep.position, sid: source.id)
                player = item
            case .web(let item):
                markWatched(ep.position, sid: source.id)
                web = item
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func next(after item: PlayerItem) async -> PlayerItem? {
        guard let source,
              let ep = episodes.filter({ $0.position > item.position }).min(by: { $0.position < $1.position }),
              let playable = try? await resolve(ep, source: source),
              case .player(let nextItem) = playable
        else { return nil }
        markWatched(ep.position, sid: source.id)
        recordContinue(position: ep.position, sid: source.id)
        return nextItem
    }

    private func recordContinue(position: Int, sid: Int) {
        let hasTitle = release.titleRu != nil || release.titleOriginal != nil
        ContinueStore.record(
            rid: release.id, title: hasTitle ? release.displayTitle : nil,
            image: release.image, sid: sid, position: position
        )
    }

    private func toggleWatched(_ ep: Episode) {
        if watched.contains(ep.position) {
            watched.remove(ep.position)
            UserDefaults.standard.set(Array(watched), forKey: "watched.\(release.id)")
        } else if let source {
            markWatched(ep.position, sid: source.id)
        }
    }

    private func markWatched(_ position: Int, sid: Int) {
        watched.insert(position)
        UserDefaults.standard.set(Array(watched), forKey: "watched.\(release.id)")
        guard auth.isLoggedIn else { return }
        let rid = release.id
        Task {
            await AnixAPI.episodeWatch(rid: rid, sid: sid, pos: position)
            await AnixAPI.historyAdd(rid: rid, sid: sid, pos: position)
        }
    }
}

// MARK: - Веб-плеер (запасной путь)

struct WebPlayerView: View {
    let url: URL

    init(url: URL) { self.url = url }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            WebView(url: url).ignoresSafeArea()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44)
                    .glassBackground(Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .padding(16)
        }
        .background(Color.black)
    }
}

private struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.isOpaque = false
        v.backgroundColor = .black
        v.scrollView.backgroundColor = .black
        v.load(URLRequest(url: url))
        return v
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
