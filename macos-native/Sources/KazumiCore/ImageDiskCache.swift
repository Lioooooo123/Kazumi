// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import Foundation

/// Disk cache for cover images. Memory caching stays in the AppKit layer so
/// this type can be tested with the Linux toolchain.
public actor ImageDiskCache {
    public let directory: URL
    public let maxBytes: Int

    public init(directory: URL, maxBytes: Int = 200 * 1024 * 1024) {
        self.directory = directory
        self.maxBytes = maxBytes
    }

    public func data(for url: URL) -> Data? {
        let file = fileURL(for: url)
        return try? Data(contentsOf: file)
    }

    public func store(_ data: Data, for url: URL) {
        let file = fileURL(for: url)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            try trimIfNeeded()
        } catch {
            return
        }
    }

    public func fetch(_ url: URL, loader: @Sendable () async throws -> Data) async throws -> Data {
        if let cached = cachedData(for: url) {
            return cached
        }
        let loaded = try await loader()
        store(loaded, for: url)
        return loaded
    }

    /// Downloads missing covers with a small concurrency cap. Cached URLs do not call `loader`.
    public func prefetch(
        _ urls: [URL],
        limit: Int = 4,
        loader: @escaping @Sendable (URL) async throws -> Data
    ) async {
        var pending: [URL] = []
        var seen = Set<String>()
        for url in urls where seen.insert(url.absoluteString).inserted {
            if cachedData(for: url) == nil {
                pending.append(url)
            }
        }
        guard !pending.isEmpty else { return }
        let width = min(max(1, limit), pending.count)
        var index = 0
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<width {
                let url = pending[index]
                index += 1
                group.addTask {
                    _ = try? await self.fetch(url) { try await loader(url) }
                }
            }
            while await group.next() != nil {
                guard index < pending.count else { continue }
                let url = pending[index]
                index += 1
                group.addTask {
                    _ = try? await self.fetch(url) { try await loader(url) }
                }
            }
        }
    }

    private func cachedData(for url: URL) -> Data? {
        guard let data = data(for: url), !data.isEmpty else { return nil }
        return data
    }

    private func fileURL(for url: URL) -> URL {
        let name = SHA256.hex(SHA256.hash(url.absoluteString))
        return directory.appendingPathComponent(name)
    }

    private func trimIfNeeded() throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        )
        let sized: [(URL, Int, Date)] = files.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            guard let size = values?.fileSize else { return nil }
            return (url, size, values?.contentModificationDate ?? .distantPast)
        }
        var total = sized.reduce(0) { $0 + $1.1 }
        guard total > maxBytes else { return }
        for item in sized.sorted(by: { $0.2 < $1.2 }) {
            if total <= maxBytes { break }
            try? FileManager.default.removeItem(at: item.0)
            total -= item.1
        }
    }
}
