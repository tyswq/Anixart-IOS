import PhotosUI
import SwiftUI
import UIKit

// MARK: - Всплывающее сообщение

extension View {
    /// Короткое сообщение внизу экрана; пропадает само.
    func banner(_ text: Binding<String?>) -> some View {
        overlay(alignment: .bottom) {
            if let t = text.wrappedValue {
                Text(t)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassBackground(Capsule())
                    .padding(.bottom, 24)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: t) {
                        try? await Task.sleep(nanoseconds: 2_800_000_000)
                        if !Task.isCancelled { text.wrappedValue = nil }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: text.wrappedValue)
    }
}

private func formatDate(_ raw: Double?) -> String {
    guard let raw, raw > 0 else { return "—" }
    let d = Date(timeIntervalSince1970: raw > 1e11 ? raw / 1000 : raw)
    return d.formatted(.dateTime.day().month().year().hour().minute())
}

private let privacyChoices = ["Все пользователи", "Только друзья", "Только я"]
private let friendRequestChoices = ["Все пользователи", "Никто"]

// MARK: - Редактирование профиля

struct EditProfileView: View {
    @Environment(AuthStore.self) private var auth

    private let onChange: () -> Void

    init(onChange: @escaping () -> Void = {}) { self.onChange = onChange }

    @State private var pref: MyPreference?
    @State private var loadError: String?
    @State private var avatarURL: String?
    @State private var status = ""
    @State private var savedStatus = ""
    @State private var privacy: [String: Int] = [:]
    @State private var pickerItem: PhotosPickerItem?
    @State private var busyAvatar = false
    @State private var busyStatus = false
    @State private var confirmDeleteAvatar = false
    @State private var note: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let loadError, pref == nil {
                    ErrorState(message: loadError) { Task { await load() } }
                } else if pref == nil {
                    ProgressView().padding(.top, 80)
                } else {
                    avatarCard
                    statusCard
                    linksCard
                    privacyCard
                }
            }
            .padding(20)
            .padding(.bottom, 60)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { AmbientBackground(image: avatarURL ?? auth.profile?.avatar) }
        .navigationTitle("Редактировать профиль")
        .navigationBarTitleDisplayMode(.inline)
        .banner($note)
        .task { await load() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
        .confirmationDialog("Удалить фото профиля?", isPresented: $confirmDeleteAvatar, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { Task { await deleteAvatar() } }
            Button("Отмена", role: .cancel) {}
        }
    }

    // MARK: Карточки

