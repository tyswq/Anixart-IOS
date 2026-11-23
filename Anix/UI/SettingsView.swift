import SwiftUI

/// Настройки: язык, тема, альтернативное соединение; «О приложении» — внизу.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AuthStore.self) private var auth
    @State private var preferMirror = ImageLoader.preferMirror
    @State private var confirmClear = false
    @State private var note: String?

    init() {}

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                languageCard
                themeCard
                connectionCard
                cacheCard
                aboutCard
            }
            .padding(20)
            .padding(.bottom, 30)
        }
        .background { AmbientBackground() }
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
        .banner($note)
        .confirmationDialog("Очистить кеш?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Очистить и выйти из аккаунта", role: .destructive) {
                CacheCleaner.clearAll(auth: auth)
                preferMirror = ImageLoader.preferMirror
                note = L("Кеш очищен")
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Будут удалены картинки, отметки просмотренных серий, места воспроизведения и данные аккаунта на телефоне. Вы выйдете из аккаунта.")
        }
    }

    // MARK: Язык

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Язык", systemImage: "globe").font(.headline)
            GlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(AppLanguage.allCases) { lang in
                        GlassChip(title: lang.title, selected: settings.language == lang) {
                            settings.setLanguage(lang)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            Text("Меняется язык интерфейса. Названия, описания и комментарии приходят с сервера на русском.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 24)
    }

    // MARK: Тема

    private var themeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Тема", systemImage: "paintpalette").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(AppTheme.allCases) { theme in
                    themeTile(theme)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 24)
    }

    private func themeTile(_ theme: AppTheme) -> some View {
        let selected = settings.theme == theme
        return Button {
            withAnimation(.smooth(duration: 0.3)) { settings.setTheme(theme) }
        } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: theme.swatch, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 64)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(selected ? Theme.accent : Color.primary.opacity(0.18), lineWidth: selected ? 2.5 : 1)
                    }
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.accent, .white)
                                .padding(5)
                        }
                    }
                Text(LocalizedStringKey(theme.title)).font(.footnote.weight(.semibold))
                Text(LocalizedStringKey(theme.subtitle))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(minHeight: 24, alignment: .top)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
    }

    // MARK: Альтернативное соединение

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $preferMirror) {
                Label("Альтернативное соединение", systemImage: "network").font(.headline)
            }
            .tint(Theme.accent)
            .onChange(of: preferMirror) { _, v in ImageLoader.preferMirror = v }
            Text("Картинки загружаются через зеркало. Включите, если обложки не отображаются.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 24)
    }

    // MARK: Кеш

    private var cacheCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Кеш", systemImage: "trash").font(.headline)
            Text("Удаляет всё, что приложение сохранило на телефоне, включая данные аккаунта. После этого нужно будет войти заново.")
                .font(.caption).foregroundStyle(.secondary)
            Button {
                confirmClear = true
            } label: {
                Text("Очистить кеш")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .glassBackground(Capsule(), interactive: true)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 24)
    }

    // MARK: О приложении

    private var aboutCard: some View {
        let diag = ImageDiagnostics.shared
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "1.0"
        let build = (info?["CFBundleVersion"] as? String) ?? "1"
        var stats = L("Картинки: загружено %ld (через зеркало %ld), ошибок %ld, без адреса %ld.",
                      diag.successes, diag.viaMirror, diag.failures, diag.noURL)
        if let last = diag.lastFailure { stats += " " + L("Последняя: %@", last) }
        if let sync = diag.lastSync { stats += "\nСинхронизация — " + sync }
        return VStack(alignment: .leading, spacing: 8) {
            Label("О приложении", systemImage: "info.circle").font(.headline)
            Text("Неофициальный клиент Anixart, основанный на проекте arigandores/anix. Не связан с разработчиками Anixart и не одобрен ими.")
                .font(.footnote).foregroundStyle(.secondary)
            Text(L("Версия %@ (%@)", version, build))
                .font(.caption).foregroundStyle(.secondary)
            Text(stats)
                .font(.caption2).foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 24)
    }
}
