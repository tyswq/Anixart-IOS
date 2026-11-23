import SwiftUI

private struct SearchSuggestion: Identifiable {
    let text: String
    let fromHistory: Bool
    var id: String { (fromHistory ? "h:" : "r:") + text }
}

struct SearchView: View {
    @State private var query = ""
    @State private var results: [Release] = []
    @State private var page = 0
    @State private var finished = false
    @State private var loading = false
    @State private var searched = false
    @State private var error: String?
    @State private var history: [String] = SearchHistory.load()
    @State private var filter = SearchFilter()
    @State private var showFilter = false
    @State private var filterResult: SearchFilter?

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if trimmed.isEmpty {
                        historyBlock
                    }
                    ForEach(results) { r in
                        ReleaseRow(release: r)
                            .onAppear { if r.id == results.last?.id { Task { await loadMore() } } }
                            .simultaneousGesture(TapGesture().onEnded { remember(trimmed) })
                    }
                    if loading { ProgressView().padding() }
                    if let error, results.isEmpty {
                        ErrorState(message: error) { Task { await reset() } }
                    } else if results.isEmpty, !loading {
                        if searched {
                            EmptyState(icon: "magnifyingglass", title: "Ничего не нашли", subtitle: "Попробуйте другое название")
                        } else if history.isEmpty {
                            EmptyState(icon: "sparkle.magnifyingglass", title: "Поиск по каталогу", subtitle: "Введите название аниме")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.immediately)
            .background { AmbientBackground() }
            .navigationTitle("Поиск")
            .searchable(text: $query, prompt: "Название аниме")
            .searchSuggestions {
                ForEach(suggestions) { s in
                    Label(s.text, systemImage: s.fromHistory ? "clock" : "magnifyingglass")
                        .searchCompletion(s.text)
                }
            }
            .onSubmit(of: .search) { remember(trimmed) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFilter = true
                    } label: {
                        Image(systemName: filter.isActive
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                            .foregroundStyle(filter.isActive ? Theme.accent : Color.primary)
                    }
                    .accessibilityLabel("Фильтр")
                }
            }
            .sheet(isPresented: $showFilter) {
                SearchFilterSheet(filter: $filter) { filterResult = filter }
            }
            .navigationDestination(item: $filterResult) { FilteredResultsView(filter: $0) }
            .task(id: query) {
                // дебаунс: пока пользователь печатает, задача отменяется
                try? await Task.sleep(nanoseconds: 400_000_000)
                if Task.isCancelled { return }
                await reset()
            }
            .appDestinations()
        }
    }

    // MARK: История и подсказки

    /// Пока строка пуста — недавние запросы; при вводе — совпадения из истории и названия из найденного.
    private var suggestions: [SearchSuggestion] {
        let q = trimmed
        if q.isEmpty {
            return history.prefix(6).map { SearchSuggestion(text: $0, fromHistory: true) }
        }
        let fromHistory = history
            .filter { $0.localizedCaseInsensitiveContains(q) && $0.caseInsensitiveCompare(q) != .orderedSame }
            .prefix(3)
            .map { SearchSuggestion(text: $0, fromHistory: true) }
        var seen = Set<String>(fromHistory.map { $0.text.lowercased() })
        seen.insert(q.lowercased())
        var titles: [SearchSuggestion] = []
        for r in results {
            let t = r.displayTitle
            if seen.insert(t.lowercased()).inserted {
                titles.append(SearchSuggestion(text: t, fromHistory: false))
            }
            if titles.count >= 5 { break }
        }
        return Array(fromHistory) + titles
    }

    @ViewBuilder
    private var historyBlock: some View {
        if !history.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("История поиска").font(.title3.weight(.bold))
                    Spacer()
                    Button("Очистить") {
                        SearchHistory.clear()
                        history = []
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                }
                VStack(spacing: 0) {
                    ForEach(history, id: \.self) { q in
                        HStack(spacing: 12) {
                            Image(systemName: "clock").foregroundStyle(.secondary)
                            Text(q).lineLimit(1)
                            Spacer()
                            Button {
                                SearchHistory.remove(q)
                                history = SearchHistory.load()
                            } label: {
                                Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                                    .frame(width: 30, height: 30)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .onTapGesture { query = q }
                    }
                }
                .padding(.vertical, 4)
                .glassCard(radius: 22)
            }
        }
    }

    private func remember(_ q: String) {
        SearchHistory.add(q)
        history = SearchHistory.load()
    }

    // MARK: Загрузка

    private func reset() async {
        let q = trimmed
        page = 0
        finished = false
        error = nil
        results = []
        guard !q.isEmpty else {
            searched = false
            return
        }
        searched = true
        await loadMore()
    }

    private func loadMore() async {
        let q = trimmed
        guard !q.isEmpty, !loading, !finished else { return }
        loading = true
        defer { loading = false }
        do {
            let res = try await AnixAPI.search(page: page, query: q)
            guard q == trimmed else { return }
            let known = Set(results.map(\.id))
            let fresh = res.filter { !known.contains($0.id) }
            if fresh.isEmpty { finished = true } else { results += fresh; page += 1 }
            error = nil
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}
