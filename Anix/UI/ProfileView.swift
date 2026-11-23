import Charts
import SwiftUI

struct ProfileView: View {
    @Environment(AuthStore.self) private var auth
    @State private var details: ProfileBrief?
    @State private var showLogin = false
    @State private var showRegister = false

    private var shown: ProfileBrief? { details ?? auth.profile }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if auth.isLoggedIn, let p = shown {
                        card(p)
                        statsCard(p)
                        NavigationLink {
                            EditProfileView(onChange: { Task { await reloadDetails() } })
                        } label: {
                            Label("Редактировать профиль", systemImage: "pencil")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .glassCard(radius: 22, interactive: true)
                        }
                        .buttonStyle(.plain)
                        Button(role: .destructive) {
                            auth.signOut()
                            details = nil
                        } label: {
                            Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .glassCard(radius: 22, interactive: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        VStack(spacing: 18) {
                            EmptyState(
                                icon: "person.crop.circle",
                                title: "Вы не вошли",
                                subtitle: "Смотреть можно и без аккаунта. С аккаунтом появятся закладки, история и комментарии."
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
                            Button {
                                showRegister = true
                            } label: {
                                Text("Создать профиль")
                                    .font(.headline)
                                    .padding(.horizontal, 28).padding(.vertical, 12)
                                    .glassBackground(Capsule(), interactive: true)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 40)
                    }
                }
                .padding(20)
            }
            .background { AmbientBackground(image: shown?.avatar) }
            .navigationTitle("Профиль")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Настройки")
                }
            }
            .task(id: auth.token) {
                details = nil
                await reloadDetails()
            }
            .sheet(isPresented: $showLogin) { LoginView() }
            .sheet(isPresented: $showRegister) { RegisterView() }
            .appDestinations()
        }
    }

    private func reloadDetails() async {
        if auth.isLoggedIn, let id = auth.profile?.id, id > 0 {
            details = try? await AnixAPI.profile(id: id)
        }
    }

    private func card(_ p: ProfileBrief) -> some View {
        VStack(spacing: 12) {
            Circle()
                .fill(Color.primary.opacity(0.08))
                .overlay { RemoteImage(url: p.avatar) }
                .clipShape(Circle())
                .frame(width: 104, height: 104)
                .glassBackground(Circle())
            Text(p.login ?? L("Профиль")).font(.title2.weight(.bold))
            if let s = p.status, !s.isEmpty {
                Text(s).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassCard(radius: 32)
    }

    @ViewBuilder
    private func statsCard(_ p: ProfileBrief) -> some View {
        let rows: [StatRow] = [
            StatRow(tab: .watching, count: p.watchingCount ?? 0, color: .green),
            StatRow(tab: .plan, count: p.planCount ?? 0, color: .purple),
            StatRow(tab: .completed, count: p.completedCount ?? 0, color: .blue),
            StatRow(tab: .hold, count: p.holdOnCount ?? 0, color: .orange),
            StatRow(tab: .dropped, count: p.droppedCount ?? 0, color: .red),
        ]
        let known = [p.watchingCount, p.planCount, p.completedCount, p.holdOnCount, p.droppedCount].contains { $0 != nil }
        if known {
            let total = rows.reduce(0) { $0 + $1.count }
            VStack(spacing: 18) {
                ZStack {
                    Chart {
                        if total == 0 {
                            SectorMark(angle: .value("Пусто", 1), innerRadius: .ratio(0.64), angularInset: 1)
                                .foregroundStyle(Color.primary.opacity(0.12))
                        } else {
                            ForEach(rows.filter { $0.count > 0 }) { r in
                                SectorMark(angle: .value(r.tab.title, r.count), innerRadius: .ratio(0.64), angularInset: 2)
                                    .cornerRadius(5)
                                    .foregroundStyle(r.color)
                            }
                        }
                    }
                    .chartLegend(.hidden)
                    .frame(height: 190)
                    VStack(spacing: 2) {
                        Text(total.formatted()).font(.title.weight(.bold).monospacedDigit())
                        Text("всего в списках").font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(spacing: 0) {
                    ForEach(rows) { r in
                        NavigationLink(value: r.tab) {
                            HStack(spacing: 12) {
                                Circle().fill(r.color).frame(width: 10, height: 10)
                                Text(r.tab.title).font(.body.weight(.medium))
                                Spacer()
                                if total > 0 {
                                    Text("\(Int((Double(r.count) / Double(total) * 100).rounded()))%")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Text(r.count.formatted()).font(.headline.monospacedDigit())
                                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 6).padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if r.id != rows.last?.id { Divider().opacity(0.4) }
                    }
                }
            }
            .padding(20)
            .glassCard(radius: 28)
        }
    }
}

private struct StatRow: Identifiable {
    let tab: LibraryTab
    let count: Int
    let color: Color
    var id: Int { tab.rawValue }
}

/// Список релизов из одной закладки (открывается нажатием на число в статистике профиля).
struct LibraryListView: View {
    let tab: LibraryTab

    var body: some View {
        PagedList(
            loader: { try await tab.load(page: $0) },
            emptyTitle: "В этом списке пока пусто",
            emptyIcon: tab.icon
        )
        .background { AmbientBackground() }
        .navigationTitle(tab.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var auth

    @State private var login = ""
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    @State private var showRegister = false
    @FocusState private var focus: Field?

    private enum Field { case login, password }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 56))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 24)
                    Text("Вход в Anixart").font(.title2.weight(.bold))
                    Text("Тот же аккаунт, что в приложении Anixart: закладки, история и отметки серий общие.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)

                    VStack(spacing: 12) {
                        TextField("Логин или e-mail", text: $login)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.username)
                            .focused($focus, equals: .login)
                            .submitLabel(.next)
                            .onSubmit { focus = .password }
                            .padding(16)
                            .glassCard(radius: 20)
                        SecureField("Пароль", text: $password)
                            .textContentType(.password)
                            .focused($focus, equals: .password)
                            .submitLabel(.go)
                            .onSubmit { Task { await submit() } }
                            .padding(16)
                            .glassCard(radius: 20)
                    }

                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        Group {
                            if busy { ProgressView().tint(.white) } else { Text("Войти").font(.headline) }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .glassBackground(Capsule(), interactive: true, tint: Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || login.isEmpty || password.isEmpty)

                    Button {
                        showRegister = true
                    } label: {
                        Text("Нет аккаунта? Создать профиль")
                            .font(.subheadline.weight(.semibold))
                            .padding(10)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
            }
            .background { AmbientBackground() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showRegister) { RegisterView() }
            .onChange(of: auth.isLoggedIn) { _, now in if now { dismiss() } }
        }
        .presentationDetents([.large])
    }

    private func submit() async {
        guard !busy, !login.isEmpty, !password.isEmpty else { return }
        busy = true
        error = nil
        defer { busy = false }
        if let e = await auth.signIn(login: login.trimmingCharacters(in: .whitespaces), password: password) {
            error = e
        } else {
            dismiss()
        }
    }
}
