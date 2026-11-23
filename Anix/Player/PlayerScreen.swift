import AVFoundation
import AVKit
import Observation
import SwiftUI

// MARK: - Модель плеера

enum ResumeStore {
    static func key(_ rid: Int, _ sid: Int, _ pos: Int) -> String { "resume.\(rid).\(sid).\(pos)" }

    static func position(rid: Int, sid: Int, pos: Int) -> Double {
        UserDefaults.standard.double(forKey: key(rid, sid, pos))
    }

    static func save(_ seconds: Double, duration: Double, rid: Int, sid: Int, pos: Int) {
        ContinueStore.progress(rid: rid, sid: sid, position: pos, seconds: seconds, duration: duration)
        let k = key(rid, sid, pos)
        if duration > 0, seconds > duration * 0.95 || seconds < 5 {
            UserDefaults.standard.removeObject(forKey: k)
        } else {
            UserDefaults.standard.set(seconds, forKey: k)
        }
    }
}

@MainActor
@Observable
final class PlayerModel {
    let player = AVPlayer()
    var isPlaying = false
    var isBuffering = true
    var current: Double = 0
    var duration: Double = 0
    var finished = false
    var quality: VideoQuality

    @ObservationIgnored private let video: ResolvedVideo
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private let onSave: (Double, Double) -> Void

    var qualities: [VideoQuality] { video.qualities.sorted { $0.height > $1.height } }

    init(video: ResolvedVideo, resume: Double, onSave: @escaping (Double, Double) -> Void) {
        self.video = video
        self.quality = video.best
        self.onSave = onSave
        load(video.best, at: resume)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor in self?.tick(time) }
        }
    }

    private func load(_ q: VideoQuality, at seconds: Double) {
        let asset = AVURLAsset(url: q.url, options: ["AVURLAssetHTTPHeaderFieldsKey": video.headers])
        let item = AVPlayerItem(asset: asset)
        if let old = endObserver { NotificationCenter.default.removeObserver(old) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.finished = true }
        }
        player.replaceCurrentItem(with: item)
        if seconds > 1 {
            player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        }
    }

    private func tick(_ time: CMTime) {
        if time.seconds.isFinite { current = time.seconds }
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 { duration = d }
        isPlaying = player.timeControlStatus == .playing
        isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        ticks += 1
        if ticks % 20 == 0 { onSave(current, duration) }
    }

    func play() {
        player.play()
        isPlaying = true
    }

    func toggle() {
        if player.timeControlStatus == .paused { play() } else { player.pause(); isPlaying = false }
    }

    func seek(by delta: Double) { seek(to: current + delta) }

    func seek(to seconds: Double) {
        let upper = duration > 0 ? duration : seconds
        let target = max(0, min(seconds, upper))
        current = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func setQuality(_ q: VideoQuality) {
        guard q != quality else { return }
        let at = current
        quality = q
        load(q, at: at)
        play()
    }

    /// Останавливает воспроизведение и сохраняет место.
    func stop() {
        onSave(current, duration)
        player.pause()
        if let t = timeObserver { player.removeTimeObserver(t); timeObserver = nil }
        if let e = endObserver { NotificationCenter.default.removeObserver(e); endObserver = nil }
        player.replaceCurrentItem(with: nil)
    }
}

// MARK: - Поверхность видео

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// Картинка в картинке: кнопка в плеере запускает и останавливает её.
final class PiPBridge: NSObject, AVPictureInPictureControllerDelegate {
    var controller: AVPictureInPictureController?
    var onActiveChange: ((Bool) -> Void)?

    static var supported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    func attach(_ layer: AVPlayerLayer) {
        guard controller == nil, Self.supported else { return }
        let c = AVPictureInPictureController(playerLayer: layer)
        c?.canStartPictureInPictureAutomaticallyFromInline = true
        c?.delegate = self
        controller = c
    }

