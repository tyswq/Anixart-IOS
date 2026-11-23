import SwiftUI

/// Кому отвечаем: ветка верхнего комментария и (необязательно) конкретный ответ в ней.
private struct ReplyTarget {
    let parent: Comment
    let to: Comment?

    var name: String { (to ?? parent).profile?.login ?? L("Аноним") }
}

private func commentErrorText(_ code: Int) -> String {
    switch code {
    case 2: return L("Нельзя комментировать этот релиз: он удалён")
    case 5: return L("Комментарий слишком короткий")
    case 6: return L("Комментарий слишком длинный")
    case 7: return L("Лимит комментариев за сутки исчерпан. Попробуйте позже")
    case 8: return L("Пользователь добавил вас в чёрный список")
    case 402: return L("Комментарии недоступны: аккаунт ограничен за нарушение правил")
    default: return L("Не удалось отправить комментарий")
    }
}

struct CommentsView: View {
    let release: Release

    init(release: Release) { self.release = release }

    @Environment(AuthStore.self) private var auth
    @State private var items: [Comment] = []
    @State private var page = 0
    @State private var finished = false
    @State private var loading = false
    @State private var error: String?
    @State private var sort = 1
    @State private var generation = 0
    @State private var showLogin = false
    @State private var note: String?
    @State private var target: ReplyTarget?
    @State private var refresh: [Int: Int] = [:]
    @State private var text = ""
    @State private var spoiler = false
    @State private var sending = false
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(items) { c in
                    CommentRow(
                        comment: c,
                        refresh: refresh[c.id] ?? 0,
                        onReply: { parent, to in startReply(parent, to) },
                        notify: { note = $0 },
                        needLogin: { showLogin = true }
                    )
                    .onAppear { if c.id == items.last?.id { Task { await loadMore() } } }
                }
                if loading { ProgressView().padding() }
                if let error, items.isEmpty { ErrorState(message: error) { Task { await loadMore() } } }
                if items.isEmpty, finished, !loading {
                    EmptyState(icon: "bubble.left", title: "Комментариев пока нет", subtitle: "Напишите первый")
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { AmbientBackground(image: release.image) }
        .navigationTitle("Комментарии")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Сортировка", selection: $sort) {
                        Text("Сначала новые").tag(1)
                        Text("Сначала старые").tag(2)
                        Text("Сначала популярные").tag(3)
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .sheet(isPresented: $showLogin) { LoginView() }
        .task { if items.isEmpty { await loadMore() } }
        .onChange(of: sort) { _, _ in Task { await reloadAll() } }
    }

    // MARK: Поле ввода

