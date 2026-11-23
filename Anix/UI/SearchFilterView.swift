import SwiftUI

/// Фильтр каталога: те же поля и значения, что в оригинальном клиенте (формы `formToRequest`).
struct SearchFilter: Hashable {
    var genres: [String] = []
    /// 1 — хотя бы один жанр, 0 — все выбранные, 2 — без выбранных
    var genresMode = 1
    var category = 0
    var status = 0
    var season = 0
    var country = 0
    /// 0 — «неважно»
    var startYear = 0
    var endYear = 0
    /// 1...5 → 0+, 6+, 12+, 16+, 18+
    var ageRatings: [Int] = []
    var sort = 0

    static let categories = ["Неважно", "Сериал", "Полнометражный фильм", "OVA", "Дорама"]
    static let statuses = ["Неважно", "Вышел", "Выходит", "Анонс"]
    static let seasons = ["Неважно", "Зима", "Весна", "Лето", "Осень"]
    static let countries = ["Неважно", "Япония", "Китай", "Южная Корея"]
    static let ages = ["0+", "6+", "12+", "16+", "18+"]
    /// Название сортировки и значение `sort` для API
    static let sorts: [(String, Int)] = [
        ("По дате добавления ▼", 0), ("По дате добавления ▲", 4),
        ("По рейтингу ▼", 1), ("По рейтингу ▲", 5),
        ("По годам ▼", 2), ("По годам ▲", 6),
        ("По популярности ▼", 3), ("По популярности ▲", 7),
    ]

    static let genreGroups: [(title: String?, items: [String])] = [
        (nil, ["авангард", "гурман", "драма", "комедия", "повседневность", "приключения", "романтика",
               "сверхъестественное", "спорт", "тайна", "триллер", "ужасы", "фантастика", "фэнтези", "экшен",
               "эротика", "этти"]),
        ("Аудитория", ["детское", "дзёсей", "сэйнэн", "сёдзё", "сёдзё-ай", "сёнен", "сёнен-ай"]),
        ("Тематика", ["CGDCT", "антропоморфизм", "боевые искусства", "вампиры", "взрослые персонажи", "видеоигры",
                      "военное", "выживание", "гарем", "гонки", "городское фэнтези", "гэг-юмор", "детектив",
                      "жестокость", "забота о детях", "злодейка", "игра с высокими ставками", "идолы (жен.)",
                      "идолы (муж.)", "изобразительное искусство", "исполнительское искусство", "исторический",
                      "исэкай", "иясикэй", "командный спорт", "космос", "кроссдрессинг", "культура отаку",
                      "любовный многоугольник", "магическая смена пола", "махо-сёдзё", "медицина", "меха",
                      "мифология", "музыка", "образовательное", "организованная преступность", "пародия",
                      "питомцы", "психологическое", "путешествие во времени", "работа", "реверс-гарем",
                      "реинкарнация", "романтический подтекст", "самураи", "спортивные единоборства",
                      "стратегические игры", "супер сила", "удостоено наград", "хулиганы", "школа", "шоу-бизнес"]),
    ]

    var isActive: Bool { self != SearchFilter() }

    /// Количество включённых условий (для значка на кнопке).
    var activeCount: Int {
        var n = 0
        if !genres.isEmpty { n += 1 }
        if category > 0 { n += 1 }
        if status > 0 { n += 1 }
        if season > 0 { n += 1 }
        if country > 0 { n += 1 }
        if startYear > 0 || endYear > 0 { n += 1 }
        if !ageRatings.isEmpty { n += 1 }
        if sort > 0 { n += 1 }
        return n
    }

    /// Поля запроса `filter/{page}` поверх пустого фильтра.
    var patch: [String: Any] {
        var p: [String: Any] = [:]
        if category > 0 { p["category_id"] = category }
        if status > 0 { p["status_id"] = status }
        if season > 0 { p["season"] = season }
        if country > 0 { p["country"] = Self.countries[country] }
        if startYear > 0 { p["start_year"] = startYear }
        if endYear > 0 { p["end_year"] = endYear }
        if !genres.isEmpty {
            p["genres"] = genres
            p["genres_mode"] = genresMode
            p["is_genres_exclude_mode_enabled"] = genresMode == 2
        }
        if !ageRatings.isEmpty { p["age_ratings"] = ageRatings.sorted() }
        p["sort"] = Self.sorts[min(sort, Self.sorts.count - 1)].1
        return p
    }
}

// MARK: - Экран фильтра

struct SearchFilterSheet: View {
    @Binding var filter: SearchFilter
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss

    private static let maxYear = Calendar.current.component(.year, from: Date()) + 2

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    genresRow
                    picker("Категория", SearchFilter.categories, $filter.category)
                    picker("Статус", SearchFilter.statuses, $filter.status)
                    picker("Сезон", SearchFilter.seasons, $filter.season)
                    picker("Страна", SearchFilter.countries, $filter.country)
                    yearsRow
                    agesRow
                    picker("Сортировка", SearchFilter.sorts.map(\.0), $filter.sort)

