// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import KazumiCore
import SwiftUI

struct DetailView: View {
    var subjectID: Int
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var summaryExpanded = false

    var body: some View {
        let subject = model.subject(id: subjectID)
        ScrollView {
            if let subject {
                VStack(alignment: .leading, spacing: 20) {
                    header(subject)
                    if !subject.summary.isEmpty {
                        SectionHeading(title: "简介")
                        Text(subject.summary)
                            .font(.body)
                            .lineLimit(summaryExpanded ? nil : 6)
                            .lineSpacing(4)
                            .frame(maxWidth: 720, alignment: .leading)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        if subject.summary.count > 240 {
                            Button(summaryExpanded ? "收起简介" : "展开简介") { summaryExpanded.toggle() }
                                .buttonStyle(.link)
                        }
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
        HStack(alignment: .top, spacing: 24) {
            CoverImage(url: subject.coverURL)
                .frame(width: 168, height: 258)
                .clipShape(RoundedRectangle(cornerRadius: KazumiTheme.cardRadius))
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(subject.displayName).font(.title.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if subject.name != subject.displayName {
                        Text(subject.name).font(.callout).foregroundStyle(.secondary)
                    }
                }
                HStack(alignment: .top, spacing: 24) {
                    if model.settings.showRating {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(
                                subject.score > 0 ? String(format: "%.1f", subject.score) : "暂无评分",
                                systemImage: "star.fill"
                            )
                            .font(.title2.weight(.semibold).monospacedDigit())
                            Text(subject.votes > 0 ? "\(subject.votes) 人评分" : "Bangumi 评分")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if subject.rank > 0 {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("#\(subject.rank)").font(.title2.weight(.semibold).monospacedDigit())
                                Text("Bangumi 排名").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(subject.airDate.isEmpty ? "未定" : subject.airDate).font(.headline)
                        Text("首播日期").font(.caption).foregroundStyle(.secondary)
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { subjectActions(subject) }
                    VStack(alignment: .leading, spacing: 8) { subjectActions(subject) }
                }
                if model.enabledRules.isEmpty {
                    Text("先安装片源规则，再选择要播放的分集。")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func subjectActions(_ subject: BangumiSubject) -> some View {
        Button {
            if model.enabledRules.isEmpty {
                model.sidebar = .rules
            } else {
                Task { await model.findSources(for: subject) }
            }
        } label: {
            Label(
                model.enabledRules.isEmpty ? "安装片源规则" : (model.sourceLoading ? "查找中…" : "查找片源"),
                systemImage: model.enabledRules.isEmpty ? "puzzlepiece.extension" : "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(model.sourceLoading)
        Button {
            model.toggleFavorite(subject)
        } label: {
            Label(
                model.isFavorite(subject.id) ? "已追番" : "追番",
                systemImage: model.isFavorite(subject.id) ? "heart.fill" : "heart")
        }
        .controlSize(.large)
        .accessibilityValue(model.isFavorite(subject.id) ? "已追番" : "未追番")
        Menu {
            Button("同步到 Bangumi") { Task { await model.syncCollection(subject.id) } }
                .disabled(model.settings.bangumiToken.isEmpty)
            if model.settings.bangumiToken.isEmpty {
                SettingsLink { Text("设置 Bangumi 令牌…") }
            }
        } label: {
            Label("更多", systemImage: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("更多番剧操作")
    }

    @ViewBuilder
    private func creditSection(_ subject: BangumiSubject) -> some View {
        let people = model.subjectCredits[subject.id] ?? []
        let crew = model.subjectStaff[subject.id] ?? []
        let notes = model.subjectComments[subject.id] ?? []
        if !people.isEmpty {
            Text("角色").font(.title3.weight(.semibold))
            Text(
                people.prefix(12).map { $0.role.isEmpty ? $0.name : "\($0.name) · \($0.role)" }.joined(
                    separator: "，")
            )
            .font(.callout)
        }
        if !crew.isEmpty {
            Text("制作人员").font(.title3.weight(.semibold))
            Text(
                crew.prefix(12).map { $0.role.isEmpty ? $0.name : "\($0.name) · \($0.role)" }.joined(
                    separator: "，")
            )
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
            SectionHeading(title: "播放来源", subtitle: "选择片源后查看分集")
            if groups.isEmpty {
                Text("没有启用的规则。").foregroundStyle(.secondary)
            }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.ruleName).font(.headline)
                    if let error = group.error {
                        Text(error).font(.callout).foregroundStyle(.secondary)
                    } else if group.hits.isEmpty {
                        Text("没有找到匹配的番剧").font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(group.hits.prefix(12)) { hit in
                        Button {
                            model.path.append(
                                AppRoute.episodes(
                                    EpisodeRoute(
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
                        .buttonStyle(ContentButtonStyle())
                        .accessibilityLabel("播放 \(hit.name)")
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    KazumiTheme.card(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}
