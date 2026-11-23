import SwiftUI

// MARK: - Картинки

struct Poster: View {
    let url: String?
    var radius: CGFloat = 18

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.primary.opacity(0.06))
            .overlay { RemoteImage(url: url) }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct GradeBadge: View {
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill").font(.system(size: 9))
            Text(text).font(.caption.weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .environment(\.colorScheme, .dark)
        .environment(\.forceGlass, true)
        .glassBackground(Capsule())
    }
}

// MARK: - Карточки

struct PosterCard: View {
    let release: Release
    var width: CGFloat = 130

    var body: some View {
        NavigationLink(value: release) {
            VStack(alignment: .leading, spacing: 8) {
                Poster(url: release.image)
                    .frame(width: width, height: width * 1.5)
                    .overlay(alignment: .topLeading) {
                        if let g = release.gradeText { GradeBadge(text: g).padding(8) }
                    }
                Text(release.displayTitle)
                    .font(.footnote.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: width, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

struct ReleaseRow: View {
    let release: Release

    var body: some View {
        NavigationLink(value: release) {
            HStack(alignment: .top, spacing: 14) {
                Poster(url: release.image, radius: 14)
                    .frame(width: 74, height: 111)
                VStack(alignment: .leading, spacing: 5) {
                    Text(release.displayTitle)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let o = release.altTitle {
                        Text(o).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text(release.metaLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let g = release.gradeText { GradeBadge(text: g) }
                    if let genres = release.genres {
                        Text(genres).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(radius: 24, interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Мелочи

struct GlassChip: View {
    let title: String
    var systemImage: String?
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .glassBackground(Capsule(), interactive: true, tint: selected ? Theme.accent : nil)
        .sensoryFeedback(.selection, trigger: selected)
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title).font(.title3.weight(.bold))
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

struct ErrorState: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 38)).foregroundStyle(.secondary)
            Text(LocalizedStringKey(message)).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let retry {
                Button("Повторить", action: retry)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .glassBackground(Capsule(), interactive: true, tint: Theme.accent)
                    .buttonStyle(.plain)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 42)).foregroundStyle(.secondary)
            Text(LocalizedStringKey(title)).font(.headline)
            if let subtitle { Text(LocalizedStringKey(subtitle)).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }
}

/// Теги с переносом по строкам (жанры).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

// MARK: - Постраничный список

struct PagedList: View {
    let loader: (Int) async throws -> [Release]
    let emptyTitle: String
    let emptyIcon: String

    init(
        loader: @escaping (Int) async throws -> [Release],
        emptyTitle: String = "Здесь пока пусто",
        emptyIcon: String = "tray"
    ) {
        self.loader = loader
        self.emptyTitle = emptyTitle
        self.emptyIcon = emptyIcon
    }

    @State private var items: [Release] = []
    @State private var page = 0
    @State private var finished = false
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(items) { r in
                    ReleaseRow(release: r)
                        .onAppear {
                            if r.id == items.last?.id { Task { await loadMore() } }
                        }
                }
                if loading { ProgressView().padding() }
                if let error, items.isEmpty {
                    ErrorState(message: error) {
                        self.error = nil
                        Task { await loadMore() }
                    }
                } else if items.isEmpty, finished, !loading {
                    EmptyState(icon: emptyIcon, title: emptyTitle)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .task { if items.isEmpty { await loadMore() } }
    }

    private func loadMore() async {
        guard !loading, !finished else { return }
        loading = true
        defer { loading = false }
        do {
            let res = try await loader(page)
            let known = Set(items.map(\.id))
            let fresh = res.filter { !known.contains($0.id) }
            if fresh.isEmpty {
                finished = true
            } else {
                items += fresh
                page += 1
            }
            error = nil
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}
