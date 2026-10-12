// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import AppKit
import AVFoundation
import CoreImage
import Foundation
import Network
import SwiftUI
import WebKit
import KazumiCore

enum DownloadFolder {
    private static var bookmarkFile: URL {
        AppPaths.support.appendingPathComponent("download-bookmark")
    }

    static func save(_ url: URL) {
        guard let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        try? FileManager.default.createDirectory(at: AppPaths.support, withIntermediateDirectories: true)
        try? data.write(to: bookmarkFile, options: .atomic)
    }

    static func resolve() -> URL? {
        guard let data = try? Data(contentsOf: bookmarkFile) else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    static func access<T>(_ url: URL, _ body: () throws -> T) rethrows -> T {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        return try body()
    }
}

struct CaptchaSheet: View {
    var url: URL
    var onFinish: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var page = CaptchaWebPage()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("在页面里完成验证，然后点「使用这个页面」。验证码通过后，下一次搜索会带上这里的 Cookie。")
                .font(.callout)
                .foregroundStyle(.secondary)
            CaptchaWebView(page: page, url: url)
                .frame(minWidth: 720, minHeight: 480)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("使用这个页面") {
                    page.cookies { header in
                        onFinish(header)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }
}

final class CaptchaWebPage: NSObject, WKNavigationDelegate {
    let webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        return WKWebView(frame: .zero, configuration: configuration)
    }()

    func cookies(_ done: @escaping (String) -> Void) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let header = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            done(header)
        }
    }
}

struct CaptchaWebView: NSViewRepresentable {
    var page: CaptchaWebPage
    var url: URL

    func makeNSView(context: Context) -> WKWebView {
        page.webView.load(URLRequest(url: url))
        return page.webView
    }

    func updateNSView(_ view: WKWebView, context: Context) {}
}

struct WebPlaybackSheet: View {
    var url: URL
    var userAgent: String
    var referer: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("片源网页").font(.headline)
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(16)
            Divider()
            WebPlaybackView(url: url, userAgent: userAgent, referer: referer)
        }.frame(minWidth: 960, minHeight: 640)
    }
}

private struct WebPlaybackView: NSViewRepresentable {
    var url: URL
    var userAgent: String
    var referer: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.customUserAgent = userAgent
        var request = URLRequest(url: url)
        if !referer.isEmpty { request.setValue(referer, forHTTPHeaderField: "Referer") }
        view.load(request)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {}

    static func dismantleNSView(_ view: WKWebView, coordinator: ()) {
        view.stopLoading()
        view.loadHTMLString("", baseURL: nil)
    }
}

struct SniffedMedia {
    var url: URL
    var referer: String
    var cookieHeader: String
}

@MainActor
enum PageSniffer {
    static func find(url: URL, userAgent: String, referer: String, legacy: Bool) async -> SniffedMedia? {
        await withCheckedContinuation { continuation in
            let box = SniffBox(legacy: legacy) { continuation.resume(returning: $0) }
            box.start(url: url, userAgent: userAgent, referer: referer)
        }
    }
}

