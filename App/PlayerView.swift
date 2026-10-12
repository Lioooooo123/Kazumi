// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
@preconcurrency import AVFoundation
@preconcurrency import AVKit
@preconcurrency import AppKit
import KazumiCore
import SwiftUI

struct PlayerScreen: View {
    var request: PlaybackRequest
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controller = PlaybackController()
    @State private var time: Double = 0
    @State private var duration: Double = 0
    @State private var playing = false
    @State private var status = "正在准备播放"
    @State private var preparing = true
    @State private var playbackFailed = false
    @State private var mediaURL: URL?
    @State private var candidates: [URL] = []
    @State private var mediaReferer = ""
    @State private var mediaCookies = ""
    @State private var comments: [DanmakuComment] = []
    @State private var danmakuNote = ""
    @State private var showControls = true
    @State private var didSeek = false
    @State private var didAutoAdvance = false
    @State private var controlsToken = 0
    @State private var showDanmakuSettings = false
    @State private var lastSaved = Date.distantPast
    @State private var showWebPlayer = false
    @State private var showCast = false
    @State private var showRoom = false
    @State private var dlna = DLNABrowser()
    @State private var room = SyncPlaySession()
    @FocusState private var playerFocused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !playbackFailed {
                VideoSurface(player: controller.player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .ignoresSafeArea()
            }
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
            if mediaURL == nil || playbackFailed {
                VStack(spacing: 16) {
                    if preparing {
                        ProgressView().controlSize(.large)
                    } else {
                        Image(systemName: "play.slash").font(.largeTitle)
                    }
                    Text(preparing ? "正在准备播放" : "暂时无法播放")
                        .font(.title2.weight(.semibold))
                    Text(status).font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).textSelection(.enabled)
                    if !preparing {
                        HStack {
                            Button("重新尝试") {
                                Task { await prepare() }
                            }
                            .buttonStyle(.borderedProminent)
                            Button("打开片源网页") { showWebPlayer = true }
                            Button("返回分集") { model.nowPlaying = nil }
                        }
                    }
                }
                .padding(32)
                .frame(maxWidth: 480)
            }
            if showControls {
                VStack {
                    topBar
                    Spacer()
                    controlBar
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : KazumiTheme.controlsVisibility, value: showControls)
        .environment(\.colorScheme, .dark)
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
        .onKeyPress(.escape) {
            model.nowPlaying = nil
            return .handled
        }
        .onChange(of: model.playerCommandToken) { _, _ in
            switch model.playerCommand {
            case PlayerCommand.toggle: toggle()
            case PlayerCommand.back: seek(by: -5)
            case PlayerCommand.forward: seek(by: 5)
            case PlayerCommand.next: playNext()
            case PlayerCommand.fullscreen: NSApp.keyWindow?.toggleFullScreen(nil)
            default: break
            }
        }
        .sheet(isPresented: $showWebPlayer) {
            if let url = URL(string: request.pageURL) {
                WebPlaybackSheet(url: url, userAgent: request.userAgent, referer: request.referer)
            }
        }
        .sheet(isPresented: $showCast) { castSheet }
        .sheet(isPresented: $showRoom) { roomSheet }
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
            .buttonStyle(ContentButtonStyle())
            .keyboardShortcut(.cancelAction)
            .help("关闭播放器")
            .accessibilityLabel("关闭播放器")
            VStack(alignment: .leading, spacing: 2) {
                Text(request.subjectName).font(.headline)
                Text(request.episodeName).font(.subheadline).foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            if !danmakuNote.isEmpty {
                Text(danmakuNote).font(.caption).foregroundStyle(.white.opacity(0.75))
            }
            HStack(spacing: 12) {
                Button {
                    let lines = comments.map { "\(Int($0.time)) \($0.message)" }.joined(separator: "\n")
                    model.enqueueDownload(
                        title: request.subjectName,
                        episode: request.episodeName,
                        url: (mediaURL ?? URL(string: request.pageURL))?.absoluteString ?? request.pageURL,
                        danmakuText: lines
                    )
                } label: {
                    Image(systemName: "arrow.down.circle").frame(width: 36, height: 36)
                }
                .buttonStyle(ContentButtonStyle())
                .help("下载")
                .accessibilityLabel("下载当前视频")
                Button {
                    showCast = true
                } label: {
                    Image(systemName: "tv").frame(width: 36, height: 36)
                }
                .buttonStyle(ContentButtonStyle())
                .help("DLNA 投屏")
                .accessibilityLabel("DLNA 投屏")
                Button {
                    showRoom = true
                } label: {
                    Image(systemName: "person.2").frame(width: 36, height: 36)
                }
                .buttonStyle(ContentButtonStyle())
                .help("一起看")
                .accessibilityLabel("一起看")
                Button {
                    if let url = mediaURL {
                        ExternalPlayback.open(url: url, player: model.settings.externalPlayer)
                    }
                } label: {
                    Image(systemName: "arrow.up.forward.app").frame(width: 36, height: 36)
                }
                .buttonStyle(ContentButtonStyle())
                .help("用外部播放器打开")
                .accessibilityLabel("用外部播放器打开")
                .disabled(mediaURL == nil)
                Button {
                    model.updateSettings { $0.danmakuEnabled.toggle() }
                } label: {
                    Image(
                        systemName: model.settings.danmakuEnabled ? "captions.bubble.fill" : "captions.bubble"
                    )
                    .frame(width: 36, height: 36)
                }
                .buttonStyle(ContentButtonStyle())
                .help("弹幕")
                .accessibilityLabel("弹幕")
                .accessibilityValue(model.settings.danmakuEnabled ? "已开启" : "已关闭")
                Button {
                    showDanmakuSettings.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3").frame(width: 36, height: 36)
                }
                .buttonStyle(ContentButtonStyle())
                .help("弹幕设置")
                .accessibilityLabel("弹幕设置")
                .popover(isPresented: $showDanmakuSettings, arrowEdge: .bottom) {
                    danmakuSettings
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .foregroundStyle(.white)
        .font(.body)
        .padding(16)
        .background(
            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom))
    }

    private var controlBar: some View {
        VStack(spacing: 6) {
            Slider(value: seekBinding, in: 0...max(duration, 1))
                .padding(.horizontal, 4)
                .accessibilityLabel("播放进度")
                .accessibilityValue("\(clock(time))，总时长 \(clock(duration))")
                .disabled(duration <= 0)
            HStack(spacing: 14) {
                Button {
                    seek(by: -5)
                } label: {
                    Image(systemName: "gobackward.5")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(ContentButtonStyle())
                .help("后退 5 秒")
                .accessibilityLabel("后退 5 秒")
                Button {
                    toggle()
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(ContentButtonStyle())
                .help(playing ? "暂停" : "播放")
                .accessibilityLabel(playing ? "暂停" : "播放")
                Button {
                    seek(by: 5)
                } label: {
                    Image(systemName: "goforward.5")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(ContentButtonStyle())
                .help("前进 5 秒")
                .accessibilityLabel("前进 5 秒")
                Button {
                    playNext()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.body)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(ContentButtonStyle())
                .disabled(nextEpisode == nil)
                .help("下一集")
                .accessibilityLabel("下一集")
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
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var danmakuSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("弹幕").font(.headline)
            Slider(value: opacityBinding, in: 0.3...1.0) {
                Text("不透明度 \(Int((model.settings.danmakuOpacity * 100).rounded()))%")
            }
            Slider(value: fontBinding, in: 12.0...32.0) {
                Text("字号 \(Int(model.settings.danmakuFontSize.rounded()))")
            }
            Slider(value: durationBinding, in: 4.0...16.0) {
                Text("滚动时长 \(Int(model.settings.danmakuDuration.rounded())) 秒")
            }
            Text("屏蔽词在设置里修改。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 280)
    }

    private var seekBinding: Binding<Double> {
        Binding(
            get: { time },
            set: { value in
                time = value
                controller.player.seek(
                    to: CMTime(seconds: value, preferredTimescale: 600), toleranceBefore: .zero,
                    toleranceAfter: .zero)
            })
    }

    private func bind() {
        controller.onFailure = { message in
            status = message
            playbackFailed = true
            playing = false
            showControls = true
        }
        controller.onTick = { current, length in
            time = current
            duration = length
            playing = controller.player.rate > 0.01
            if !playing { showControls = true }
            if !didSeek, length > 1, let record = savedProgress,
                let start = PlaybackResume.position(
                    saved: record.position, savedDuration: record.duration, mediaDuration: length)
            {
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
                playbackFailed = true
                showControls = true
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
        Binding(
            get: { model.settings.danmakuOpacity },
            set: { value in model.updateSettings { $0.danmakuOpacity = value } })
    }

    private var fontBinding: Binding<Double> {
        Binding(
            get: { model.settings.danmakuFontSize },
            set: { value in model.updateSettings { $0.danmakuFontSize = value } })
    }

    private var durationBinding: Binding<Double> {
        Binding(
            get: { model.settings.danmakuDuration },
            set: { value in model.updateSettings { $0.danmakuDuration = value } })
    }

    private func bumpControls() {
        showControls = true
        controlsToken += 1
        let token = controlsToken
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard token == controlsToken, playing,
                controller.player.currentItem?.status == .readyToPlay,
                !playbackFailed, !showDanmakuSettings else { return }
            showControls = false
        }
    }

    private func prepare() async {
        controller.player.pause()
        mediaURL = nil
        candidates = []
        preparing = true
        playbackFailed = false
        mediaReferer = ""
        mediaCookies = ""
        defer { preparing = false }
        await loadDanmaku()
        guard !Task.isCancelled else { return }
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
            let response = try await client.get(
                request.pageURL,
                headers: [
                    "User-Agent": request.userAgent,
                    "Referer": request.referer,
                ])
            guard !Task.isCancelled else { return }
            var found = MediaSniffer.mediaURLs(in: response.text, baseURL: response.url)
            mediaReferer = response.url.absoluteString
            if let resolved = try await model.resolveDirectPlayback(
                page: response.url, html: response.text, userAgent: request.userAgent)
            {
                found = [resolved]
            }
            if found.isEmpty {
                status = "正在用网页嗅探视频地址"
                let legacy =
                    model.rules.first {
                        $0.plugin.baseURL == request.referer || request.pageURL.hasPrefix($0.plugin.baseURL)
                    }?.plugin.useLegacyParser ?? false
                if let sniffed = await PageSniffer.find(
                    url: page, userAgent: request.userAgent, referer: request.referer, legacy: legacy)
                {
                    found = [sniffed.url]
                    mediaReferer = sniffed.referer
                    mediaCookies = sniffed.cookieHeader
                }
            }
            guard !Task.isCancelled else { return }
            candidates = found
            if let first = found.first {
                play(first)
            } else {
                status = "没有找到可直接播放的地址"
            }
        } catch {
            status = describe(error)
        }
    }

    private func play(_ url: URL) {
        playbackFailed = false
        mediaURL = url
        status = url.lastPathComponent
        var headers = [
            "User-Agent": request.userAgent,
            "Referer": mediaReferer.isEmpty ? request.referer : mediaReferer,
        ]
        if !mediaCookies.isEmpty { headers["Cookie"] = mediaCookies }
        controller.load(url: url, headers: headers, sharpen: model.settings.superResolution)
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
            guard let anime = DanmakuMatching.bestAnime(title: request.subjectName, candidates: animes)
            else {
                danmakuNote = "没有匹配到弹幕"
                return
            }
            let info = try await client.episodes(bangumiID: anime.id)
            let number = DanmakuMatching.episodeNumber(from: request.episodeName)
            guard let episode = DanmakuMatching.bestEpisode(number: number, episodes: info.episodes)
            else {
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
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
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
    var onFailure: ((String) -> Void)?
    private var observer: Any?
    private var statusObserver: NSKeyValueObservation?

    func load(url: URL, headers: [String: String], sharpen: Int = SuperResolutionMode.off.rawValue) {
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        if sharpen != SuperResolutionMode.off.rawValue {
            item.videoComposition = VideoSharpen.composition(
                for: asset, strong: sharpen == SuperResolutionMode.quality.rawValue)
        }
        statusObserver?.invalidate()
        // Failed items may never emit a periodic time tick. Observe the item itself.
        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.player.currentItem === item, item.status == .failed else { return }
                self.player.pause()
                self.onFailure?(item.error?.localizedDescription ?? "当前视频无法播放，请重试或选择其他线路。")
            }
        }
        player.replaceCurrentItem(with: item)
        guard observer == nil else { return }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        // The observer closure is @Sendable. The player is main-actor isolated, and this queue is .main.
        observer = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
            [weak self] time in
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
        statusObserver?.invalidate()
        statusObserver = nil
        onFailure = nil
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
                    .foregroundStyle(
                        Color(rgb: item.comment.colorRGB == 0 ? 0xFFFFFF : item.comment.colorRGB)
                    )
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

    private func measuredWidth(_ text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    private func visible(in size: CGSize, lanes: Int) -> [Placed] {
        let window = max(duration, 4)
        let measured = comments.map { comment in
            (comment, Double(measuredWidth(comment.message)))
        }
        return DanmakuLanes.assignMeasured(
            comments: measured,
            at: time,
            viewWidth: size.width,
            travel: window,
            laneCount: lanes,
            shield: shield
        ).map { placement in
            let comment = placement.comment
            let age = max(0, time - comment.time)
            if comment.isTop {
                return Placed(
                    id: comment.id, comment: comment,
                    point: CGPoint(x: size.width / 2, y: laneHeight(placement.lane, size: size)))
            }
            if comment.isBottom {
                let bottomLane = placement.lane
                return Placed(
                    id: comment.id, comment: comment,
                    point: CGPoint(
                        x: size.width / 2, y: size.height - 48 - CGFloat(bottomLane) * (fontSize + 6)))
            }
            let textWidth = measuredWidth(comment.message)
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

extension PlayerScreen {
    fileprivate var castSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DLNA").font(.title3.weight(.semibold))
            Text(dlna.status).font(.callout).foregroundStyle(.secondary)
            Button("搜索设备") { dlna.search() }
                .disabled(mediaURL == nil)
            ForEach(dlna.devices, id: \.control) { device in
                Button(device.name) {
                    guard let mediaURL else { return }
                    Task {
                        await dlna.cast(control: device.control, media: mediaURL, title: request.subjectName)
                    }
                }
            }
            Text("投屏发送的是当前直链。需要验证码或加密的地址，电视端未必能打开。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 360)
    }

    fileprivate var roomSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("一起看").font(.title3.weight(.semibold))
            Text(room.status).font(.callout).foregroundStyle(.secondary)
            Text(
                "房间 \(model.settings.syncplayHost):\(model.settings.syncplayPort)。协议与 Syncplay 的 Hello / State JSON 相同，默认不加密。"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack {
                Button(room.connected ? "断开" : "连接") {
                    if room.connected {
                        room.disconnect()
                    } else {
                        room.onState = { position, paused, _ in
                            controller.player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
                            if paused { controller.player.pause() } else { controller.player.play() }
                        }
                        room.connect(
                            host: model.settings.syncplayHost,
                            port: model.settings.syncplayPort,
                            tls: model.settings.syncplayTLS,
                            username: NSFullUserName(),
                            room: "kazumi"
                        )
                    }
                }
                Button("同步进度") { room.sendState(position: time, paused: !playing) }
                    .disabled(!room.connected)
            }
        }
        .padding(20)
        .frame(minWidth: 380)
    }
}