    private var avatarCard: some View {
        VStack(spacing: 14) {
            Circle()
                .fill(Color.primary.opacity(0.08))
                .overlay { RemoteImage(url: avatarURL) }
                .overlay { if busyAvatar { ProgressView().tint(.white) } }
                .clipShape(Circle())
                .frame(width: 112, height: 112)
                .glassBackground(Circle())

            HStack(spacing: 10) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Выбрать фото", systemImage: "photo.on.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .glassBackground(Capsule(), interactive: true, tint: Theme.accent)
                        .foregroundStyle(.white)
                }
                .disabled(busyAvatar)

                if let a = avatarURL, !a.isEmpty {
                    Button {
                        confirmDeleteAvatar = true
                    } label: {
                        Label("Удалить", systemImage: "trash")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .glassBackground(Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(busyAvatar)
                }
            }
            if pref?.isChangeAvatarBanned == true {
                Text("Смена фото временно ограничена из-за нарушения правил.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassCard(radius: 28)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Статус").font(.headline)
            TextField("Расскажите о себе", text: $status, axis: .vertical)
                .lineLimit(1...4)
                .padding(14)
                .glassCard(radius: 18)
            HStack {
                Spacer()
                Button {
                    Task { await saveStatus() }
                } label: {
                    Group {
                        if busyStatus { ProgressView().tint(.white) } else { Text("Сохранить").font(.subheadline.weight(.semibold)) }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 9)
                    .glassBackground(Capsule(), interactive: true, tint: Theme.accent)
                    .opacity(status == savedStatus ? 0.45 : 1)
                }
                .buttonStyle(.plain)
                .disabled(status == savedStatus || busyStatus)
            }
        }
        .padding(18)
        .glassCard(radius: 24)
    }

    private var linksCard: some View {
        VStack(spacing: 0) {
            NavigationLink {
                NicknameView(onChange: { refreshAfterNickname() })
            } label: {
                linkRow("person.text.rectangle", "Никнейм", auth.profile?.login)
            }
            Divider().overlay(Color.primary.opacity(0.08))
            NavigationLink {
                SocialPagesView()
            } label: {
                linkRow("link", "Социальные сети", "VK, Telegram, Discord, TikTok")
            }
            Divider().overlay(Color.primary.opacity(0.08))
            NavigationLink {
                PasswordView()
            } label: {
                linkRow("lock", "Пароль", "Сменить пароль")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .glassCard(radius: 24)
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Приватность").font(.headline).padding(.bottom, 6)
            privacyRow("Статистика, оценки и история просмотра", kind: "stats", options: privacyChoices)
            privacyRow("Комментарии, коллекции, видео и друзья в профиле", kind: "counts", options: privacyChoices)
            privacyRow("Мои социальные сети", kind: "social", options: privacyChoices)
            privacyRow("Заявки в друзья", kind: "friendRequests", options: friendRequestChoices)
        }
        .padding(18)
        .glassCard(radius: 24)
    }

    private func linkRow(_ icon: String, _ title: String, _ sub: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 26).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title)).font(.body)
                if let sub, !sub.isEmpty {
                    Text(LocalizedStringKey(sub)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func privacyRow(_ title: String, kind: String, options: [String]) -> some View {
        let binding = Binding<Int>(
            get: { privacy[kind] ?? 0 },
            set: { v in Task { await setPrivacy(kind, v) } }
        )
        return HStack(spacing: 8) {
            Text(LocalizedStringKey(title)).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Picker(title, selection: binding) {
                ForEach(options.indices, id: \.self) { i in Text(LocalizedStringKey(options[i])).tag(i) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: Логика

    private func load() async {
        loadError = nil
        do {
            let p = try await AccountAPI.preferences()
            guard p.code == 0 else {
                loadError = L("Не удалось загрузить настройки (код %@)", p.code.map(String.init) ?? "—")
                return
            }
            pref = p
            avatarURL = p.avatar ?? auth.profile?.avatar
            status = p.status ?? ""
            savedStatus = status
            privacy = [
                "stats": p.privacyStats ?? 0,
                "counts": p.privacyCounts ?? 0,
                "social": p.privacySocial ?? 0,
                "friendRequests": p.privacyFriendRequests ?? 0,
            ]
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func refreshAfterNickname() {
        onChange()
    }

    private func saveStatus() async {
        busyStatus = true
        defer { busyStatus = false }
        let value = status.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let r = try await AccountAPI.setStatus(value)
            if r.code == 0 {
                status = value
                savedStatus = value
                auth.patchProfile { $0.status = value }
                onChange()
                note = L("Статус сохранён")
            } else {
                note = L("Не удалось сохранить статус (код %@)", r.code.map(String.init) ?? "—")
            }
        } catch {
            note = error.localizedDescription
        }
    }

    private func setPrivacy(_ kind: String, _ value: Int) async {
        let prev = privacy[kind] ?? 0
        guard value != prev else { return }
        privacy[kind] = value
        do {
            let r = try await AccountAPI.setPrivacy(kind: kind, permission: value)
            if r.code != 0 { throw APIError.http(r.code ?? 0) }
        } catch {
            privacy[kind] = prev
            note = L("Не удалось сохранить настройку")
        }
    }

    private func upload(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        if pref?.isChangeAvatarBanned == true {
            note = L("Смена фото временно ограничена")
            return
        }
        busyAvatar = true
        defer { busyAvatar = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let jpeg = Self.prepareAvatar(data)
        else {
            note = L("Не удалось прочитать выбранное фото")
            return
        }
        do {
            let r = try await AccountAPI.uploadAvatar(jpeg: jpeg)
            if r.code == 0 {
                if let a = r.avatar, !a.isEmpty {
                    avatarURL = a
                    auth.patchProfile { $0.avatar = a }
                } else {
                    await load()
                }
                onChange()
                note = L("Фото профиля обновлено")
            } else {
                note = L("Не удалось загрузить фото (код %@)", r.code.map(String.init) ?? "—")
            }
        } catch {
            note = error.localizedDescription
        }
    }

    private func deleteAvatar() async {
        busyAvatar = true
        defer { busyAvatar = false }
        do {
            let r = try await AccountAPI.deleteAvatar()
            if r.code == 0 {
                avatarURL = r.avatar
                auth.patchProfile { $0.avatar = r.avatar }
                onChange()
                note = L("Фото профиля удалено")
            } else {
                note = L("Не удалось удалить фото")
            }
        } catch {
            note = error.localizedDescription
        }
    }

    /// Квадрат по центру, не больше 1024 точек, JPEG не тяжелее ~1 МБ (больше бекенд не принимает).
    static func prepareAvatar(_ data: Data) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        let src = img.size
        let side = min(src.width, src.height)
        guard side > 0 else { return nil }
        let out = min(side, 1024)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: fmt)
        let scaled = renderer.image { _ in
            let k = out / side
            let w = src.width * k
            let h = src.height * k
            img.draw(in: CGRect(x: (out - w) / 2, y: (out - h) / 2, width: w, height: h))
        }
        var q: CGFloat = 0.9
        while q > 0.2 {
            if let d = scaled.jpegData(compressionQuality: q), d.count <= 1_000_000 { return d }
            q -= 0.15
        }
        return scaled.jpegData(compressionQuality: 0.2)
    }
}

// MARK: - Никнейм

struct NicknameView: View {
    @Environment(AuthStore.self) private var auth

    private let onChange: () -> Void

    init(onChange: @escaping () -> Void = {}) { self.onChange = onChange }

    @State private var info: LoginInfo?
    @State private var current = ""
    @State private var login = ""
    @State private var note: String?
    @State private var noteIsGood = false
    @State private var free = false
    @State private var suggestions: [String] = []
    @State private var busy = false
    @State private var banner: String?

    private var trimmed: String { login.trimmingCharacters(in: .whitespaces) }
    private var available: Bool { info?.isChangeAvailable ?? true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GlassTextField("Никнейм", text: $login)
                    .disabled(!available)
                    .opacity(available ? 1 : 0.5)
                if let note {
                    Text(note).font(.footnote).foregroundStyle(noteIsGood ? Color.green : Color.red).padding(.horizontal, 6)
                }
                if !suggestions.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(suggestions, id: \.self) { s in GlassChip(title: s) { login = s } }
                    }
                }
                Text(available
                     ? L("Никнейм виден всем: в профиле, комментариях и коллекциях. Менять его можно не слишком часто.")
                     : L("Сменить никнейм снова можно будет %@.", formatDate(info?.nextChangeAvailableAt)))
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 6)
                PrimaryButton("Изменить", busy: busy, enabled: available && free && trimmed != current) {
                    Task { await change() }
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { AmbientBackground() }
        .navigationTitle("Никнейм")
        .navigationBarTitleDisplayMode(.inline)
        .banner($banner)
        .task {
            info = try? await AccountAPI.loginInfo()
            current = info?.login ?? auth.profile?.login ?? ""
            login = current
        }
        .task(id: login) { await check() }
    }

    private func check() async {
        free = false
        suggestions = []
        let v = trimmed
        if v.isEmpty || v == current { note = nil; return }
        if v.count < 3 { note = L("Никнейм слишком короткий"); noteIsGood = false; return }
        if v.count > 20 { note = L("Никнейм слишком длинный"); noteIsGood = false; return }
        note = nil
        try? await Task.sleep(nanoseconds: 450_000_000)
        if Task.isCancelled { return }
        guard let r = try? await AccountAPI.checkLogin(v), !Task.isCancelled else { return }
        if r.code == 0 && r.available == true {
            free = true
            note = L("Никнейм свободен")
            noteIsGood = true
        } else if r.code == 0 {
            note = L("Никнейм уже занят")
            noteIsGood = false
            suggestions = r.suggestedLogins ?? []
        } else if r.code == 2 {
            note = L("Недопустимый никнейм")
            noteIsGood = false
        }
    }

    private func change() async {
        busy = true
        defer { busy = false }
        let v = trimmed
        do {
            let r = try await AccountAPI.changeLogin(v)
            switch r.code {
            case 0:
                current = v
                free = false
                auth.patchProfile { $0.login = v }
                onChange()
                banner = L("Никнейм изменён")
                info = try? await AccountAPI.loginInfo()
            case 2: note = L("Недопустимый никнейм"); noteIsGood = false
            case 3:
                note = L("Никнейм уже занят"); noteIsGood = false
                suggestions = r.suggestedLogins ?? []
            case 4:
                info = try? await AccountAPI.loginInfo()
                banner = L("Никнейм можно менять не так часто")
            default: banner = L("Не удалось изменить никнейм (код %@)", r.code.map(String.init) ?? "—")
            }
        } catch {
            banner = error.localizedDescription
        }
    }
}

// MARK: - Социальные сети

struct SocialPagesView: View {
    @State private var vk = ""
    @State private var tg = ""
    @State private var discord = ""
    @State private var tiktok = ""
    @State private var inst = ""
    @State private var errors: [String: String] = [:]
    @State private var loaded = false
    @State private var busy = false
    @State private var banner: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Укажите ссылки или никнеймы — другие пользователи смогут с вами связаться.")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 6)
                field("ВКонтакте", $vk, key: "vk")
                field("Telegram", $tg, key: "tg")
                field("Discord (никнейм)", $discord, key: "discord")
                field("TikTok", $tiktok, key: "tt")
                PrimaryButton("Сохранить", busy: busy, enabled: loaded) { Task { await save() } }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { AmbientBackground() }
        .navigationTitle("Социальные сети")
        .navigationBarTitleDisplayMode(.inline)
        .banner($banner)
        .task { await load() }
    }

    private func field(_ title: String, _ text: Binding<String>, key: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            GlassTextField(title, text: text)
            if let e = errors[key] {
                Text(e).font(.footnote).foregroundStyle(.red).padding(.horizontal, 6)
            }
        }
    }

    private func load() async {
        guard let s = try? await AccountAPI.socialPages() else { banner = L("Не удалось загрузить"); return }
        vk = s.vkPage ?? ""
        tg = s.tgPage ?? ""
        discord = s.discordPage ?? ""
        tiktok = s.ttPage ?? ""
        inst = s.instPage ?? ""
        loaded = true
    }

    private static func match(_ pattern: String, _ s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    /// Из ссылки или никнейма получает никнейм (как в профиле Anixart); пустая строка — поле очищено.
    private static func nick(_ value: String, pattern: String?) -> String? {
        let v = value.filter { !$0.isWhitespace }
        if v.isEmpty { return "" }
        guard let pattern else { return match(#"^((?!.*\.\.)[a-zA-Z0-9_.]{2,32})$"#, v) }
        return match(pattern, v) ?? match(#"^@?([a-zA-Z0-9_.-]{3,32})$"#, v)
    }

    private func save() async {
        errors = [:]
        var body: [String: String] = ["instPage": inst]
        let specs: [(String, String, String, String?)] = [
            ("vk", "vkPage", vk, #"(?:https?://)?(?:www\.)?(?:vk\.com|vk\.me)/([A-Za-z0-9\-_.]+)"#),
            ("tg", "tgPage", tg, #"(?:https?://)?(?:www\.)?t\.me/([A-Za-z0-9\-_.]+)"#),
            ("discord", "discordPage", discord, nil),
            ("tt", "ttPage", tiktok, #"(?:https?://)?(?:www\.)?tiktok\.com/@([A-Za-z0-9\-_.]+)"#),
        ]
        var bad = false
        for (key, param, value, pattern) in specs {
            if let n = Self.nick(value, pattern: pattern) {
                body[param] = n
            } else {
                errors[key] = L("Ссылка или никнейм указаны неверно")
                bad = true
            }
        }
        if bad { return }
        busy = true
        defer { busy = false }
        do {
            let r = try await AccountAPI.setSocial(body)
            switch r.code {
            case 0: banner = L("Изменения сохранены")
            case 2: errors["vk"] = L("Ссылка или никнейм указаны неверно")
            case 3: errors["tg"] = L("Ссылка или никнейм указаны неверно")
            case 5: errors["tt"] = L("Ссылка или никнейм указаны неверно")
            case 6: errors["discord"] = L("Ссылка или никнейм указаны неверно")
            default: banner = L("Не удалось сохранить (код %@)", r.code.map(String.init) ?? "—")
            }
        } catch {
            banner = error.localizedDescription
        }
    }
}

// MARK: - Смена пароля

struct PasswordView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var new1 = ""
    @State private var new2 = ""
    @State private var error: String?
    @State private var busy = false
    @State private var banner: String?

    private var valid: Bool {
        (6...32).contains(current.count) && (6...32).contains(new1.count) && new1 == new2
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                GlassTextField("Текущий пароль", text: $current, secure: true).textContentType(.password)
                GlassTextField("Новый пароль (6–32 символа)", text: $new1, secure: true).textContentType(.newPassword)
                GlassTextField("Повторите новый пароль", text: $new2, secure: true).textContentType(.newPassword)
                if !new2.isEmpty && new1 != new2 {
                    Text("Пароли не совпадают").font(.footnote).foregroundStyle(.red)
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }
                PrimaryButton("Сменить пароль", busy: busy, enabled: valid) { Task { await submit() } }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { AmbientBackground() }
        .navigationTitle("Пароль")
        .navigationBarTitleDisplayMode(.inline)
        .banner($banner)
    }

    private func submit() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let r = try await AccountAPI.changePassword(current: current, new: new1)
            if r.code == 0 {
                if let t = r.token, !t.isEmpty { auth.replaceToken(t) }
                banner = L("Пароль изменён")
                current = ""; new1 = ""; new2 = ""
                try? await Task.sleep(nanoseconds: 900_000_000)
                dismiss()
            } else if r.code == 3 {
                error = L("Текущий пароль введён неверно")
            } else {
                error = L("Не удалось сменить пароль (код %@)", r.code.map(String.init) ?? "—")
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