                    PrimaryButton("Показать") {
                        dismiss()
                        onApply()
                    }
                    .padding(.top, 6)
                }
                .padding(20)
            }
            .background { AmbientBackground() }
            .navigationTitle("Фильтр")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сбросить") { filter = SearchFilter() }
                        .disabled(!filter.isActive)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Строки

    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedStringKey(title)).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 22)
    }

    private func picker(_ title: String, _ options: [String], _ selection: Binding<Int>) -> some View {
        card(title) {
            Menu {
                Picker(LocalizedStringKey(title), selection: selection) {
                    ForEach(options.indices, id: \.self) { i in
                        Text(LocalizedStringKey(options[i])).tag(i)
                    }
                }
            } label: {
                HStack {
                    Text(LocalizedStringKey(options[min(selection.wrappedValue, options.count - 1)])).font(.body.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
            }
        }
    }

    private var genresRow: some View {
        card("Жанры") {
            NavigationLink {
                GenrePickerView(selected: $filter.genres, mode: $filter.genresMode)
            } label: {
                HStack {
                    Text(filter.genres.isEmpty ? L("Неважно") : filter.genres.map { L($0) }.joined(separator: ", "))
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var yearsRow: some View {
        card("Годы выхода") {
            HStack(spacing: 10) {
                yearMenu(selection: Binding(
                    get: { filter.startYear },
                    set: { v in
                        filter.startYear = v
                        if v > 0 && filter.endYear == 0 { filter.endYear = Self.maxYear }
                        if v == 0 { filter.endYear = 0 }
                    }
                ))
                Text("—").foregroundStyle(.secondary)
                yearMenu(selection: Binding(
                    get: { filter.endYear },
                    set: { v in
                        filter.endYear = v
                        if v > 0 && filter.startYear == 0 { filter.startYear = 1917 }
                        if v == 0 { filter.startYear = 0 }
                    }
                ))
            }
        }
    }

    private func yearMenu(selection: Binding<Int>) -> some View {
        Menu {
            Picker("Год", selection: selection) {
                Text("Неважно").tag(0)
                ForEach(Array(stride(from: Self.maxYear, through: 1917, by: -1)), id: \.self) { y in
                    Text(String(y)).tag(y)
                }
            }
        } label: {
            HStack {
                Text(selection.wrappedValue == 0 ? L("Неважно") : String(selection.wrappedValue))
                    .font(.body.weight(.medium))
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .glassBackground(Capsule(), interactive: true)
            .contentShape(Capsule())
        }
        .frame(maxWidth: .infinity)
    }

    private var agesRow: some View {
        card("Возрастное ограничение") {
            FlowLayout(spacing: 8) {
                ForEach(SearchFilter.ages.indices, id: \.self) { i in
                    let value = i + 1
                    GlassChip(title: SearchFilter.ages[i], selected: filter.ageRatings.contains(value)) {
                        if let at = filter.ageRatings.firstIndex(of: value) {
                            filter.ageRatings.remove(at: at)
                        } else {
                            filter.ageRatings.append(value)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Выбор жанров

struct GenrePickerView: View {
    @Binding var selected: [String]
    @Binding var mode: Int

    @State private var query = ""

    private static let modes: [(Int, String)] = [(1, "Хотя бы один"), (0, "Все выбранные"), (2, "Без выбранных")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FlowLayout(spacing: 8) {
                    ForEach(Self.modes, id: \.0) { m in
                        GlassChip(title: L(m.1), selected: mode == m.0) { mode = m.0 }
                    }
                }
                if mode == 0 && selected.count > 3 {
                    Text("Выбрано слишком много жанров — результатов может не быть.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(SearchFilter.genreGroups.indices, id: \.self) { g in
                    let group = SearchFilter.genreGroups[g]
                    let items = group.items.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) || L($0).localizedCaseInsensitiveContains(query) }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.title.map { L($0) } ?? L("Жанры"))
                                .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                            FlowLayout(spacing: 8) {
                                ForEach(items, id: \.self) { name in
                                    GlassChip(title: L(name), selected: selected.contains(name)) {
                                        if let at = selected.firstIndex(of: name) {
                                            selected.remove(at: at)
                                        } else {
                                            selected.append(name)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background { AmbientBackground() }
        .navigationTitle("Жанры")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Поиск жанра")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Сбросить") { selected = [] }.disabled(selected.isEmpty)
            }
        }
    }
}

// MARK: - Результаты фильтра

struct FilteredResultsView: View {
    let filter: SearchFilter

    var body: some View {
        PagedList(
            loader: { try await AnixAPI.filter(page: $0, patch: filter.patch) },
            emptyTitle: "Ничего не найдено",
            emptyIcon: "line.3.horizontal.decrease.circle"
        )
        .background { AmbientBackground() }
        .navigationTitle("Результаты фильтра")
        .navigationBarTitleDisplayMode(.inline)
    }
}
