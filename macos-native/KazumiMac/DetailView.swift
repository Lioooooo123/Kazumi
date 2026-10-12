// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import SwiftUI
import KazumiCore

struct DetailView: View {
    var subjectID: Int
    @Environment(AppModel.self) private var model

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
                }
                .padding(24)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error = model.detailError {
                EmptyHint(title: "条目加载失败", message: error, systemImage: "exclamationmark.triangle")
                Button("重试") { Task { await model.loadSubject(subjectID) } }
            } else {
                ProgressView("正在读取条目")
                    .frame(maxWidth: .infinity, minHeight: 240)
            }
        }
        .navigationTitle(model.subject(id: subjectID)?.displayName ?? "详情")
        .task { await model.loadSubject(subjectID) }
    }

    private func header(_ subject: BangumiSubject) -> some View {
        HStack(alignment: .top, spacing: 20) {
            CoverImage(url: subject.coverURL)
                .frame(width: 180, height: 276)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 10) {
                Text(subject.displayName)
                    .font(.system(size: 28, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                if subject.name != subject.displayName {
                    Text(subject.name).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    if subject.score > 0 {
                        Label(String(format: "%.1f", subject.score), systemImage: "star.fill")
                    }
                    if subject.rank > 0 { Text("Bangumi #\(subject.rank)") }
                    if subject.episodeCount > 0 { Text("\(subject.episodeCount) 话") }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                if !subject.airDate.isEmpty {
                    Text("开播 \(subject.airDate)").font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    Button {
                        model.toggleFavorite(subject)
                    } label: {
                        Label(model.isFavorite(subject.id) ? "已追番" : "追番", systemImage: model.isFavorite(subject.id) ? "heart.fill" : "heart")
                    }
                    .buttonStyle(.borderedProminent)
                    Button("搜索片源") {
                        Task { await model.findSources(for: subject) }
                    }
                    .disabled(model.sourceLoading || model.enabledRules.isEmpty)
                }
                if model.enabledRules.isEmpty {
                    Text("导入规则后才能搜索片源。").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
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
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}