    func toggle() {
        guard let c = controller else { return }
        if c.isPictureInPictureActive { c.stopPictureInPicture() } else { c.startPictureInPicture() }
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        onActiveChange?(true)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        onActiveChange?(false)
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer
    let pip: PiPBridge

    func makeUIView(context: Context) -> PlayerLayerView {
        let v = PlayerLayerView()
        v.backgroundColor = .black
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        pip.attach(v.playerLayer)
        return v
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

// MARK: - Экран плеера

struct PlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    let loadNext: (PlayerItem) async -> PlayerItem?

    @State private var item: PlayerItem
    @State private var model: PlayerModel
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var hasNext = true
    @State private var loadingNext = false
    @State private var locked = false
    @State private var pip = PiPBridge()
    @State private var pipActive = false
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?

    init(initial: PlayerItem, loadNext: @escaping (PlayerItem) async -> PlayerItem?) {
        self.loadNext = loadNext
        _item = State(initialValue: initial)
        _model = State(initialValue: PlayerScreen.makeModel(for: initial))
    }

    private static func makeModel(for item: PlayerItem) -> PlayerModel {
        let resume = ResumeStore.position(rid: item.rid, sid: item.sid, pos: item.position)
        return PlayerModel(video: item.video, resume: resume) { seconds, duration in
            ResumeStore.save(seconds, duration: duration, rid: item.rid, sid: item.sid, pos: item.position)
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoSurface(player: model.player, pip: pip).ignoresSafeArea()

            // двойной тап по краям — перемотка на 10 секунд, одиночный — показать/спрятать управление
            HStack(spacing: 0) {
                tapZone(delta: -10)
                tapZone(delta: 10)
            }
            .ignoresSafeArea()

            if model.isBuffering {
                ProgressView().tint(.white).scaleEffect(1.5)
            }
            if locked {
                // интерфейс заблокирован: по нажатию на экран всплывает только замок и пропадает сам, как остальное управление
                if controlsVisible {
                    VStack {
                        HStack {
                            Spacer()
                            lockButton
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        Spacer()
                    }
                    .transition(.opacity)
                }
            } else if controlsVisible {
                controls.transition(.opacity)
            }
            if let n = countdown {
                nextEpisodeCard(seconds: n)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .environment(\.forceGlass, true)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .animation(.smooth(duration: 0.25), value: controlsVisible)
        .animation(.smooth(duration: 0.25), value: countdown == nil)
        .onAppear {
            pip.onActiveChange = { pipActive = $0 }
            model.play()
            scheduleHide()
        }
        .onDisappear {
            hideTask?.cancel()
            countdownTask?.cancel()
            model.stop()
        }
        .onChange(of: model.finished) { _, done in
            if done { startCountdown() }
        }
    }

    private func tapZone(delta: Double) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                guard !locked else { return }
                model.seek(by: delta)
                scheduleHide()
            }
            .onTapGesture {
                controlsVisible.toggle()
                if controlsVisible { scheduleHide() }
            }
    }

    // MARK: Управление

    private var controls: some View {
        VStack {
            GlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    circleButton("xmark") { dismiss() }
                    HStack(spacing: 5) {
                        Text(item.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text("· " + item.episode)
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(.white.opacity(0.75))
                    }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .frame(maxWidth: .infinity)
                        .glassBackground(Capsule())
                    // +1:30 — пропустить опенинг одним нажатием
                    Button {
                        model.seek(by: 90)
                        scheduleHide()
                    } label: {
                        Text("+1:30")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassBackground(Capsule(), interactive: true)
                    Menu {
                        ForEach(model.qualities) { q in
                            Button {
                                model.setQuality(q)
                                scheduleHide()
                            } label: {
                                if q == model.quality {
                                    Label(q.label, systemImage: "checkmark")
                                } else {
                                    Text(q.label)
                                }
                            }
                        }
                    } label: {
                        Text(model.quality.label)
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .glassBackground(Capsule(), interactive: true)
                    }
                    lockButton
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            GlassGroup(spacing: 24) {
                HStack(spacing: 24) {
                    circleButton("gobackward.10", size: 56) { model.seek(by: -10); scheduleHide() }
                    circleButton(model.isPlaying ? "pause.fill" : "play.fill", size: 76, font: .title) {
                        model.toggle()
                        scheduleHide()
                    }
                    circleButton("goforward.10", size: 56) { model.seek(by: 10); scheduleHide() }
                }
            }

            Spacer()

            HStack(spacing: 12) {
                Text(format(scrubbing ? scrubValue : model.current))
                    .frame(minWidth: 40, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { scrubbing ? scrubValue : model.current },
                        set: { scrubValue = $0 }
                    ),
                    in: 0...max(model.duration, 1),
                    onEditingChanged: { editing in
                        scrubbing = editing
                        if editing {
                            hideTask?.cancel()
                        } else {
                            model.seek(to: scrubValue)
                            scheduleHide()
                        }
                    }
                )
                .tint(Theme.accent)
                Text("-" + format(max(model.duration - (scrubbing ? scrubValue : model.current), 0)))
                    .frame(minWidth: 48, alignment: .trailing)
                if PiPBridge.supported {
                    Button {
                        pip.toggle()
                        scheduleHide()
                    } label: {
                        Image(systemName: pipActive ? "pip.exit" : "pip.enter")
                            .font(.body.weight(.semibold))
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 18).padding(.vertical, 10)
            .glassBackground(Capsule())
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .foregroundStyle(.white)
    }

    /// Замок: прячет весь интерфейс, кроме себя; повторное нажатие возвращает его.
    private var lockButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.25)) { locked.toggle() }
            // и при блокировке, и при снятии замок и интерфейс скрываются сами через пару секунд
            controlsVisible = true
            scheduleHide()
        } label: {
            Image(systemName: locked ? "lock.fill" : "lock.open.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassBackground(Circle(), interactive: true, tint: locked ? Theme.accent.opacity(0.55) : nil)
        .opacity(locked ? 0.85 : 1)
    }

    private func circleButton(_ icon: String, size: CGFloat = 44, font: Font = .headline, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(font)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassBackground(Circle(), interactive: true)
    }

    // MARK: Логика

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if !Task.isCancelled, model.isPlaying, !scrubbing { controlsVisible = false }
        }
    }

    /// Серия закончилась: 5 секунд до следующей, можно отменить или перейти сразу.
    private func nextEpisodeCard(seconds: Int) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Следующая серия").font(.subheadline.weight(.bold))
                    Text(L("Через %ld с", seconds)).font(.caption).foregroundStyle(.white.opacity(0.75))
                }
                Spacer(minLength: 8)
                Button {
                    cancelCountdown()
                } label: {
                    Text("Отмена")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).frame(height: 40)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassBackground(Capsule(), interactive: true)
                Button {
                    countdownTask?.cancel()
                    countdown = nil
                    Task { await advance() }
                } label: {
                    Text("Смотреть")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 16).frame(height: 40)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassBackground(Capsule(), interactive: true, tint: Theme.accent)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .glassBackground(Capsule())
            .padding(.horizontal, 20)
            .padding(.bottom, 90)
        }
    }

    private func startCountdown() {
        countdownTask?.cancel()
        controlsVisible = false
        countdown = 5
        countdownTask = Task {
            while let n = countdown, n > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                countdown = n - 1
            }
            if Task.isCancelled { return }
            countdown = nil
            await advance()
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdown = nil
        controlsVisible = true
    }

    private func advance() async {
        guard !loadingNext else { return }
        loadingNext = true
        defer { loadingNext = false }
        guard let nextItem = await loadNext(item) else {
            hasNext = false
            if model.finished { dismiss() }
            return
        }
        model.stop()
        item = nextItem
        model = PlayerScreen.makeModel(for: nextItem)
        model.play()
        controlsVisible = true
        scheduleHide()
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}
