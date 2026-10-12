// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import KazumiCore
import SwiftUI

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var queryFocused: Bool
    @State private var lastSubmittedQuery = ""
    private let columns = KazumiTheme.posterColumns

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeading(title: "找一部想看的番剧", subtitle: "同时搜索番剧资料和已启用的片源")
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("番剧名称或片源关键词", text: $model.searchQuery)
                            .textFieldStyle(.plain)
                            .focused($queryFocused)
                            .accessibilityLabel("搜索番剧或片源")
                            .onSubmit { runSearch() }
                    }
                    .padding(12)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                queryFocused ? Color.accentColor : Color.secondary.opacity(0.3),
                                lineWidth: queryFocused ? 2 : 1)
                    }
                    Button("搜索") { runSearch() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .disabled(
                            model.searching
                                || model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                        .accessibilityLabel("开始搜索")
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
                    HStack {
                        Label("安装规则后可搜索播放来源", systemImage: "puzzlepiece.extension")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("前往规则") { model.sidebar = .rules }
                    }
                }
                if model.searching && model.searchBangumi.isEmpty && model.searchGroups.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在搜索 Bangumi 和已启用的规则")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("正在搜索")
                } else if let error = model.searchError, model.searchBangumi.isEmpty,
                    model.searchGroups.isEmpty
                {
                    EmptyHint(title: "搜索失败", message: error, systemImage: "magnifyingglass") {
                        Task { await model.search() }
                    }
                } else if !model.searching, model.searchBangumi.isEmpty, model.searchGroups.isEmpty,
                    model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    EmptyHint(
                        title: "输入番剧名称", message: "回车即可搜索，也可以展开「以图搜番」识别截图。", systemImage: "magnifyingglass")
                } else if !model.searching, model.searchBangumi.isEmpty, model.searchGroups.isEmpty,
                    !lastSubmittedQuery.isEmpty,
                    lastSubmittedQuery == model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                {
                    EmptyHint(
                        title: "没有找到匹配的番剧", message: "试试中文名、原名，或更短的关键词。", systemImage: "magnifyingglass")
                }
                if let error = model.searchError,
                    !model.searchBangumi.isEmpty || !model.searchGroups.isEmpty
                {
                    Text(error).foregroundStyle(.red).font(.callout)
                }
                LoadingBar(
                    active: model.searching && (!model.searchBangumi.isEmpty || !model.searchGroups.isEmpty))
                if !model.searchBangumi.isEmpty {
                    SectionHeading(title: "番剧资料", subtitle: "Bangumi · \(model.searchBangumi.count) 个结果")
                    LazyVGrid(columns: columns, spacing: KazumiTheme.cardSpacing) {
                        ForEach(model.searchBangumi) { subject in
                            Button {
                                model.open(subject)
                            } label: {
                                BangumiCard(subject: subject)
                            }
                            .buttonStyle(ContentButtonStyle())
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
                                    model.path.append(
                                        AppRoute.episodes(
                                            EpisodeRoute(
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
                                    .background(
                                        .background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(ContentButtonStyle())
                            }
                        }
                    }
                }
            }
            .padding(KazumiTheme.pagePadding)
            .frame(maxWidth: KazumiTheme.pageWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("搜索")
        .onAppear { queryFocused = true }
    }

    private func runSearch() {
        lastSubmittedQuery = model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await model.search() }
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
                if loading {
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonLine(width: 120)
                        HStack(spacing: 8) {
                            ForEach(0..<6, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(width: 88, height: 28)
                            }
                        }
                    }
                    .accessibilityLabel("正在读取分集")
                }
                if let error {
                    EmptyHint(title: "分集读取失败", message: error, systemImage: "exclamationmark.triangle") {
                        Task { await load() }
                    }
                } else if !loading, roads.isEmpty {
                    EmptyHint(title: "没有分集", message: "这条片源没有解析出播放线路。", systemImage: "list.bullet")
                }
                ForEach(roads) { road in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(road.name).font(.headline)
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 144, maximum: 220), spacing: 12)], spacing: 12
                        ) {
                            ForEach(Array(road.episodes.enumerated()), id: \.element.id) { index, episode in
                                Button {
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
                                } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("第 \(index + 1) 集").font(.headline)
                                        Text(episode.name).font(.caption)
                                            .lineLimit(2, reservesSpace: true)
                                            .multilineTextAlignment(.leading)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                                }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.roundedRectangle(radius: KazumiTheme.cardRadius))
                                .controlSize(.large)
                                .accessibilityLabel("第 \(index + 1) 集，\(episode.name)")
                                .help(episode.name)
                                .accessibilityHint("播放这一集")
                            }
                        }
                    }
                }
            }
            .padding(KazumiTheme.pagePadding)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
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
