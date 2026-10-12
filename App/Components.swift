// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import AppKit
import ImageIO
import SwiftUI
import KazumiCore

@MainActor
final class CoverLoader {
    static let shared = CoverLoader()
    private let memory: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 180
        return cache
    }()
    private var disk: ImageDiskCache?
    private var inflight = Set<URL>()

    func configure(directory: URL) {
        disk = ImageDiskCache(directory: directory)
    }

    /// Fills the disk cache ahead of scrolling. Decoding waits until a card appears.
    func prefetch(_ urlStrings: [String]) {
        guard let disk else { return }
        var batch: [URL] = []
        for raw in urlStrings {
            guard let url = URL(string: raw), !raw.isEmpty else { continue }
            if memory.object(forKey: url as NSURL) != nil || inflight.contains(url) { continue }
            inflight.insert(url)
            batch.append(url)
            if batch.count == 16 { break }
        }
        guard !batch.isEmpty else { return }
        Task {
            await disk.prefetch(batch, limit: 4) { url in
                try await CoverLoader.loadData(from: url)
            }
            for url in batch {
                inflight.remove(url)
            }
        }
    }

    func image(for urlString: String) async -> NSImage? {
        guard let url = URL(string: urlString), !urlString.isEmpty else { return nil }
        if let cached = memory.object(forKey: url as NSURL) { return cached }
        do {
            let data: Data
            if let disk {
                data = try await disk.fetch(url) {
                    try await CoverLoader.loadData(from: url)
                }
            } else {
                data = try await CoverLoader.loadData(from: url)
            }
            guard let image = CoverLoader.thumbnail(from: data) else { return nil }
            memory.setObject(image, forKey: url as NSURL)
            return image
        } catch {
            return nil
        }
    }

    static func thumbnail(from data: Data) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return NSImage(data: data)
        }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            return NSImage(data: data)
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    nonisolated static func loadData(from url: URL) async throws -> Data {
        let (payload, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw KazumiError.message("图片加载失败")
        }
        return payload
    }
}

struct CoverImage: View {
    var url: String

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: url) {
            let loaded = await CoverLoader.shared.image(for: url)
            if !Task.isCancelled { image = loaded }
        }
    }
}

struct BangumiCard: View {
    var subject: BangumiSubject
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CoverImage(url: subject.coverURL)
                .aspectRatio(0.65, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()
            Text(subject.displayName)
                .font(.system(size: 13, weight: .medium))
                .tracking(0.3)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(EdgeInsets(top: 4, leading: 6, bottom: 6, trailing: 6))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
        }
        .background(KazumiTheme.card(scheme))
        .clipShape(RoundedRectangle(cornerRadius: KazumiTheme.cardRadius, style: .continuous))
        .scaleEffect(hovering ? 1.025 : 1)
        .shadow(color: .black.opacity(hovering ? 0.12 : 0), radius: hovering ? 8 : 0, y: 3)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.16), value: hovering)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subject.displayName)
    }
}

struct TimelineCard: View {
    var subject: BangumiSubject
    var showRating: Bool
    var isWatching: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            CoverImage(url: subject.coverURL)
                .frame(width: 88, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: KazumiTheme.timelineRadius - 12, style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                Text(subject.displayName)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(2)
                if !subject.timelineLine.isEmpty {
                    Text(subject.timelineLine)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if showRating || isWatching {
                    HStack(spacing: 8) {
                        if showRating {
                            Text(subject.score > 0 ? String(format: "%.1f", subject.score) : "暂无评分")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(KazumiTheme.chip(scheme), in: Capsule())
                        }
                        Spacer(minLength: 0)
                        if isWatching {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .help("正在追")
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 156, alignment: .leading)
        .background(KazumiTheme.timelineCard(scheme))
        .clipShape(RoundedRectangle(cornerRadius: KazumiTheme.timelineRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subject.displayName)
    }
}

struct HoverLift: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? 1.015 : 1)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.16), value: hovering)
    }
}

extension View {
    func hoverLift() -> some View { modifier(HoverLift()) }
}

struct EmptyHint: View {
    var title: String
    var message: String
    var systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
            .frame(maxWidth: .infinity, minHeight: 280)
    }
}

struct LoadingBar: View {
    var active: Bool
    var body: some View {
        Group {
            if active {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
    }
}

struct TagWrap: View {
    var tags: [String]
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        let rows = arrange(width: width, subviews: subviews)
        let height = rows.last.map { $0.maxY } ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            for item in row.items {
                item.view.place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + item.y),
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
            }
        }
    }

    private struct Item {
        var view: LayoutSubview
        var x: CGFloat
        var y: CGFloat
        var size: CGSize
    }

    private struct Row {
        var items: [Item]
        var maxY: CGFloat
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var items: [Item] = []
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                rows.append(Row(items: items, maxY: y + rowHeight))
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
                items = []
            }
            items.append(Item(view: view, x: x, y: y, size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        if !items.isEmpty {
            rows.append(Row(items: items, maxY: y + rowHeight))
        }
        return rows
    }
}
