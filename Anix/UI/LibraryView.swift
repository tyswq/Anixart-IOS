import SwiftUI

enum LibraryTab: Int, CaseIterable, Identifiable {
    case watching = 1, plan, completed, hold, dropped, favorites = 100

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .watching: return L("Смотрю")
        case .plan: return L("В планах")
        case .completed: return L("Просмотрено")
        case .hold: return L("Отложено")
        case .dropped: return L("Брошено")
        case .favorites: return L("Избранное")
        }
    }

    var icon: String {
        switch self {
        case .watching: return "play.circle"
        case .plan: return "calendar"
        case .completed: return "checkmark.circle"
        case .hold: return "pause.circle"
        case .dropped: return "xmark.circle"
        case .favorites: return "heart"
        }
    }

    func load(page: Int) async throws -> [Release] {
        self == .favorites
            ? try await AnixAPI.favorites(page: page)
            : try await AnixAPI.profileList(status: rawValue, page: page)
    }
}

struct LibraryView: View {
    @Environment(AuthStore.self) private var auth
    @State private var selection: LibraryTab = .watching
    @State private var showLogin = false
    @State private var events = LibraryEvents.shared

    var body: some View {
        NavigationStack {
            Group {
                if auth.isLoggedIn {
                    PagedList(
                        loader: { try await selection.load(page: $0) },
                        emptyTitle: "В этом списке пока пусто",
                        emptyIcon: selection.icon
                    )
                    .id("\(selection.rawValue)-\(auth.token)-\(events.revision)")
                } else {
                    VStack(spacing: 18) {
                        EmptyState(
                            icon: "bookmark.circle",
                            title: "Ваши закладки",
                            subtitle: "Войдите в аккаунт Anixart — списки, избранное и история будут общими с приложением."
                        )
                        Button {
                            showLogin = true
                        } label: {
                            Text("Войти")
                                .font(.headline).foregroundStyle(.white)
                                .padding(.horizontal, 40).padding(.vertical, 14)
                                .glassBackground(Capsule(), interactive: true, tint: Theme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if auth.isLoggedIn { chips }
            }
            .background { AmbientBackground() }
            .navigationTitle("Закладки")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showLogin) { LoginView() }
            .appDestinations()
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(LibraryTab.allCases) { tab in
                        GlassChip(title: tab.title, systemImage: tab.icon, selected: selection == tab) {
                            withAnimation(.smooth) { selection = tab }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
