import SwiftUI

// MARK: - Общие элементы форм

struct GlassTextField: View {
    let title: String
    @Binding var text: String
    var secure = false
    var keyboard: UIKeyboardType = .default

    init(_ title: String, text: Binding<String>, secure: Bool = false, keyboard: UIKeyboardType = .default) {
        self.title = title
        self._text = text
        self.secure = secure
        self.keyboard = keyboard
    }

    var body: some View {
        Group {
            if secure {
                SecureField(LocalizedStringKey(title), text: $text)
            } else {
                TextField(LocalizedStringKey(title), text: $text).keyboardType(keyboard)
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .padding(16)
        .glassCard(radius: 20)
    }
}

struct PrimaryButton: View {
    let title: String
    var busy = false
    var enabled = true
    let action: () -> Void

    init(_ title: String, busy: Bool = false, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.busy = busy
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if busy { ProgressView().tint(.white) } else { Text(LocalizedStringKey(title)).font(.headline) }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .glassBackground(Capsule(), interactive: true, tint: Theme.accent)
            .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(busy || !enabled)
    }
}

// MARK: - Регистрация

/// Регистрация: никнейм, почта, пароль → код из письма → вход в созданный аккаунт.
struct RegisterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var auth

    private enum Step { case form, code }

    @State private var step: Step = .form
    @State private var login = ""
    @State private var email = ""
    @State private var password = ""
    @State private var password2 = ""
    @State private var agreed = false

    @State private var loginNote: String?
    @State private var loginFree = false
    @State private var suggestions: [String] = []

    @State private var error: String?
    @State private var busy = false

    @State private var hash = ""
    @State private var expires: Double = 0
    @State private var code = ""

    init() {}

    private var trimmedLogin: String { login.trimmingCharacters(in: .whitespaces) }
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespaces).lowercased() }

    private var formValid: Bool {
        (3...20).contains(trimmedLogin.count) && !trimmedEmail.isEmpty
            && (6...32).contains(password.count) && password == password2 && agreed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: step == .form ? "person.crop.circle.badge.plus" : "envelope.badge")
                        .font(.system(size: 56))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 24)
                    if step == .form { formStep } else { codeStep }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .task(id: login) { if step == .form { await checkLoginLive() } }
            .background { AmbientBackground() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(LocalizedStringKey(step == .code ? "Назад" : "Закрыть")) {
                        if step == .code { step = .form; error = nil } else { dismiss() }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
    }

    // MARK: Шаг 1 — данные

    @ViewBuilder
    private var formStep: some View {
        Text("Создать профиль").font(.title2.weight(.bold))
        Text("Аккаунт Anixart: заработает и в этом приложении, и в официальном.")
            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)

        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                GlassTextField("Никнейм (3–20 символов)", text: $login)
                    .textContentType(.username)
                if let loginNote {
                    Text(loginNote)
                        .font(.footnote)
                        .foregroundStyle(loginFree ? Color.green : Color.red)
                        .padding(.horizontal, 6)
                }
                if !suggestions.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(suggestions, id: \.self) { s in
                            GlassChip(title: s) { login = s }
                        }
                    }
                }
            }
            GlassTextField("Email", text: $email, keyboard: .emailAddress)
                .textContentType(.emailAddress)
            GlassTextField("Пароль (6–32 символа)", text: $password, secure: true)
                .textContentType(.newPassword)
            GlassTextField("Повторите пароль", text: $password2, secure: true)
                .textContentType(.newPassword)
        }

        Toggle(isOn: $agreed) {
            Text("Я принимаю пользовательское соглашение и политику конфиденциальности Anixart")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .tint(Theme.accent)

        if !password2.isEmpty && password != password2 {
            Text("Пароли не совпадают").font(.footnote).foregroundStyle(.red)
        }
        if let error {
            Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
        }

        PrimaryButton("Создать профиль", busy: busy, enabled: formValid && (loginFree || loginNote == nil)) {
            Task { await signUp() }
        }
    }

    // MARK: Шаг 2 — код из письма

    @ViewBuilder
    private var codeStep: some View {
        Text("Подтвердите почту").font(.title2.weight(.bold))
        Text("Anixart отправил код на \(trimmedEmail). Проверьте и папку «Спам».")
            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)

        TextField("Код", text: $code)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.system(size: 26, weight: .semibold, design: .monospaced))
            .padding(16)
            .glassCard(radius: 20)
            .onChange(of: code) { _, v in
                let digits = String(v.filter(\.isNumber).prefix(4))
                if digits != v { code = digits }
            }

        if let error {
            Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
        }

        PrimaryButton("Подтвердить", busy: busy, enabled: !code.isEmpty) {
            Task { await verify() }
        }

        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = Int(ceil(expires - ctx.date.timeIntervalSince1970))
            Button {
                Task { await resend() }
            } label: {
                Text(left > 0 ? L("Отправить ещё раз через %ld с", left) : L("Не получили код? Отправить ещё раз"))
                    .font(.subheadline.weight(.semibold))
                    .padding(10)
            }
            .buttonStyle(.plain)
            .disabled(left > 0 || busy)
            .opacity(left > 0 ? 0.5 : 1)
        }
    }

    // MARK: Логика

    private func signUp() async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let r = try await AccountAPI.signUp(login: trimmedLogin, email: trimmedEmail, password: password)
            switch r.code {
            case 0, 7:
                hash = r.hash ?? ""
                expires = r.codeTimestampExpires ?? 0
                code = ""
                step = .code
                if r.code == 7 { error = L("Код уже был отправлен — проверьте почту.") }
            case 2: error = L("Недопустимый никнейм")
            case 3: error = L("Неверный Email")
            case 4: error = L("Недопустимый пароль")
            case 5:
                error = L("Никнейм уже занят")
                suggestions = r.suggestedLogins ?? []
            case 6: error = L("Этот Email уже занят")
            case 8: error = L("Не удалось отправить код. Повторите попытку позднее.")
            case 9: error = L("Регистрация с этим почтовым сервисом невозможна")
            case 10: error = L("Слишком много регистраций с этого устройства. Попробуйте позже.")
            default: error = L("Не удалось создать профиль (код %@)", r.code.map(String.init) ?? "—")
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func verify() async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let r = try await AccountAPI.verify(
                login: trimmedLogin, email: trimmedEmail, password: password, hash: hash, code: code
            )
            if r.code == 0, let t = r.profileToken?.token, !t.isEmpty {
                auth.complete(token: t, profile: r.profile)
                dismiss()
                return
            }
            switch r.code {
            case 2: error = L("Недопустимый никнейм")
            case 3: error = L("Неверный Email")
            case 4: error = L("Недопустимый пароль")
            case 5: error = L("Никнейм уже занят")
            case 6: error = L("Этот Email уже занят")
            case 7: error = L("Неверный код")
            case 8: error = L("Срок действия кода истёк — запросите новый")
            case 9: error = L("Сеанс подтверждения устарел — начните заново")
            case 10: error = L("Регистрация с этим почтовым сервисом невозможна")
            case 11: error = L("Слишком много регистраций с этого устройства. Попробуйте позже.")
            default: error = L("Не удалось подтвердить (код %@)", r.code.map(String.init) ?? "—")
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func resend() async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let r = try await AccountAPI.resend(login: trimmedLogin, email: trimmedEmail, password: password, hash: hash)
            if r.code == 0 {
                expires = r.timestampExpires ?? (Date().timeIntervalSince1970 + 60)
                error = L("Новый код отправлен")
            } else if r.code == 6 {
                error = L("Новый код можно будет запросить чуть позже")
            } else {
                error = L("Не удалось отправить код (код %@)", r.code.map(String.init) ?? "—")
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension RegisterView {
    /// Проверка свободного никнейма по мере ввода (вызывается из `.task(id:)`).
    @MainActor
    fileprivate func checkLoginLive() async {
        loginFree = false
        suggestions = []
        let v = trimmedLogin
        if v.isEmpty { loginNote = nil; return }
        if v.count < 3 { loginNote = L("Никнейм слишком короткий"); return }
        if v.count > 20 { loginNote = L("Никнейм слишком длинный"); return }
        loginNote = nil
        try? await Task.sleep(nanoseconds: 450_000_000)
        if Task.isCancelled { return }
        guard let r = try? await AccountAPI.checkLogin(v), !Task.isCancelled else { return }
        if r.code == 0 && r.available == true {
            loginFree = true
            loginNote = L("Никнейм свободен")
        } else if r.code == 0 {
            loginNote = L("Никнейм уже занят")
            suggestions = r.suggestedLogins ?? []
        } else if r.code == 2 {
            loginNote = L("Недопустимый никнейм")
        }
    }
}
