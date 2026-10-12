// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import AppKit
import SwiftUI
import OpenGL.GL3
import MPVBridge

@MainActor
final class MPVPlaybackSession {
    private(set) var handle: OpaquePointer?
    private var timer: Timer?
    var onSnapshot: ((KNSnapshot) -> Void)?
    private(set) var snapshot = KNSnapshot()

    init() {
        if let directory = Bundle.main.privateFrameworksURL {
            let library = directory.appendingPathComponent("Mpv.framework/Mpv").path
            if kn_open_library(library) != 0 { handle = kn_create() }
        }
    }

    func load(url: URL, headers: [String: String]) -> Int32 {
        let cookie = headers["Cookie"].map { "Cookie: " + $0 } ?? ""
        snapshot = KNSnapshot()
        let result = kn_load(handle, url.absoluteString, headers["Referer"] ?? "", headers["User-Agent"] ?? "", cookie, 0)
        if timer == nil {
            timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.snapshot = kn_snapshot(self.handle)
                    self.onSnapshot?(self.snapshot)
                }
            }
            if let timer { RunLoop.main.add(timer, forMode: .common) }
        }
        return result
    }

    func pause() { kn_pause(handle, 1) }
    func play(rate: Double) { kn_speed(handle, rate); kn_pause(handle, 0) }
    func seek(_ seconds: Double) { kn_seek(handle, max(0, seconds)) }
    func volume(_ value: Double) { kn_volume(handle, value * 100) }
    func stop() {
        timer?.invalidate()
        timer = nil
        kn_stop(handle)
        snapshot = KNSnapshot()
    }
    deinit {
        // The rendering view retains this session until its render context is
        // released. Destroying the handle therefore cannot precede the GL view.
        kn_destroy(handle)
    }
}

@MainActor
private final class MPVVideoView: NSOpenGLView {
    let session: MPVPlaybackSession
    private var frameTimer: Timer?
    private var rendererReady = false

    init?(session: MPVPlaybackSession) {
        self.session = session
        let attributes: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion3_2Core),
            UInt32(NSOpenGLPFADoubleBuffer), UInt32(NSOpenGLPFAAccelerated),
            UInt32(NSOpenGLPFAColorSize), 24, UInt32(NSOpenGLPFAAlphaSize), 8, 0
        ]
        let format = attributes.withUnsafeBufferPointer { NSOpenGLPixelFormat(attributes: $0.baseAddress!) }
        super.init(frame: .zero, pixelFormat: format)
    }
    required init?(coder: NSCoder) { nil }

    override func prepareOpenGL() {
        super.prepareOpenGL()
        openGLContext?.makeCurrentContext()
        var swap: GLint = 1
        openGLContext?.setValues(&swap, for: .swapInterval)
        rendererReady = kn_render_create(session.handle) >= 0
        frameTimer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.needsDisplay = true }
        }
        if let frameTimer { RunLoop.main.add(frameTimer, forMode: .common) }
    }
    override func draw(_ dirtyRect: NSRect) {
        openGLContext?.makeCurrentContext()
        let size = convertToBacking(bounds).size
        if rendererReady { kn_render(session.handle, Int32(size.width), Int32(size.height)) }
        else { glClearColor(0, 0, 0, 1); glClear(GLbitfield(GL_COLOR_BUFFER_BIT)) }
        openGLContext?.flushBuffer()
    }
    override func reshape() { super.reshape(); needsDisplay = true }
    func releaseRenderer() {
        frameTimer?.invalidate()
        frameTimer = nil
        openGLContext?.makeCurrentContext()
        kn_render_destroy(session.handle)
        rendererReady = false
    }
}

struct MPVVideoSurface: NSViewRepresentable {
    let session: MPVPlaybackSession
    func makeNSView(context: Context) -> NSView { MPVVideoView(session: session) ?? NSView() }
    func updateNSView(_ view: NSView, context: Context) {}
    static func dismantleNSView(_ view: NSView, coordinator: ()) { (view as? MPVVideoView)?.releaseRenderer() }
}
