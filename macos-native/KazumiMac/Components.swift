// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import AppKit
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

    func configure(directory: URL) {
        disk = ImageDiskCache(directory: directory)
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
            guard let image = NSImage(data: data) else { return nil }
            memory.setObject(image, forKey: url as NSURL)
            return image
        } catch {
            return nil
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CoverImage(url: subject.coverURL)
                .aspectRatio(0.65, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()
            Text(subject.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
        }
        .background(KazumiTheme.card(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

struct TimelineCard: View {
    var subject: BangumiSubject
    var showRating: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CoverImage(url: subject.coverURL)
                .frame(width: 92, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                Text(subject.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)
                Text(metadata)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                HStack {
                    if showRating, subject.score > 0 {
                        Label(String(format: "%.1f", subject.score), systemImage: "star.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(KazumiTheme.chip(scheme), in: Capsule())
                    }
                    if subject.rank > 0 {
                        Text("Rank \(subject.rank)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 156, alignment: .leading)
        .background(KazumiTheme.card(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var metadata: String {
        let tags = subject.metaTags.isEmpty ? subject.tags.map(\.name) : subject.metaTags
        let names = tags.prefix(3).joined(separator: " · ")
        if !names.isEmpty { return names }
        return subject.name == subject.displayName ? subject.airDate : subject.name
    }
}

struct EmptyHint: View {
    var title: String
    var message: String
    var systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: {
            Text(message)
        })
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