@MainActor
private final class SniffBox: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let legacy: Bool
    let finish: (SniffedMedia?) -> Void
    private var webView: WKWebView?
    private var done = false

    init(legacy: Bool, finish: @escaping (SniffedMedia?) -> Void) {
        self.legacy = legacy
        self.finish = finish
    }

    func start(url: URL, userAgent: String, referer: String) {
        let content = WKUserContentController()
        content.add(self, name: "kazumi")
        content.addUserScript(WKUserScript(
            source: "window.kazumiLegacySniff = \(legacy ? "true" : "false");" + Self.source,
            injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = content
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 360), configuration: configuration)
        view.navigationDelegate = self
        view.customUserAgent = userAgent
        webView = view
        var request = URLRequest(url: url)
        if !referer.isEmpty { request.setValue(referer, forHTTPHeaderField: "Referer") }
        view.load(request)
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in self?.complete(nil) }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !done, let body = message.body as? [String: Any], let raw = body["url"] as? String,
              let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        let lower = url.absoluteString.lowercased()
        guard !LegacySniff.blockedFragments.contains(where: { lower.contains($0) }) else { return }
        guard !["ts", "m4s", "aac", "css", "js", "html", "jpg", "png", "svg"].contains(url.pathExtension.lowercased()) else { return }
        let mime = (body["mime"] as? String ?? "").lowercased().split(separator: ";").first.map(String.init) ?? ""
        let videoResponse = (mime.hasPrefix("video/") && mime != "video/mp2t") || ["application/vnd.apple.mpegurl", "application/x-mpegurl", "audio/mpegurl", "audio/x-mpegurl"].contains(mime)
        // Frames, scripts, styles, thumbnails and HLS fragments are never a player URL.
        guard MediaSniffer.isDirect(url) || videoResponse || (body["kind"] as? String == "video" && url.pathExtension.isEmpty) else { return }
        let referer = body["document"] as? String ?? message.frameInfo.request.url?.absoluteString ?? ""
        complete(url, referer: referer)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("window.kazumiScanMedia && window.kazumiScanMedia();", completionHandler: nil)
    }

    private func complete(_ url: URL?, referer: String = "") {
        guard !done else { return }
        done = true
        guard let view = webView, let url else {
            teardown()
            finish(nil)
            return
        }
        view.configuration.websiteDataStore.httpCookieStore.getAllCookies { [self] cookies in
            let host = url.host?.lowercased() ?? ""
            let matching = cookies.filter { cookie in
                let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                return (host == domain || host.hasSuffix("." + domain)) && url.path.hasPrefix(cookie.path)
                    && (!cookie.isSecure || url.scheme == "https") && (cookie.expiresDate.map { $0 > Date() } ?? true)
            }
            let header = HTTPCookie.requestHeaderFields(with: matching)["Cookie"] ?? ""
            teardown()
            finish(SniffedMedia(url: url, referer: referer, cookieHeader: header))
        }
    }

    private func teardown() {
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "kazumi")
        webView?.navigationDelegate = nil
        webView = nil
    }

    private static let source = #"""
    (function() {
      function mediaURL(value) {
        try { return /\.(m3u8|mp4|m4v|webm|mkv|flv|mov)$/i.test(new URL(value, location.href).pathname); }
        catch (_) { return false; }
      }
      function mediaType(mime) { return /^(video\/|application\/(vnd\.apple\.mpegurl|x-mpegurl)|audio\/(x-)?mpegurl)/i.test(mime || ''); }
      function report(value, kind, mime) {
        try {
          var url = new URL(value, location.href);
          if (!/^https?:$/.test(url.protocol)) return;
          if (kind !== 'video' && !mediaURL(url.href) && !mediaType(mime)) return;
          window.webkit.messageHandlers.kazumi.postMessage({url:url.href, kind:kind, mime:mime || '', document:location.href});
        } catch (_) {}
      }
      function scan() {
        document.querySelectorAll('video,video source').forEach(function(node) {
          var value = node.currentSrc || node.src;
          if (value) report(value, 'video', node.type);
        });
      }
      function legacyBody(text) {
        if (!window.kazumiLegacySniff || typeof text !== 'string') return;
        var urls = text.replace(/\\\//g, '/').match(/https?:\/\/[^\s"'<>\\]+/g) || [];
        urls.forEach(function(url) { if (mediaURL(url)) report(url, 'resource', ''); });
      }
      window.kazumiScanMedia = scan;
      document.addEventListener('DOMContentLoaded', function() {
        scan();
        new MutationObserver(scan).observe(document.documentElement, {childList:true, subtree:true, attributes:true, attributeFilter:['src']});
      });
      document.addEventListener('loadedmetadata', scan, true);
      document.addEventListener('play', scan, true);
      try {
        new PerformanceObserver(function(list) {
          list.getEntries().forEach(function(entry) { if (mediaURL(entry.name)) report(entry.name, 'resource', ''); });
        }).observe({type:'resource', buffered:true});
      } catch (_) {}
      var originalFetch = window.fetch;
      window.fetch = function() {
        return originalFetch.apply(this, arguments).then(function(response) {
          var type = response.headers.get('content-type') || '';
          report(response.url, 'response', type);
          if (window.kazumiLegacySniff && /json|text/.test(type)) response.clone().text().then(legacyBody).catch(function() {});
          return response;
        });
      };
      var originalSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.send = function() {
        this.addEventListener('load', function() {
          report(this.responseURL, 'response', this.getResponseHeader('content-type'));
          try { if (this.responseType === '' || this.responseType === 'text') legacyBody(this.responseText); } catch (_) {}
        });
        return originalSend.apply(this, arguments);
      };
    })();
    """#
}

enum ExternalPlayback {
    static func open(url: URL, player: String) {
        switch player {
        case "iina":
            NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: "/Applications/IINA.app"), configuration: NSWorkspace.OpenConfiguration())
        case "vlc":
            NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: "/Applications/VLC.app"), configuration: NSWorkspace.OpenConfiguration())
        case "browser":
            NSWorkspace.shared.open(url)
        default:
            NSWorkspace.shared.open(url)
        }
    }
}

enum VideoSharpen {
    static func composition(for asset: AVAsset, strong: Bool) -> AVVideoComposition {
        AVVideoComposition(asset: asset, applyingCIFiltersWithHandler: { request in
            let name = strong ? "CIUnsharpMask" : "CISharpenLuminance"
            let image = request.sourceImage
            guard let filter = CIFilter(name: name) else {
                request.finish(with: image, context: nil)
                return
            }
            filter.setValue(image, forKey: kCIInputImageKey)
            if strong {
                filter.setValue(0.8, forKey: kCIInputIntensityKey)
                filter.setValue(2.4, forKey: kCIInputRadiusKey)
            } else {
                filter.setValue(0.45, forKey: kCIInputSharpnessKey)
            }
            request.finish(with: filter.outputImage ?? image, context: nil)
        })
    }
}

@MainActor
@Observable
final class SyncPlaySession {
    var connected = false
    var status = "未连接"
    var onState: ((Double, Bool, Bool) -> Void)?
    private var connection: NWConnection?
    private var buffer = Data()

    func connect(host: String, port: Int, tls: Bool, username: String, room: String) {
        disconnect()
        let parameters: NWParameters = tls ? .tls : .tcp
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: UInt16(port)))
        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection
        status = "正在连接"
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.connected = true
                    self?.status = "已加入 \(room)"
                    self?.send(SyncPlayCodec.hello(username: username, room: room))
                    self?.receive()
                case .failed(let error):
                    self?.connected = false
                    self?.status = error.localizedDescription
                case .cancelled:
                    self?.connected = false
                    self?.status = "已断开"
                default:
                    break
                }
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }

    func sendState(position: Double, paused: Bool) {
        send(SyncPlayCodec.state(position: position, paused: paused))
    }

    func sendChat(_ text: String) {
        send(SyncPlayCodec.chat(text))
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        connected = false
    }

    private func send(_ text: String) {
        guard let data = text.data(using: .utf8), let connection else { return }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            Task { @MainActor in
                guard let self, error == nil else { return }
                if let data { self.buffer.append(data) }
                self.drain()
                self.receive()
            }
        }
    }

    private func drain() {
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard let text = String(data: line, encoding: .utf8) else { continue }
            if case .state(let position, let paused, let seek) = SyncPlayCodec.parse(text) {
                onState?(position, paused, seek)
            }
        }
    }
}

@MainActor
@Observable
final class DLNABrowser {
    var devices: [(name: String, control: URL)] = []
    var status = "未搜索"
    private var connection: NWConnection?

    func search() {
        devices = []
        status = "正在搜索"
        let host = NWEndpoint.Host(DLNAMessages.searchTarget)
        let port = NWEndpoint.Port(integerLiteral: UInt16(DLNAMessages.searchPort))
        let connection = NWConnection(host: host, port: port, using: .udp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard case .ready = state else { return }
            let payload = Data(DLNAMessages.searchRequest().utf8)
            connection.send(content: payload, completion: .contentProcessed { _ in })
            Task { @MainActor in self?.listen() }
        }
        connection.start(queue: .global(qos: .userInitiated))
        Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            status = devices.isEmpty ? "没有发现渲染器" : "发现 \(devices.count) 台设备"
            connection.cancel()
        }
    }

    func cast(control: URL, media: URL, title: String) async {
        let http = HTTPClient()
        do {
            _ = try await http.sendRaw(
                method: "POST",
                url: control.absoluteString,
                body: Data(DLNAMessages.setAVTransportURI(mediaURL: media.absoluteString, title: title).utf8),
                headers: [
                    "Content-Type": "text/xml; charset=\"utf-8\"",
                    "SOAPAction": "\"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI\"",
                ]
            )
            _ = try await http.sendRaw(
                method: "POST",
                url: control.absoluteString,
                body: Data(DLNAMessages.play().utf8),
                headers: [
                    "Content-Type": "text/xml; charset=\"utf-8\"",
                    "SOAPAction": "\"urn:schemas-upnp-org:service:AVTransport:1#Play\"",
                ]
            )
            status = "已发送到 \(control.host ?? "设备")"
        } catch {
            status = describe(error)
        }
    }

    private func listen() {
        connection?.receiveMessage { [weak self] data, _, _, _ in
            let text = data.flatMap { String(data: $0, encoding: .utf8) }
            Task { @MainActor in
                guard let self else { return }
                if let text, let location = DLNAMessages.location(in: text), let url = URL(string: location) {
                    await self.loadDevice(at: url)
                }
                self.listen()
            }
        }
    }

    private func loadDevice(at url: URL) async {
        guard let xml = try? await HTTPClient().get(url.absoluteString).text,
              let control = DLNAMessages.controlURL(in: xml, base: url) else { return }
        let name = url.host ?? control.host ?? "渲染器"
        if devices.contains(where: { $0.control == control }) { return }
        devices.append((name, control))
        status = "发现 \(devices.count) 台设备"
    }
}
