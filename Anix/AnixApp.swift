import AVFoundation
import SwiftUI

@main
struct AnixApp: App {
    @State private var auth = AuthStore()
    @State private var settings = AppSettings.shared

    init() {
        // звук должен идти и при выключенном беззвучном режиме, и в фоне (картинка в картинке)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        Task { await AnixAPI.toggles() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(settings.language) // при смене языка интерфейс собирается заново, строки обновляются
                .environment(auth)
                .environment(settings)
                .environment(\.locale, settings.language.locale)
                .tint(Theme.accent)
                .preferredColorScheme(settings.theme.scheme)
        }
    }
}

struct RootView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        TabView(selection: $settings.selectedTab) {
            Tab("Главная", systemImage: "house.fill", value: 0) { HomeView() }
            Tab("Закладки", systemImage: "bookmark.fill", value: 1) { LibraryView() }
            Tab("Профиль", systemImage: "person.crop.circle.fill", value: 2) { ProfileView() }
            Tab(value: 3, role: .search) { SearchView() }
        }
        .modifier(MinimizingTabBar())
    }
}

/// iOS 26: панель вкладок сворачивается при прокрутке вниз.
private struct MinimizingTabBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}