    private var composer: some View {
        VStack(spacing: 6) {
            if let note {
                Text(note)
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .glassBackground(Capsule())
                    .transition(.opacity)
                    .task(id: note) {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        if !Task.isCancelled { self.note = nil }
                    }
            }
            if let t = target {
                HStack {
                    Text(L("Ответ для %@", t.name)).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        target = nil
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 22)
            }
            HStack(alignment: .bottom, spacing: 2) {
                TextField(target == nil ? L("Ваш комментарий") : L("Ваш ответ"), text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focused)
                    .padding(.leading, 16)
                    .padding(.vertical, 13)
                Button {
                    spoiler.toggle()
                } label: {
                    Image(systemName: spoiler ? "eye.slash.fill" : "eye.slash")
                        .font(.body)
                        .foregroundStyle(spoiler ? Theme.accent : Color.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 6)
                Button {
                    Task { await send() }
                } label: {
                    Group {
                        if sending {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.up").font(.body.weight(.bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.accent))
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                .padding(.bottom, 6)
                .padding(.trailing, 6)
            }
            .frame(minHeight: 50)
            .glassBackground(RoundedRectangle(cornerRadius: 25, style: .continuous))
            .padding(.horizontal, 12)
        }
        .padding(.top, 6)
        .padding(.bottom, 8)
        .animation(.smooth(duration: 0.2), value: note)
    }

    // MARK: Действия

    private func startReply(_ parent: Comment, _ to: Comment?) {
        guard auth.isLoggedIn else { showLogin = true; return }
        target = ReplyTarget(parent: parent, to: to)
        if let login = to?.profile?.login, !login.isEmpty { text = login + ", " } else { text = "" }
        focused = true
    }

    private func send() async {
        guard auth.isLoggedIn else { showLogin = true; return }
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard message.count >= 5 else { note = commentErrorText(5); return }
        guard message.count <= 720 else { note = commentErrorText(6); return }
        guard !sending else { return }
        sending = true
        defer { sending = false }
        do {
            let code = try await AnixAPI.commentAdd(
                rid: release.id, message: message, spoiler: spoiler,
                parent: target?.parent.id, replyTo: target?.to?.profile?.id
            )
            guard code == 0 else { note = commentErrorText(code); return }
            text = ""
            spoiler = false
            focused = false
            if let t = target {
                refresh[t.parent.id, default: 0] += 1
                target = nil
            } else {
                await reloadAll()
            }
            note = L("Комментарий отправлен")
        } catch {
            note = error.localizedDescription
        }
    }

    // MARK: Загрузка

    private func reloadAll() async {
        generation += 1
        page = 0
        finished = false
        loading = false
        error = nil
        items = []
        await loadMore()
    }

    private func loadMore() async {
        guard !loading, !finished else { return }
        loading = true
        let gen = generation
        defer { if gen == generation { loading = false } }
        do {
            let res = try await AnixAPI.comments(releaseId: release.id, page: page, sort: sort)
            guard gen == generation else { return }
            let known = Set(items.map(\.id))
            let fresh = res.filter { !known.contains($0.id) }
            if fresh.isEmpty { finished = true } else { items += fresh; page += 1 }
            error = nil
        } catch {
            if !Task.isCancelled, gen == generation { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Комментарий

private struct CommentRow: View {
    @State private var comment: Comment
    let refresh: Int
    let onReply: (Comment, Comment?) -> Void
    let notify: (String) -> Void
    let needLogin: () -> Void
    var isReply = false
    var parent: Comment?

    init(
        comment: Comment, refresh: Int = 0,
        onReply: @escaping (Comment, Comment?) -> Void,
        notify: @escaping (String) -> Void,
        needLogin: @escaping () -> Void,
        isReply: Bool = false, parent: Comment? = nil
    ) {
        _comment = State(initialValue: comment)
        self.refresh = refresh
        self.onReply = onReply
        self.notify = notify
        self.needLogin = needLogin
        self.isReply = isReply
        self.parent = parent
    }

    @Environment(AuthStore.self) private var auth
    @State private var replies: [Comment] = []
    @State private var showReplies = false
    @State private var loadingReplies = false
    @State private var extraReplies = 0

    private var replyCount: Int { max(comment.replyCount ?? 0, replies.count) + extraReplies }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Circle().fill(Color.primary.opacity(0.08))
                    .overlay { RemoteImage(url: comment.profile?.avatar) }
                    .clipShape(Circle())
                    .frame(width: isReply ? 32 : 40, height: isReply ? 32 : 40)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(comment.profile?.login ?? L("Аноним")).font(.subheadline.weight(.semibold))
                        if let t = comment.timestamp {
                            Text(Date(timeIntervalSince1970: t > 1e11 ? t / 1000 : t), format: .relative(presentation: .named))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    if comment.isDeleted == true {
                        Text("Комментарий удалён").font(.callout).foregroundStyle(.secondary)
                    } else {
                        SpoilerText(text: comment.message ?? "", isSpoiler: comment.isSpoiler == true)
                    }
                    if comment.isDeleted != true { tools }
                }
            }

            if !isReply && replyCount > 0 {
                Button {
                    withAnimation(.smooth) { showReplies.toggle() }
                    if showReplies && replies.isEmpty { Task { await loadReplies() } }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showReplies ? "chevron.up" : "chevron.down").font(.caption.weight(.bold))
                        Text(showReplies ? L("Скрыть ответы") : L("Показать ответы: %ld", replyCount))
                            .font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.leading, 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if showReplies {
                if loadingReplies && replies.isEmpty { ProgressView().frame(maxWidth: .infinity) }
                ForEach(replies) { r in
                    CommentRow(
                        comment: r, onReply: onReply, notify: notify, needLogin: needLogin,
                        isReply: true, parent: comment
                    )
                    .padding(.leading, 28)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 22)
        .task(id: refresh) {
            // после своего ответа ветка перечитывается и раскрывается
            guard refresh > 0 else { return }
            extraReplies = 0
            showReplies = true
            await loadReplies()
            comment.replyCount = max(comment.replyCount ?? 0, replies.count)
        }
    }

    // MARK: Оценка и ответ

    private var tools: some View {
        HStack(spacing: 4) {
            voteButton(2, icon: "hand.thumbsup")
            let v = comment.voteCount ?? 0
            Text("\(v)")
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(v > 0 ? Theme.accent : (v < 0 ? Color.red : Color.secondary))
                .frame(minWidth: 22)
            voteButton(1, icon: "hand.thumbsdown")
            Button {
                onReply(parent ?? comment, isReply ? comment : nil)
            } label: {
                Text("Ответить")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10).frame(height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    /// 1 — минус, 2 — плюс (как в API).
    private func voteButton(_ value: Int, icon: String) -> some View {
        let mine = comment.vote == value
        return Button {
            vote(value)
        } label: {
            Image(systemName: mine ? icon + ".fill" : icon)
                .font(.subheadline)
                .foregroundStyle(mine ? (value == 2 ? Theme.accent : Color.red) : Color.secondary)
                .frame(width: 32, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: comment.vote)
    }

    private static func delta(old: Int, new: Int) -> Int {
        switch (old, new) {
        case (0, 2): return 1
        case (0, 1): return -1
        case (2, 2): return -1
        case (1, 1): return 1
        case (1, 2): return 2
        case (2, 1): return -2
        default: return 0
        }
    }

    private func vote(_ value: Int) {
        guard auth.isLoggedIn else { needLogin(); return }
        let oldVote = comment.vote ?? 0
        let oldCount = comment.voteCount ?? 0
        // оценка меняется сразу, ответ сервера не ждём; отказ сервера возвращает как было
        comment.vote = oldVote == value ? 0 : value
        comment.voteCount = oldCount + Self.delta(old: oldVote, new: value)
        let id = comment.id
        Task {
            let code = (try? await AnixAPI.commentVote(id: id, value: value)) ?? -1
            guard code != 0 else { return }
            comment.vote = oldVote
            comment.voteCount = oldCount
            switch code {
            case 2: notify(L("Дневной лимит отрицательных оценок исчерпан"))
            case 3: notify(L("Вы зарегистрировались недавно — оценки станут доступны позже"))
            case 402: notify(L("Оценки недоступны: аккаунт ограничен"))
            default: break
            }
        }
    }

    // MARK: Ответы

    private func loadReplies() async {
        loadingReplies = true
        defer { loadingReplies = false }
        var all: [Comment] = []
        var page = 0
        while page < 20, let chunk = try? await AnixAPI.commentReplies(id: comment.id, page: page) {
            let known = Set(all.map(\.id))
            let fresh = chunk.filter { !known.contains($0.id) }
            if fresh.isEmpty { break }
            all += fresh
            page += 1
            if chunk.count < 25 { break }
        }
        replies = all
    }
}
