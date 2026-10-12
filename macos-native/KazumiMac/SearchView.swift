// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import SwiftUI
import KazumiCore

struct SearchView: View {
    @Environment(AppModel.self) private var model
    private let columns = [GridItem(.adaptive(minimum: 148, maximum: 190), spacing: KazumiTheme.cardSpacing)]

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 8) {
                    TextField("搜索番剧、角色或片源", text: $model.searchQuery)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await model.search() } }
                    Button("搜索") { Task { await model.search() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.searching)
                }
                DisclosureGroup("以图搜番") {
                    HStack {
                        TextField("图片网址", text: $model.traceQuery)
                            .textFieldStyle(.roundedBorder)
                        Button("识别") { Task { await model.searchByImage() } }
                    }
                    if let error = model.traceError {
                        Text(error).font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(model.traceHits) { hit in
                        Text("\(hit.title) · 第 \(hit.episode) 集 · \(Int(hit.similarity * 100))%")
                            .font(.callout)
                    }
                }
                if model.enabledRules.isEmpty {
                    Text("还没有启用的规则。Bangumi 资料可以搜索；片源需要在「规则」页导入 Kazumi JSON 或 kazumi:// 链接。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let error = model.searchError {
                    Text(error).foregroundStyle(.red).font(.callout)
                }
                LoadingBar(active: model.searching)
                if !model.searchBangumi.isEmpty {
                    Text("Bangumi")
                        .font(.title3.weight(.semibold))
                    LazyVGrid(columns: columns, spacing: KazumiTheme.cardSpacing) {
                        ForEach(model.searchBangumi) { subject in
                            Button { model.open(subject) } label: { BangumiCard(subject: subject) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                ForEach(model.searchGroups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.ruleName).font(.title3.weight(.semibold))
                        if let error = group.error {
                            Text(error).font(.callout).foregroundStyle(.secondary)
                            if let page = group.captchaURL, !page.isEmpty {
                                Button("打开验证") {
                                    model.captchaPlugin = group.ruleName
                                    model.captchaURL = page
                                }
                                .accessibilityLabel("打开 \(group.ruleName) 的验证页面")
                            }
                        } else if group.hits.isEmpty {
                            Text("没有结果").font(.callout).foregroundStyle(.secondary)
                        } else {
                            ForEach(group.hits) { hit in
                                Button {
                                    model.path.append(AppRoute.episodes(EpisodeRoute(
                                        ruleName: group.ruleName,
                                        title: hit.name,
                                        source: hit.source,
                                        subjectID: 0,
                                        subjectName: hit.name,
                                        coverURL: ""
                                    )))
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(hit.name).foregroundStyle(.primary)
                                            Text(hit.source).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                    }
                                    .padding(10)
                                    .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .hoverLift()
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("搜索")
    }
}

struct EpisodesView: View {
    var route: EpisodeRoute
    @Environment(AppModel.self) private var model
    @State private var roads: [PlaybackRoad] = []
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(route.title).font(.title2.weight(.semibold))
                Text(route.ruleName).font(.callout).foregroundStyle(.secondary)
                if loading { ProgressView("正在读取分集") }
                if let error {
                    Text(error).foregroundStyle(.red)
                    Button("重试") { Task { await load() } }
                }
                ForEach(roads) { road in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(road.name).font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88, maximum: 140), spacing: 8)], spacing: 8) {
                            ForEach(road.episodes) { episode in
                                Button(episode.name) {
                                    let subject = model.subject(id: route.subjectID)
                                    let request = model.playback(
                                        ruleName: route.ruleName,
                                        subject: subject,
                                        title: route.title,
                                        episode: episode,
                                        episodes: road.episodes
                                    )
                                    var playback = request
                                    if subject == nil {
                                        playback.subjectName = route.subjectName
                                        playback.coverURL = route.coverURL
                                        playback.subjectID = route.subjectID
                                    }
                                    model.play(playback)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .navigationTitle("分集")
        .task { await load() }
    }

    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            roads = try await model.chapters(for: route)
            if roads.isEmpty { error = "没有解析到播放线路" }
        } catch {
            self.error = describe(error)
        }
    }
}
