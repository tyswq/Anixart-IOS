import SwiftUI

/// Подборки на главной и экран «Показать все».
enum Feed: String, Hashable, CaseIterable {
    case recommendations, watching, discussing, popular, ongoing, announces, finished

    var title: String {
        switch self {
        case .recommendations: return L("Рекомендации")
        case .watching: return L("Сейчас смотрят")
        case .discussing: return L("Обсуждают")
        case .popular: return L("Популярное")
        case .ongoing: return L("Онгоинги")
        case .announces: return L("Анонсы")
        case .finished: return L("Завершённые")
        }
    }

    func load(page: Int) async throws -> [Release] {
        switch self {
        case .recommendations: return try await AnixAPI.recommendations(page: page)
        case .watching: return try await AnixAPI.watching(page: page)
        case .discussing: return page == 0 ? try await AnixAPI.discussing() : []
        case .popular: return try await AnixAPI.filter(page: page, patch: ["sort": 3])
        case .ongoing: return try await AnixAPI.filter(page: page, patch: ["status_id": 2])
        case .announces: return try await AnixAPI.filter(page: page, patch: ["status_id": 3])
        case .finished: return try await AnixAPI.filter(page: page, patch: ["status_id": 1])
        }
    }
}

struct WatchRoute: Hashable {
    let release: Release
    var autoplay: Int? = nil
}
struct CommentsRoute: Hashable { let release: Release }
struct RelatedRoute: Hashable { let info: RelatedInfo }

struct AppDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: Release.self) { ReleaseView(release: $0) }
            .navigationDestination(for: Feed.self) { FeedView(feed: $0) }
            .navigationDestination(for: WatchRoute.self) { EpisodesView(release: $0.release, autoplay: $0.autoplay) }
            .navigationDestination(for: CommentsRoute.self) { CommentsView(release: $0.release) }
            .navigationDestination(for: RelatedRoute.self) { RelatedView(info: $0.info) }
            .navigationDestination(for: LibraryTab.self) { LibraryListView(tab: $0) }
    }
}

extension View {
    func appDestinations() -> some View { modifier(AppDestinations()) }
}

struct Rail: Identifiable {
    let feed: Feed
    let items: [Release]
    var id: Feed { feed }
}

@MainActor
@Observable
final class HomeModel {
    var banners: [Banner] = []
    var rails: [Rail] = []
    var loaded = false
    var failed = false

    func load(loggedIn: Bool) async {
        async let b = try? AnixAPI.interesting()
        async let rec = fetch(.recommendations, enabled: loggedIn)
        async let watching = fetch(.watching)
        async let discussing = fetch(.discussing)
        async let ongoing = fetch(.ongoing)
        async let popular = fetch(.popular)
        async let announces = fetch(.announces)

        let bannersResult = await b ?? []
        let recResult = await rec
        let ongoingResult = await ongoing
        let popularResult = await popular
        let watchingResult = await watching
        let discussingResult = await discussing
        let announcesResult = await announces
        let all: [(Feed, [Release])] = [
            (.recommendations, recResult),
            (.ongoing, ongoingResult),
            (.popular, popularResult),
            (.watching, watchingResult),
            (.discussing, discussingResult),
            (.announces, announcesResult),
        ]
        let rails = all.filter { !$0.1.isEmpty }.map { Rail(feed: $0.0, items: $0.1) }

        if bannersResult.isEmpty && rails.isEmpty {
            failed = true
        } else {
            failed = false
            self.banners = bannersResult
            self.rails = rails
        }
        loaded = true
    }

    private func fetch(_ feed: Feed, enabled: Bool = true) async -> [Release] {
        guard enabled else { return [] }
        return (try? await feed.load(page: 0)) ?? []
    }
}

