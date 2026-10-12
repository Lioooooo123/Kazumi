// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
@preconcurrency import AVFoundation
@preconcurrency import AVKit
@preconcurrency import AppKit
import KazumiCore
import MPVBridge
import SwiftUI

struct PlayerScreen: View {
    var request: PlaybackRequest
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controller = PlaybackController()
    @State private var resolver = PageSniffer()
    @State private var reloadToken = UUID()
    @State private var preparationToken = UUID()
    @State private var preferWebSniff = false
    @State private var sniffAttempted = false
    @State private var lastPlaybackError: String?
    @State private var resumePosition: Double?
    @State private var volume = 1.0
    @State private var buffering = false
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
                Group {
                    if controller.usesMPV { MPVVideoSurface(session: controller.mpv) }
                    else { VideoSurface(player: controller.player) }
                }
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
            if mediaURL == nil || playbackFailed || preparing {
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
                                retry()
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
            if buffering && !preparing && !playbackFailed {
                ProgressView("正在缓冲").padding(16).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
            resumePosition = request.startPosition ?? savedProgress?.position
            playerFocused = true
            bumpControls()
        }
        .onDisappear {
            remember()
            preparationToken = UUID()
            resolver.cancel()
            controller.stop()
        }
        .task(id: reloadToken) {
            bind()
            await prepare()
        }
        .task { await loadDanmaku() }
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
                .disabled(mediaURL == nil || preparing)
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
                if let context = request.context, context.roads.count > 1 {
                    Menu(context.roadName.isEmpty ? "播放线路" : context.roadName) {
                        ForEach(context.roads) { road in
                            Button { switchRoad(road) } label: {
                                if road.name == context.roadName { Label(road.name, systemImage: "checkmark") }
                                else { Text(road.name) }
                            }
                            .disabled(context.episode(on: road, replacing: request.pageURL) == nil)
                        }
                    }
                    .help("切换当前集的播放线路")
                }
                if candidates.count > 1 {
                    Menu("视频地址") {
                        ForEach(candidates, id: \.absoluteString) { url in
                            Button(url.lastPathComponent) { play(url) }
                        }
                    }
                }
                Menu(String(format: "%.2gx", model.settings.playbackRate)) {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        Button(String(format: "%.2g×", rate)) {
                            model.updateSettings { $0.playbackRate = rate }
                            if playing { controller.play(rate: rate) }
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
                Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                Slider(value: $volume, in: 0...1).frame(width: 72)
                    .accessibilityLabel("音量")
                    .onChange(of: volume) { _, value in controller.setVolume(value) }
                Button { NSApp.keyWindow?.toggleFullScreen(nil) } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 36, height: 36)
                }.buttonStyle(ContentButtonStyle()).help("全屏").accessibilityLabel("全屏")
                Text(status).font(.caption).lineLimit(1).frame(maxWidth: 150, alignment: .trailing)
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
                controller.seek(value)
            })
    }

    private func bind() {
        controller.onFailure = { message in
            guard model.nowPlaying?.identity == request.identity else { return }
            lastPlaybackError = message
            playing = false
            preparing = false
            buffering = false
            showControls = true
            if let mediaURL, let index = candidates.firstIndex(of: mediaURL), candidates.indices.contains(index + 1) {
                play(candidates[index + 1])
            } else if !sniffAttempted, !MediaSniffer.isDirect(URL(string: request.pageURL) ?? URL(fileURLWithPath: "/")) {
                preferWebSniff = true
                reloadToken = UUID()
            } else {
                status = message
                playbackFailed = true
            }
        }
        controller.onReady = {
            preparing = false
            status = "播放中"
            controller.setVolume(volume)
            if !didSeek {
                didSeek = true
                if let saved = resumePosition,
                   let start = PlaybackResume.position(saved: saved, savedDuration: savedProgress?.duration ?? 0, mediaDuration: controller.mediaDuration) {
                    controller.seek(start) { finished in
                        Task { @MainActor in
                            guard finished, model.nowPlaying?.identity == request.identity else { return }
                            controller.play(rate: model.settings.playbackRate)
                        }
                    }
                    return
                }
            }
            controller.play(rate: model.settings.playbackRate)
        }
        controller.onCompleted = {
            guard !didAutoAdvance else { return }
            didAutoAdvance = true
            remember()
            Task { playNext() }
        }
        controller.onTick = { current, length in
            guard model.nowPlaying?.identity == request.identity else { return }
            time = current
            duration = length
            playing = controller.isPlaying
            if !playing { showControls = true }
            buffering = controller.isBuffering && !preparing
            if playing { status = "播放中" }
            else if buffering { status = "正在缓冲" }
            else if controller.isReady { status = "已暂停" }
            if Date().timeIntervalSince(lastSaved) > 5 {
                lastSaved = Date()
                remember()
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
                controller.isReady,
                !playbackFailed, !showDanmakuSettings else { return }
            showControls = false
        }
    }

    private func retry() {
        if time > 1 { resumePosition = time }
        preferWebSniff = false
        sniffAttempted = false
        lastPlaybackError = nil
        reloadToken = UUID()
    }

    private func prepare() async {
        let token = UUID()
        preparationToken = token
        resolver.cancel()
        controller.resetItem()
        mediaURL = nil
        candidates = []
        preparing = true
        playing = false
        buffering = false
        playbackFailed = false
        mediaReferer = request.referer
        mediaCookies = ""
        didSeek = false
        didAutoAdvance = false
        time = 0
        duration = 0
        guard let page = URL(string: request.pageURL), ["http", "https", "file"].contains(page.scheme ?? "") else {
            status = "播放地址无效"
            preparing = false
            return
        }
        if page.isFileURL || MediaSniffer.isDirect(page) {
            candidates = [page]
            play(page)
            return
        }
        status = "正在解析片源"
        var found: [URL] = []
        var pageError: String?
        if !preferWebSniff {
            do {
                var headers = request.context.map { model.verificationHeaders(ruleName: $0.ruleName) } ?? [:]
                headers["User-Agent"] = request.userAgent
                headers["Referer"] = request.referer
                let response = try await model.playbackHTTP.get(request.pageURL, headers: headers)
                guard preparationToken == token, !Task.isCancelled else { return }
                if MediaSniffer.isMediaResponse(url: response.url, mimeType: response.headers.first(where: { $0.key.lowercased() == "content-type" })?.value ?? "", text: response.text) {
                    found = [response.url]
                } else {
                    found = MediaSniffer.mediaURLs(in: response.text, baseURL: response.url)
                    do {
                        if let resolved = try await model.resolveDirectPlayback(page: response.url, html: response.text, userAgent: request.userAgent, context: request.context) {
                            found = [resolved]
                        }
                    } catch { pageError = describe(error) }
                }
                guard preparationToken == token, !Task.isCancelled else { return }
                let rule = model.rules.first { $0.plugin.name == request.context?.ruleName }?.plugin
                mediaReferer = rule?.referer.isEmpty == false ? rule!.referer : response.url.absoluteString
            } catch {
                guard preparationToken == token, !Task.isCancelled else { return }
                pageError = describe(error)
            }
        }
        if found.isEmpty {
            status = "正在从网页读取视频"
            sniffAttempted = true
            let rule = model.rules.first {
                $0.plugin.name == request.context?.ruleName || URL(string: $0.plugin.baseURL)?.host == page.host
            }?.plugin
            if let sniffed = await resolver.find(url: page, userAgent: request.userAgent, referer: request.referer, legacy: rule?.useLegacyParser ?? false) {
                found = [sniffed.url]
                mediaReferer = rule?.referer.isEmpty == false ? rule!.referer : sniffed.referer
                mediaCookies = sniffed.cookieHeader
            }
        }
        guard preparationToken == token, !Task.isCancelled else { return }
        candidates = found
        if let first = found.first {
            play(first)
        } else {
            preparing = false
            playbackFailed = true
            status = (pageError ?? lastPlaybackError).map { "片源无法播放：\($0)" } ?? "没有找到视频，请切换播放线路或打开片源网页"
        }
    }

    private func play(_ url: URL) {
        playbackFailed = false
        preparing = true
        playing = false
        didSeek = false
        mediaURL = url
        status = "正在加载视频"
        var headers = [
            "User-Agent": request.userAgent,
            "Referer": mediaReferer.isEmpty ? request.referer : mediaReferer,
        ]
        if !mediaCookies.isEmpty { headers["Cookie"] = mediaCookies }
        controller.load(url: url, headers: headers, sharpen: model.settings.superResolution)
        controller.setVolume(volume)
    }

    private func toggle() {
        if controller.isPlaying {
            controller.pause()
            playing = false
        } else {
            controller.play(rate: model.settings.playbackRate)
            playing = true
        }
    }

    private func seek(by delta: Double) {
        let target = min(max(0, time + delta), duration > 0 ? duration : time + delta)
        controller.seek(target)
    }

    private func playNext() {
        guard let episode = nextEpisode else { return }
        switchTo(episode)
    }

    private func switchTo(_ episode: EpisodeEntry) {
        guard episode.url != request.pageURL else { return }
        remember()
        var next = request
        next.episodeName = episode.name
        next.pageURL = episode.url
        next.startPosition = nil
        model.play(next)
    }

    private func switchRoad(_ road: PlaybackRoad) {
        guard var context = request.context, road.name != context.roadName,
              let episode = context.episode(on: road, replacing: request.pageURL) else { return }
        remember()
        context.roadName = road.name
        var next = request
        next.context = context
        next.episodes = road.episodes
        next.episodeName = episode.name
        next.pageURL = episode.url
        next.startPosition = time > 1 ? time : resumePosition
        model.play(next)
    }

    private func remember() {
        guard time > 1, time.isFinite, duration.isFinite else { return }
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
            guard !Task.isCancelled else { return }
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
    let mpv = MPVPlaybackSession()
    var usesMPV: Bool { mpv.handle != nil }
    var isPlaying: Bool { usesMPV ? mpv.snapshot.loaded != 0 && mpv.snapshot.paused == 0 : player.rate > 0.01 }
    var isBuffering: Bool { usesMPV ? mpv.snapshot.buffering != 0 : player.timeControlStatus == .waitingToPlayAtSpecifiedRate }
    var isReady: Bool { usesMPV ? mpv.snapshot.loaded != 0 : player.currentItem?.status == .readyToPlay }
    var mediaDuration: Double { usesMPV ? mpv.snapshot.duration : player.currentItem?.duration.seconds ?? 0 }
    private var readyReported = false
    private var endReported = false
    var onTick: ((Double, Double) -> Void)?
    var onFailure: ((String) -> Void)?
    var onReady: (() -> Void)?
    var onCompleted: (() -> Void)?
    private var observer: Any?
    private var statusObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var timeoutTask: Task<Void, Never>?
    private var itemToken = UUID()
    private var failureReported = false

    func load(url: URL, headers: [String: String], sharpen: Int = SuperResolutionMode.off.rawValue) {
        resetItem()
        let token = itemToken
        if usesMPV {
            mpv.onSnapshot = { [weak self] snapshot in
                guard let self, self.itemToken == token else { return }
                if snapshot.error < 0 {
                    self.fail(String(cString: kn_error_string(snapshot.error)), token: token)
                    return
                }
                if snapshot.loaded != 0 {
                    if !self.readyReported { self.readyReported = true; self.timeoutTask?.cancel(); self.onReady?() }
                    self.onTick?(max(0, snapshot.position), max(0, snapshot.duration))
                    if snapshot.completed != 0, !self.endReported {
                        self.endReported = true
                        self.onCompleted?()
                    }
                }
            }
            let result = mpv.load(url: url, headers: headers)
            if result < 0 { fail(String(cString: kn_error_string(result)), token: token); return }
            timeoutTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard let self, self.itemToken == token, !self.isReady else { return }
                self.fail("视频加载超时，请重试或切换播放线路。", token: token)
            }
            return
        }
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        if sharpen != SuperResolutionMode.off.rawValue {
            item.videoComposition = VideoSharpen.composition(for: asset, strong: sharpen == SuperResolutionMode.quality.rawValue)
        }
        player.replaceCurrentItem(with: item)
        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.itemToken == token, self.player.currentItem === item else { return }
                if item.status == .readyToPlay {
                    self.timeoutTask?.cancel()
                    self.timeoutTask = nil
                    self.onReady?()
                } else if item.status == .failed {
                    self.fail(item.error?.localizedDescription ?? "当前视频无法播放，请重试或切换线路。", token: token)
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.itemToken == token else { return }
                self.onCompleted?()
            }
        }
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, self.itemToken == token, self.player.currentItem?.status != .readyToPlay else { return }
            self.fail("视频加载超时，请重试或切换播放线路。", token: token)
        }
        guard observer == nil else { return }
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            let seconds = time.seconds
            MainActor.assumeIsolated {
                guard let self, self.player.currentItem != nil else { return }
                let length = self.player.currentItem?.duration.seconds ?? 0
                self.onTick?(seconds.isFinite ? seconds : 0, length.isFinite ? length : 0)
            }
        }
    }

    func pause() { if usesMPV { mpv.pause() } else { player.pause() } }
    func play(rate: Double) { if usesMPV { mpv.play(rate: rate) } else { player.playImmediately(atRate: Float(rate)) } }
    func setVolume(_ value: Double) { if usesMPV { mpv.volume(value) } else { player.volume = Float(value) } }
    func seek(_ seconds: Double, completion: ((Bool) -> Void)? = nil) {
        if usesMPV { mpv.seek(seconds); completion?(true) }
        else { player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { finished in
            Task { @MainActor in completion?(finished) }
        } }
    }

    private func fail(_ message: String, token: UUID) {
        guard itemToken == token, !failureReported else { return }
        failureReported = true
        timeoutTask?.cancel()
        timeoutTask = nil
        pause()
        onFailure?(message)
    }

    func resetItem() {
        itemToken = UUID()
        failureReported = false
        readyReported = false
        endReported = false
        mpv.onSnapshot = nil
        mpv.stop()
        timeoutTask?.cancel()
        timeoutTask = nil
        statusObserver?.invalidate()
        statusObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    func stop() {
        resetItem()
        if let observer { player.removeTimeObserver(observer) }
        observer = nil
        onTick = nil
        onFailure = nil
        onReady = nil
        onCompleted = nil
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
                            controller.seek(position)
                            if paused { controller.pause() } else { controller.play(rate: model.settings.playbackRate) }
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
