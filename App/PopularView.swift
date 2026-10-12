// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import KazumiCore
import SwiftUI

struct PopularView: View {
    @Environment(AppModel.self) private var model
    private let columns = KazumiTheme.posterColumns

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !model.continueWatching.isEmpty {
                        continueRow
                    }
                    SectionHeading(
                        title: model.popularTag.isEmpty ? "发现好番" : model.popularTag,
                        subtitle: "来自 Bangumi 的热门番剧")
                    if model.popularLoading && model.popular.isEmpty {
                        popularSkeleton
                    } else if let error = model.popularError, model.popular.isEmpty {
                        EmptyHint(title: "推荐加载失败", message: error, systemImage: "wifi.exclamationmark") {
                            Task { await model.loadPopular(reset: true) }
                        }
                    } else if model.popular.isEmpty {
                        EmptyHint(title: "没有推荐", message: "换一个标签，或稍后再刷新。", systemImage: "square.grid.2x2")
                    } else {
                        LazyVGrid(columns: columns, spacing: KazumiTheme.cardSpacing) {
                            ForEach(model.popular) { subject in
                                Button {
                                    model.open(subject)
                                } label: {
                                    BangumiCard(subject: subject)
                                }
                                .buttonStyle(ContentButtonStyle())
                                .onAppear {
                                    if subject.id == model.popular.last?.id {
                                        Task { await model.loadPopular(reset: false) }
                                    }
                                }
                            }
                        }
                        LoadingBar(active: model.popularLoading && !model.popular.isEmpty)
                    }
                }
                .id("top")
                .padding(KazumiTheme.pagePadding)
                .frame(maxWidth: KazumiTheme.pageWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem {
                    Button {
                        proxy.scrollTo("top")
                    } label: {
                        Image(systemName: "arrow.up.to.line")
                    }
                    .buttonStyle(.automatic)
                    .help("回到顶部")
                    .accessibilityLabel("回到顶部")
                    .disabled(model.popular.isEmpty)
                }
            }
        }
        .navigationTitle(model.popularTag.isEmpty ? "推荐" : model.popularTag)
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("推荐") { select("") }
                    Divider()
                    ForEach(KazumiCore.defaultAnimeTags, id: \.self) { tag in
                        Button(tag) { select(tag) }
                    }
                } label: {
                    Label(
                        model.popularTag.isEmpty ? "全部" : model.popularTag,
                        systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem {
                Button {
                    Task { await model.loadPopular(reset: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新推荐")
                .accessibilityLabel("刷新推荐")
                .disabled(model.popularLoading)
            }
        }
        .task { if model.popular.isEmpty { await model.loadPopular(reset: true) } }
    }

    private var popularSkeleton: some View {
        LazyVGrid(columns: columns, spacing: KazumiTheme.cardSpacing) {
            ForEach(0..<8, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: KazumiTheme.cardRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                        .aspectRatio(0.65, contentMode: .fit)
                    SkeletonLine(width: 96, height: 10)
                    SkeletonLine(width: 64, height: 10)
                }
            }
        }
        .accessibilityLabel("正在加载推荐")
    }

    private var continueRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "继续观看", subtitle: "从上次停下的地方继续")
            ScrollView(.horizontal) {
                LazyHStack(spacing: KazumiTheme.cardSpacing) {
                    ForEach(model.continueWatching) { item in
                        Button {
                            Task { await model.resume(item) }
                        } label: {
                            ContinueCard(item: item)
                                .overlay(alignment: .topTrailing) {
                                    if model.restoringHistoryID == item.id { ProgressView().padding(8) }
                                }
                        }
                        .buttonStyle(ContentButtonStyle())
                        .accessibilityLabel("继续观看 \(item.displayName)，\(item.episodeName)")
                    }
                }
            }
        }

    }

    private func select(_ tag: String) {
        model.popularTag = tag
        Task { await model.loadPopular(reset: true) }
    }
}