struct HomeView: View {
    @Environment(AuthStore.self) private var auth
    @State private var model = HomeModel()
    @State private var continueItems: [ContinueEntry] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if !model.loaded {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 120)
                    } else if model.failed {
                        ErrorState(message: L("Не удалось загрузить главную. Проверьте соединение.")) {
                            Task { await model.load(loggedIn: auth.isLoggedIn) }
                        }
                        .padding(.top, 80)
                    } else {
                        if !model.banners.isEmpty { BannerCarousel(banners: model.banners) }
                        if !continueItems.isEmpty { continueRail }
                        ForEach(model.rails) { rail in
                            VStack(alignment: .leading, spacing: 14) {
                                NavigationLink(value: rail.feed) { SectionHeader(title: rail.feed.title) }
                                    .buttonStyle(.plain)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 14) {
                                        ForEach(rail.items) { PosterCard(release: $0) }
                                    }
                                }
                                .contentMargins(.horizontal, 20, for: .scrollContent)
                            }
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .background { AmbientBackground() }
            .navigationTitle("Anix")
            .onAppear { continueItems = ContinueStore.load() }
            .refreshable { await model.load(loggedIn: auth.isLoggedIn) }
            .task(id: auth.token) { await model.load(loggedIn: auth.isLoggedIn) }
            .appDestinations()
        }
    }
}

extension HomeView {
    /// «Продолжить просмотр»: последние начатые релизы с полоской прогресса.
    fileprivate var continueRail: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Продолжить просмотр").font(.title3.weight(.bold))
                Spacer()
            }
            .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(continueItems) { e in
                        ContinueCard(entry: e)
                            .contextMenu {
                                Button(role: .destructive) {
                                    ContinueStore.remove(e.rid)
                                    continueItems = ContinueStore.load()
                                } label: {
                                    Label("Убрать из списка", systemImage: "xmark.circle")
                                }
                            }
                    }
                }
            }
            .contentMargins(.horizontal, 20, for: .scrollContent)
        }
    }
}

private struct ContinueCard: View {
    let entry: ContinueEntry

    var body: some View {
        // досмотрена — предлагаем следующую серию
        let target = entry.finished ? entry.position + 1 : entry.position
        let fraction = entry.finished ? 0 : entry.fraction
        var release = Release(id: entry.rid)
        release.titleRu = entry.title
        release.image = entry.image
        return NavigationLink(value: WatchRoute(release: release, autoplay: target)) {
            VStack(alignment: .leading, spacing: 8) {
                Poster(url: entry.image)
                    .frame(width: 130, height: 195)
                    .overlay(alignment: .center) {
                        Image(systemName: "play.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .environment(\.colorScheme, .dark)
                            .environment(\.forceGlass, true)
                            .glassBackground(Circle())
                    }
                    .overlay(alignment: .bottom) {
                        if fraction > 0 {
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.3))
                                    Capsule().fill(Theme.accent).frame(width: g.size.width * fraction)
                                }
                            }
                            .frame(height: 4)
                            .padding(10)
                        }
                    }
                Text(entry.title)
                    .font(.footnote.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 130, alignment: .leading)
                Text(L("Серия %ld", target))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

struct BannerCarousel: View {
    let banners: [Banner]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(banners) { banner in
                    if let id = banner.releaseId {
                        NavigationLink(value: Release(id: id)) { card(banner) }.buttonStyle(.plain)
                    } else if banner.type == 2, let u = banner.action.flatMap({ URL(string: $0) }) {
                        Link(destination: u) { card(banner) }.buttonStyle(.plain)
                    } else {
                        card(banner)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, 20, for: .scrollContent)
    }

    private func card(_ b: Banner) -> some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.primary.opacity(0.06))
            .overlay { RemoteImage(url: b.image) }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    if let t = b.title { Text(t).font(.headline).lineLimit(1) }
                    if let s = b.subtitle { Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
                .foregroundStyle(.white)
                .environment(\.colorScheme, .dark)
                .environment(\.forceGlass, true)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(radius: 20)
                .padding(10)
                .opacity(b.title == nil && b.subtitle == nil ? 0 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .containerRelativeFrame(.horizontal) { w, _ in w - 40 }
            .frame(height: 210)
    }
}

struct FeedView: View {
    let feed: Feed

    var body: some View {
        PagedList(loader: { try await feed.load(page: $0) })
            .background { AmbientBackground() }
            .navigationTitle(feed.title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
