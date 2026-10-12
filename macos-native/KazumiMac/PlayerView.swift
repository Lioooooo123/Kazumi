// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import AppKit
import AVFoundation
import AVKit
import SwiftUI
import KazumiCore

struct PlayerScreen: View {
    var request: PlaybackRequest
    @Environment(AppModel.self) private var model
    @State private var controller = PlaybackController()
    @State private var time: Double = 0
    @State private var duration: Double = 0
    @State private var playing = false
    @State private var status = "正在准备播放"
    @State private var mediaURL: URL?
    @State private var candidates: [URL] = []
    @State private var comments: [DanmakuComment] = []
    @State private var danmakuNote = ""
    @State private var showControls = true
    @State private var didSeek = false
    @State private var didAutoAdvance = false
    @State private var controlsToken = 0
    @State private var showDanmakuSettings = false
    @State private var lastSaved = Date.distantPast
    @FocusState private var playerFocused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoSurface(player: controller.player)
                .ignoresSafeArea()
            if model.settings.danmakuEnabled {
                DanmakuOverlay(
                    comments: comments,
                    time: time,
                    duration: model.settings.danmakuDuration,
                    fontSize: model.settings.danmakuFontSize,
                    opacity: model.settings.danmakuOpacity,
                    shield: model.settings.danmakuShield
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
            if mediaURL == nil {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.large)
                    Text(status).foregroundStyle(.white)
                }
            }
            if showControls {
                VStack {
                    topBar
                    Spacer()
                    controlBar
                }
            }
        }
        .focusable()
        .focused($playerFocused)
        .focusEffectDisabled()
        .onAppear {
            bind()
            playerFocused = true
            bumpControls()
        }
        .onDisappear {
            remember()
            controller.stop()
        }
        .task {
            bind()
            await prepare()
        }
        .onContinuousHover { phase in
            if case .active = phase { bumpControls() }
        }
        .onKeyPress(.space) { toggle(); return .handled }
        .onKeyPress("n") { playNext(); return .handled }
        .onKeyPress(.leftArrow) { seek(by: -5); return .handled }
        .onKeyPress(.rightArrow) { seek(by: 5); return .handled }
        .onKeyPress(.escape) { model.nowPlaying = nil; return .handled }
        .onKeyPress(.upArrow) { controller.player.volume = min(1, controller.player.volume + 0.05); return .handled }
        .onKeyPress(.downArrow) { controller.player.volume = max(0, controller.player.volume - 0.05); return .handled }
    }

    private var topBar: some View {
        HStack {
            Button {
                model.nowPlaying = nil
            } label: {
                Image(systemName: "xmark")
                    .padding(8)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            VStack(alignment: .leading, spacing: 2) {
                Text(request.subjectName).font(.headline)
                Text(request.episodeName).font(.subheadline).foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            if !danmakuNote.isEmpty {
                Text(danmakuNote).font(.caption).foregroundStyle(.white.opacity(0.75))
            }
            Button {
                model.updateSettings { $0.danmakuEnabled.toggle() }
            } label: {
                Image(systemName: model.settings.danmakuEnabled ? "captions.bubble.fill" : "captions.bubble")
            }
            .buttonStyle(.plain)
            .help("弹幕")
            Button {
                showDanmakuSettings.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
            .help("弹幕设置")
            .popover(isPresented: $showDanmakuSettings, arrowEdge: .bottom) {
                danmakuSettings
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom))
    }

    private var controlBar: some View {
        VStack(spacing: 6) {
            Slider(value: seekBinding, in: 0...max(duration, 1))
                .padding(.horizontal, 4)
            HStack(spacing: 16) {
                Button { toggle() } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(playing ? "暂停" : "播放")
                Button { playNext() } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 16))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(nextEpisode == nil)
                .help("下一集")
                Text("\(clock(time)) / \(clock(duration))")
                    .font(.caption.monospacedDigit())
                Spacer(minLength: 8)
                if candidates.count > 1 {
                    Menu("线路") {
                        ForEach(candidates, id: \.absoluteString) { url in
                            Button(url.lastPathComponent) { play(url) }
                        }
                    }
                }
                Menu(String(format: "%.2gx", model.settings.playbackRate)) {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        Button(String(format: "%.2g×", rate)) {
                            model.updateSettings { $0.playbackRate = rate }
                            if playing { controller.player.playImmediately(atRate: Float(rate)) }
                        }
                    }
                }
                if request.episodes.count > 1 {
                    Menu("选集") {
                        ForEach(request.episodes) { episode in
                            Button(episode.name) { switchTo(episode) }
                        }
                    }
                }
                Text(status).font(.caption).lineLimit(1).frame(maxWidth: 180, alignment: .trailing)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .top, endPoint: .bottom))
    }

    private var danmakuSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("弹幕").font(.headline)
            Slider(value: opacityBinding, in: 0.3...1.0) { Text("不透明度") }
            Slider(value: fontBinding, in: 12.0...32.0) { Text("字号") }
            Slider(value: durationBinding, in: 4.0...16.0) { Text("滚动时长") }
            Text("屏蔽词在设置里修改。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 280)
    }

    private var seekBinding: Binding<Double> {
        Binding(get: { time }, set: { value in
            time = value
            controller.player.seek(to: CMTime(seconds: value, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        })
    }

    private func bind() {
        controller.onTick = { current, length in
            time = current
            duration = length
            playing = controller.player.rate > 0.01
            if !playing { showControls = true }
            if !didSeek, length > 1, let record = savedProgress,
               let start = PlaybackResume.position(saved: record.position, savedDuration: record.duration, mediaDuration: length) {
                didSeek = true
                controller.player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
            }
            if !didAutoAdvance, length > 1, current >= length - 0.8, nextEpisode != nil {
                didAutoAdvance = true
                Task { playNext() }
            }
            if Date().timeIntervalSince(lastSaved) > 5 {
                lastSaved = Date()
                remember()
            }
            if controller.player.currentItem?.status == .failed {
                status = controller.player.currentItem?.error?.localizedDescription ?? "无法播放"
            }
        }
    }

    private var savedProgress: HistoryRecord? {
        model.history.first { $0.pageURL == request.pageURL }
    }

    private var nextEpisode: EpisodeEntry? {
        EpisodeSequence.next(after: request.pageURL, in: request.episodes)
    }

    private var opacityBinding: Binding<Double> {
        Binding(get: { model.settings.danmakuOpacity }, set: { value in model.updateSettings { $0.danmakuOpacity = value } })
    }

    private var fontBinding: Binding<Double> {
        Binding(get: { model.settings.danmakuFontSize }, set: { value in model.updateSettings { $0.danmakuFontSize = value } })
    }

    private var durationBinding: Binding<Double> {
        Binding(get: { model.settings.danmakuDuration }, set: { value in model.updateSettings { $0.danmakuDuration = value } })
    }

    private func bumpControls() {
        showControls = true
        controlsToken += 1
        let token = controlsToken
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard token == controlsToken, playing, !showDanmakuSettings else { return }
            showControls = false
        }
    }

    private func prepare() async {
        await loadDanmaku()
        guard let page = URL(string: request.pageURL) else {
            status = "播放地址无效"
            return
        }
        if MediaSniffer.isDirect(page) {
            candidates = [page]
            play(page)
            return
        }
        status = "正在从页面查找视频地址"
        do {
            let client = HTTPClient()
            let response = try await client.get(request.pageURL, headers: [
                "User-Agent": request.userAgent,
                "Referer": request.referer,
            ])
            let found = MediaSniffer.mediaURLs(in: response.text, baseURL: page)
            candidates = found
            if let first = found.first {
                play(first)
            } else {
                status = "没有找到可直接播放的地址。WebView 嗅探还没移植。"
            }
        } catch {
            status = describe(error)
        }
    }

    private func play(_ url: URL) {
        mediaURL = url
        status = url.lastPathComponent
        let headers = [
            "User-Agent": request.userAgent,
            "Referer": request.referer,
        ]
        controller.load(url: url, headers: headers)
        controller.player.playImmediately(atRate: Float(model.settings.playbackRate))
        playing = true
    }

    private func toggle() {
        if controller.player.rate > 0.01 {
            controller.player.pause()
            playing = false
        } else {
            controller.player.playImmediately(atRate: Float(model.settings.playbackRate))
            playing = true
        }
    }

    private func seek(by delta: Double) {
        let target = min(max(0, time + delta), duration > 0 ? duration : time + delta)
        controller.player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    private func playNext() {
        guard let episode = nextEpisode else { return }
        switchTo(episode)
    }

    private func switchTo(_ episode: EpisodeEntry) {
        remember()
        var next = request
        next.episodeName = episode.name
        next.pageURL = episode.url
        model.play(next)
    }

    private func remember() {
        guard duration > 0 || time > 0 else { return }
        model.remember(request: request, position: time, duration: duration)
    }

    private func loadDanmaku() async {
        let id = model.settings.dandanAppID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = model.settings.dandanAppSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !secret.isEmpty else {
            danmakuNote = "未配置弹幕凭据"
            return
        }
        let client = model.danmakuClient()
        do {
            let animes = try await client.searchAnime(title: request.subjectName)
            guard let anime = DanmakuMatching.bestAnime(title: request.subjectName, candidates: animes) else {
                danmakuNote = "没有匹配到弹幕"
                return
            }
            let info = try await client.episodes(bangumiID: anime.id)
            let number = DanmakuMatching.episodeNumber(from: request.episodeName)
            guard let episode = DanmakuMatching.bestEpisode(number: number, episodes: info.episodes) else {
                danmakuNote = "没有匹配到分集"
                return
            }
            let loaded = try await client.comments(episodeID: episode.id)
            comments = DanmakuMatching.mergeDuplicates(loaded)
            danmakuNote = "\(comments.count) 条弹幕"
        } catch {
            danmakuNote = describe(error)
        }
    }

    private func clock(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "00:00" }
        let total = Int(value)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

struct VideoSurface: NSViewRepresentable {
    var player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.player = player
        view.videoGravity = .resizeAspect
        view.updatesNowPlayingInfoCenter = false
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}

@MainActor
final class PlaybackController {
    let player = AVPlayer()
    var onTick: ((Double, Double) -> Void)?
    private var observer: Any?

    func load(url: URL, headers: [String: String]) {
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        guard observer == nil else { return }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        // The observer closure is @Sendable. The player is main-actor isolated, and this queue is .main.
        observer = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds
            MainActor.assumeIsolated {
                self?.handleTick(seconds)
            }
        }
    }

    private func handleTick(_ seconds: Double) {
        let length = player.currentItem?.duration.seconds ?? 0
        onTick?(seconds.isFinite ? seconds : 0, length.isFinite ? length : 0)
    }

    func stop() {
        player.pause()
        if let observer {
            player.removeTimeObserver(observer)
            self.observer = nil
        }
        onTick = nil
        player.replaceCurrentItem(with: nil)
    }
}

struct DanmakuOverlay: View {
    var comments: [DanmakuComment]
    var time: Double
    var duration: Double
    var fontSize: Double
    var opacity: Double
    var shield: [String]

    var body: some View {
        GeometryReader { geo in
            let laneHeight = fontSize + 6
            let lanes = max(1, Int(geo.size.height / laneHeight) - 1)
            ForEach(visible(in: geo.size, lanes: lanes)) { item in
                Text(item.comment.message)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(Color(rgb: item.comment.colorRGB == 0 ? 0xFFFFFF : item.comment.colorRGB))
                    .shadow(color: .black.opacity(0.75), radius: 1, y: 1)
                    .fixedSize()
                    .position(item.point)
                    .opacity(opacity)
            }
        }
    }

    private struct Placed: Identifiable {
        var id: Int
        var comment: DanmakuComment
        var point: CGPoint
    }

    private func visible(in size: CGSize, lanes: Int) -> [Placed] {
        let window = max(duration, 4)
        return DanmakuLanes.assign(
            comments: comments,
            at: time,
            travel: window,
            laneCount: lanes,
            shield: shield
        ).map { placement in
            let comment = placement.comment
            let age = max(0, time - comment.time)
            if comment.isTop {
                return Placed(id: comment.id, comment: comment, point: CGPoint(x: size.width / 2, y: laneHeight(placement.lane, size: size)))
            }
            if comment.isBottom {
                let bottomLane = placement.lane
                return Placed(id: comment.id, comment: comment, point: CGPoint(x: size.width / 2, y: size.height - 48 - CGFloat(bottomLane) * (fontSize + 6)))
            }
            let textWidth = CGFloat(comment.message.count) * fontSize
            let progress = min(1, age / window)
            let travel = size.width + textWidth
            let x = size.width + textWidth / 2 - CGFloat(progress) * travel
            let y = 28 + CGFloat(placement.lane) * (fontSize + 6)
            return Placed(id: comment.id, comment: comment, point: CGPoint(x: x, y: y))
        }
    }

    private func laneHeight(_ lane: Int, size: CGSize) -> CGFloat {
        28 + CGFloat(lane) * (fontSize + 6)
    }
}
