import Foundation
import Observation
import Security

enum Keychain {
    private static let service = "dev.anix.client"

    static func set(_ value: String, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(q as CFDictionary)
    }
}

/// Вход в аккаунт Anixart. Токен — в Keychain, краткий профиль — в UserDefaults.
@MainActor
@Observable
final class AuthStore {
    var token: String = ""
    var profile: ProfileBrief?

    var isLoggedIn: Bool { !token.isEmpty }

    init() {
        token = Keychain.get("token") ?? ""
        if let d = UserDefaults.standard.data(forKey: "anix.profile"),
           let p = try? JSONDecoder().decode(ProfileBrief.self, from: d) {
            profile = p
        }
        APIClient.shared.token = token
    }

    /// Возвращает текст ошибки или nil при успехе.
    func signIn(login: String, password: String) async -> String? {
        do {
            let r = try await AnixAPI.signIn(login: login, password: password)
            if r.code == 0, let t = r.profileToken?.token, !t.isEmpty {
                complete(token: t, profile: r.profile)
                return nil
            }
            switch r.code {
            case 2: return L("Профиль не найден")
            case 3: return L("Неверный пароль")
            default: return L("Не удалось войти (код %@)", r.code.map(String.init) ?? "—")
            }
        } catch {
            return error.localizedDescription
        }
    }

    /// Сохраняет вход (после входа и регистрации).
    func complete(token t: String, profile p: ProfileBrief?) {
        token = t
        profile = p
        Keychain.set(t, for: "token")
        saveProfile()
        APIClient.shared.token = t
    }

    /// Меняет только токен (после смены пароля сервер выдаёт новый).
    func replaceToken(_ t: String) {
        token = t
        Keychain.set(t, for: "token")
        APIClient.shared.token = t
    }

    /// Правка сохранённого профиля (ник, аватар, статус).
    func patchProfile(_ change: (inout ProfileBrief) -> Void) {
        guard var p = profile else { return }
        change(&p)
        profile = p
        saveProfile()
    }

    private func saveProfile() {
        if let p = profile, let d = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(d, forKey: "anix.profile")
        }
    }

    func signOut() {
        token = ""
        profile = nil
        Keychain.delete("token")
        UserDefaults.standard.removeObject(forKey: "anix.profile")
        APIClient.shared.token = ""
    }
}
