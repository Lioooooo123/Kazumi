// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import Foundation

/// Copy used on the timeline card. Matches `BangumiTimelineCard._supportingText`.
public enum CatalogText {
    public static func timelineLine(
        title: String,
        info: String,
        metaTags: [String],
        tagNames: [String],
        originalName: String
    ) -> String {
        var metadata: [String] = []
        if let episodes = leadingEpisodeCount(in: info) {
            metadata.append("\(episodes) 话")
        }
        let tags = metaTags.isEmpty ? tagNames : metaTags
        var seen = Set<String>()
        for name in tags {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || !seen.insert(trimmed).inserted { continue }
            metadata.append(trimmed)
        }
        if !metadata.isEmpty {
            return metadata.prefix(3).joined(separator: " · ")
        }
        let original = originalName.trimmingCharacters(in: .whitespacesAndNewlines)
        return original == title.trimmingCharacters(in: .whitespacesAndNewlines) ? "" : original
    }

    /// `12话` or `12 话 / …` at the start of a calendar `info` string.
    static func leadingEpisodeCount(in info: String) -> String? {
        let pattern = #"^\s*([1-9]\d*)\s*[话話集](?=\s*(?:[/／]|$))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(info.startIndex..<info.endIndex, in: info)
        guard let match = regex.firstMatch(in: info, range: range),
              let slice = Range(match.range(at: 1), in: info) else {
            return nil
        }
        return String(info[slice])
    }
}

extension BangumiSubject {
    public var timelineLine: String {
        CatalogText.timelineLine(
            title: displayName,
            info: info,
            metaTags: metaTags,
            tagNames: tags.map(\.name),
            originalName: name
        )
    }
}

/// Where to resume, using the same edges as the player: skip the first second
/// and the last five seconds. Prefer the real media duration once it is known.
public enum PlaybackResume {
    public static func position(saved: Double, savedDuration: Double, mediaDuration: Double) -> Double? {
        let duration = mediaDuration > 1 ? mediaDuration : savedDuration
        guard saved > 1, duration > 1, saved < duration - 5 else { return nil }
        return saved
    }
}

public enum EpisodeSequence {
    public static func next(after url: String, in episodes: [EpisodeEntry]) -> EpisodeEntry? {
        guard let index = episodes.firstIndex(where: { $0.url == url }) else { return nil }
        let following = episodes.index(after: index)
        guard following < episodes.endIndex else { return nil }
        return episodes[following]
    }
}

/// Latest unfinished item per subject, in history order.
public enum ContinueWatching {
    public static func select(_ records: [HistoryRecord], limit: Int = 12) -> [HistoryRecord] {
        var seen = Set<String>()
        var result: [HistoryRecord] = []
        for record in records {
            let key = record.subjectID > 0 ? "id:\(record.subjectID)" : record.pageURL
            if !seen.insert(key).inserted { continue }
            if PlaybackResume.position(saved: record.position, savedDuration: record.duration, mediaDuration: 0) == nil,
               record.duration > 1 {
                continue
            }
            result.append(record)
            if result.count == limit { break }
        }
        return result
    }
}

public struct DanmakuPlacement: Equatable, Sendable, Identifiable {
    public var comment: DanmakuComment
    public var lane: Int

    public var id: Int { comment.id }

    public init(comment: DanmakuComment, lane: Int) {
        self.comment = comment
        self.lane = lane
    }
}

/// Puts comments that would overlap into different lanes.
///
/// A lane stays busy for `travel / laneCount` seconds after a scroll comment
/// enters it. Top and bottom comments do not take those lanes.
public enum DanmakuLanes {
    public static func assign(
        comments: [DanmakuComment],
        at time: Double,
        travel: Double,
        laneCount: Int,
        shield: [String]
    ) -> [DanmakuPlacement] {
        let lanes = max(1, laneCount)
        let window = max(travel, 0.1)
        let visible = comments.filter { comment in
            if DanmakuMatching.blocked(comment, shield: shield) { return false }
            let age = time - comment.time
            return age >= 0 && age <= window
        }.sorted { lhs, rhs in
            if lhs.time == rhs.time { return lhs.id < rhs.id }
            return lhs.time < rhs.time
        }
        let gap = window / Double(lanes)
        var busyUntil = Array(repeating: -Double.greatestFiniteMagnitude, count: lanes)
        var placed: [DanmakuPlacement] = []
        placed.reserveCapacity(visible.count)
        for comment in visible {
            if comment.isTop || comment.isBottom {
                placed.append(DanmakuPlacement(comment: comment, lane: abs(comment.id) % min(3, lanes)))
                continue
            }
            var chosen = 0
            var chosenSlack = -Double.greatestFiniteMagnitude
            var foundFree = false
            for lane in 0..<lanes {
                if busyUntil[lane] <= comment.time {
                    chosen = lane
                    foundFree = true
                    break
                }
                let slack = comment.time - busyUntil[lane]
                if slack > chosenSlack {
                    chosenSlack = slack
                    chosen = lane
                }
            }
            if !foundFree {
                // Every lane is still busy. `chosen` is the one furthest along.
            }
            busyUntil[chosen] = comment.time + gap
            placed.append(DanmakuPlacement(comment: comment, lane: chosen))
        }
        return placed
    }
}
