import Observation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case ru, en

    var id: String { rawValue }
    var title: String { self == .ru ? "Русский" : "English" }
    var locale: Locale { Locale(identifier: rawValue) }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case standard, light, oled, red

    var id: String { rawValue }
    var scheme: ColorScheme { self == .light ? .light : .dark }

    var title: String {
        switch self {
        case .standard: return "Стандартная"
        case .light: return "Светлая"
        case .oled: return "OLED"
        case .red: return "Red"
        }
    }

    var subtitle: String {
        switch self {
        case .standard: return "Тёмная с подсветкой"
        case .light: return "Белая, со стеклом"
        case .oled: return "Чёрная, для OLED"
        case .red: return "Чёрная с красным свечением"
        }
    }

    /// Основа фона.
    var base: Color {
        switch self {
        case .standard: return Color(red: 0.04, green: 0.04, blue: 0.07)
        case .light: return Color(red: 0.975, green: 0.96, blue: 0.965)
        case .oled, .red: return .black
        }
    }

    /// Цветные подсветки по углам: (верх справа, низ слева).
    var glows: (Color, Color) {
        switch self {
        case .standard:
            return (Theme.accent.opacity(0.28), Color.indigo.opacity(0.25))
        case .light:
            return (Theme.accent.opacity(0.20), Color(red: 1.0, green: 0.62, blue: 0.70).opacity(0.28))
        case .oled, .red:
            return (Color(red: 0.62, green: 0.06, blue: 0.14).opacity(0.38), Color(red: 0.36, green: 0.02, blue: 0.10).opacity(0.30))
        }
    }

    /// Образцы для выбора темы.
    var swatch: [Color] {
        switch self {
        case .standard: return [Color(red: 0.04, green: 0.04, blue: 0.07), Color(red: 0.25, green: 0.12, blue: 0.2)]
        case .light: return [Color(red: 0.99, green: 0.97, blue: 0.97), Color(red: 1.0, green: 0.78, blue: 0.82)]
        case .oled: return [.black, Color(red: 0.12, green: 0.12, blue: 0.12)]
        case .red: return [.black, Color(red: 0.45, green: 0.04, blue: 0.1)]
        }
    }
}

/// Настройки приложения: язык и тема. Хранятся в UserDefaults.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private(set) var language: AppLanguage
    private(set) var theme: AppTheme
    /// Выбранная вкладка: хранится здесь, чтобы смена языка не возвращала на главную.
    var selectedTab = 0

    init() {
        let d = UserDefaults.standard
        language = AppLanguage(rawValue: d.string(forKey: "app.language") ?? "") ?? .ru
        theme = AppTheme(rawValue: d.string(forKey: "app.theme") ?? "") ?? .standard
    }

    func setLanguage(_ l: AppLanguage) {
        language = l
        UserDefaults.standard.set(l.rawValue, forKey: "app.language")
    }

    func setTheme(_ t: AppTheme) {
        theme = t
        UserDefaults.standard.set(t.rawValue, forKey: "app.theme")
    }
}

// MARK: - Перевод строк

/// Строка на выбранном языке. Ключ — русский текст; перевод лежит в en.lproj/Localizable.strings.
/// Для литералов в `Text("…")` SwiftUI переводит сам (по языку из окружения), эта функция — для обычных строк.
func L(_ key: String) -> String {
    let code = UserDefaults.standard.string(forKey: "app.language") ?? "ru"
    guard code != "ru",
          let path = Bundle.main.path(forResource: code, ofType: "lproj"),
          let bundle = Bundle(path: path)
    else { return key }
    return bundle.localizedString(forKey: key, value: key, table: nil)
}

func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}

// MARK: - Обновление списков

/// Счётчик изменений избранного и папок: «Закладки» перезагружают списки, когда сервер принял изменение.
@MainActor
@Observable
final class LibraryEvents {
    static let shared = LibraryEvents()
    var revision = 0
    func changed() { revision += 1 }
}

// MARK: - Очистка кеша

/// Удаляет всё, что приложение сохранило на телефоне: картинки, отметки и места просмотра, данные аккаунта.
/// Язык, тема и «Альтернативное соединение» остаются.
@MainActor
enum CacheCleaner {
    static func clearAll(auth: AuthStore) {
        auth.signOut()
        ImageLoader.shared.clearCache()
        URLCache.shared.removeAllCachedResponses()
        TranslationCache.store = [:]

        let defaults = UserDefaults.standard
        let prefixes = ["watched.", "resume.", "choice.", "anix."]
        for key in defaults.dictionaryRepresentation().keys where prefixes.contains(where: { key.hasPrefix($0) }) {
            defaults.removeObject(forKey: key)
        }

        let fm = FileManager.default
        var dirs: [URL] = [URL(fileURLWithPath: NSTemporaryDirectory())]
        if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first { dirs.append(caches) }
        for dir in dirs {
            for item in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                try? fm.removeItem(at: item)
            }
        }

        let diag = ImageDiagnostics.shared
        diag.successes = 0
        diag.failures = 0
        diag.viaMirror = 0
        diag.noURL = 0
        diag.lastFailure = nil
    }
}
