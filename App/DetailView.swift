// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import SwiftUI
import KazumiCore

struct DetailView: View {
    var subjectID: Int
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let subject = model.subject(id: subjectID)
        ScrollView {
            if let subject {
                VStack(alignment: .leading, spacing: 20) {
                    header(subject)
                    if !subject.summary.isEmpty {
                        Text(subject.summary)
                            .font(.body)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !subject.tags.isEmpty {
                        TagWrap(tags: subject.tags.prefix(16).map(\.name))
                    }
                    sourceSection(subject)
                    creditSection(subject)
                }
                .padding(24)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error = model.detailError {
                EmptyHint(title: "条目加载失败", message: error, systemImage: "exclamationmark.triangle") {
                    Task { await model.loadSubject(subjectID) }
                }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    RoundedRectangle(cornerRadius: KazumiTheme.cardRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 168, height: 258)
                    VStack(alignment: .leading, spacing: 10) {
                        SkeletonLine(width: 220, height: 18)
                        SkeletonLine(width: 140)
                        SkeletonLine(width: 96)
                        SkeletonLine(width: 180)
                    }
                    Spacer()
                }
                .padding(24)
                .frame(maxWidth: .infinity, minHeight: 320, alignment: .topLeading)
                .accessibilityLabel("正在读取条目")
            }
        }
        .navigationTitle(model.subject(id: subjectID)?.displayName ?? "详情")
        .task {
            await model.loadSubject(subjectID)
            await model.loadSubjectExtras(subjectID)
        }
    }

    private func header(_ subject: BangumiSubject) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(subject.displayName)
                .font(.system(size: 24, weight: .semibold))
                .lineLimit(2)
            HStack(alignment: .top, spacing: 16) {
                CoverImage(url: subject.coverURL)
                    .frame(width: 168, height: 258)
                    .clipShape(RoundedRectangle(cornerRadius: KazumiTheme.cardRadius, style: .continuous))
                VStack(alignment: .leading, spacing: 8) {
                    if subject.name != subject.displayName {
                        Text(subject.name).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text("放送开始")
                        .font(.callout)
                    Text(subject.airDate.isEmpty ? "未知" : subject.airDate)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                    if model.settings.showRating {
                        Text(subject.votes > 0 ? "\(subject.votes) 人评分" : "暂无评分人数")
                            .font(.callout)
                        HStack(spacing: 8) {
                            Text(subject.score > 0 ? String(format: "%.1f", subject.score) : "—")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                            ScoreStars(score: subject.score)
                        }
                        Text("Bangumi Ranked")
                            .font(.callout)
                        Text(subject.rank > 0 ? "#\(subject.rank)" : "—")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }
                    Spacer(minLength: 0)
                    HStack {
                        Button {
                            model.toggleFavorite(subject)
                        } label: {
                            Label(model.isFavorite(subject.id) ? "已追番" : "追番", systemImage: model.isFavorite(subject.id) ? "heart.fill" : "heart")
                        }
                        .buttonStyle(.borderedProminent)
                        Button("同步到 Bangumi") { Task { await model.syncCollection(subject.id) } }
                            .disabled(model.settings.bangumiToken.isEmpty)
                            .help(model.settings.bangumiToken.isEmpty ? "先在设置里填写访问令牌" : "标记为在看")
                        Button("搜索片源") {
                            Task { await model.findSources(for: subject) }
                        }
                        .disabled(model.sourceLoading || model.enabledRules.isEmpty)
                    }
                    if model.enabledRules.isEmpty {
                        Text("导入规则后才能搜索片源。").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 258, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder
    private func creditSection(_ subject: BangumiSubject) -> some View {
        let people = model.subjectCredits[subject.id] ?? []
        let crew = model.subjectStaff[subject.id] ?? []
        let notes = model.subjectComments[subject.id] ?? []
        if !people.isEmpty {
            Text("角色").font(.title3.weight(.semibold))
            Text(people.prefix(12).map { $0.role.isEmpty ? $0.name : "\($0.name) · \($0.role)" }.joined(separator: "，"))
                .font(.callout)
        }
        if !crew.isEmpty {
            Text("Staff").font(.title3.weight(.semibold))
            Text(crew.prefix(12).map { $0.role.isEmpty ? $0.name : "\($0.name) · \($0.role)" }.joined(separator: "，"))
                .font(.callout)
        }
        if !notes.isEmpty {
            Text("评论").font(.title3.weight(.semibold))
            ForEach(Array(notes.prefix(6))) { note in
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.user).font(.caption).foregroundStyle(.secondary)
                    Text(note.text).font(.callout)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private func sourceSection(_ subject: BangumiSubject) -> some View {
        if model.sourceLoading, model.sourceGroups[subject.id] == nil {
            ProgressView("正在用已启用的规则搜索")
        }
        if let groups = model.sourceGroups[subject.id] {
            Text("片源").font(.title3.weight(.semibold))
            if groups.isEmpty {
                Text("没有启用的规则。").foregroundStyle(.secondary)
            }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.ruleName).font(.headline)
                    if let error = group.error {
                        Text(error).font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(group.hits.prefix(12)) { hit in
                        Button {
                            model.path.append(AppRoute.episodes(EpisodeRoute(
                                ruleName: group.ruleName,
                                title: hit.name,
                                source: hit.source,
                                subjectID: subject.id,
                                subjectName: subject.displayName,
                                coverURL: subject.coverURL
                            )))
                        } label: {
                            HStack {
                                Text(hit.name)
                                Spacer()
                                Image(systemName: "play.circle")
                                    .foregroundStyle(Color.accentColor)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("播放 \(hit.name)")
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(KazumiTheme.card(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}

private struct ScoreStars: View {
    var score: Double

    var body: some View {
        let filled = score > 0 ? score / 2 : 0
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { index in
                let threshold = Double(index) + 1
                Image(systemName: filled >= threshold ? "star.fill" : filled >= threshold - 0.5 ? "star.leadinghalf.filled" : "star")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .accessibilityLabel(score > 0 ? String(format: "评分 %.1f", score) : "暂无评分")
    }
}
