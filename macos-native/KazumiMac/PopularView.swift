// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import SwiftUI
import KazumiCore

struct PopularView: View {
    @Environment(AppModel.self) private var model
    private let columns = [GridItem(.adaptive(minimum: 148, maximum: 190), spacing: KazumiTheme.cardSpacing)]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 0).id("top")
                if !model.continueWatching.isEmpty {
                    continueRow
                }
                if model.popularLoading {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(height: 4)
                        .padding(.horizontal, 20)
                }
                LazyVGrid(columns: columns, spacing: KazumiTheme.cardSpacing) {
                    ForEach(model.popular) { subject in
                        Button {
                            model.open(subject)
                        } label: {
                            BangumiCard(subject: subject)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if subject.id == model.popular.last?.id {
                                Task { await model.loadPopular(reset: false) }
                            }
                        }
                    }
                }
                .padding(20)
                LoadingBar(active: model.popularLoading)
                if let error = model.popularError, model.popular.isEmpty {
                    EmptyHint(title: "推荐加载失败", message: error, systemImage: "wifi.exclamationmark")
                    Button("重试") { Task { await model.loadPopular(reset: true) } }
                        .padding(.bottom, 24)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    withAnimation { proxy.scrollTo("top") }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .padding(12)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(20)
                .help("回到顶部")
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
                    Label(model.popularTag.isEmpty ? "全部" : model.popularTag, systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem {
                Button {
                    Task { await model.loadPopular(reset: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新")
            }
        }
        .task { if model.popular.isEmpty { await model.loadPopular(reset: true) } }
    }

    private var continueRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("继续观看")
                .font(.system(size: 16, weight: .bold))
            ScrollView(.horizontal) {
                LazyHStack(spacing: KazumiTheme.cardSpacing) {
                    ForEach(model.continueWatching) { item in
                        Button {
                            model.play(model.playback(from: item))
                        } label: {
                            ContinueCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func select(_ tag: String) {
        model.popularTag = tag
        Task { await model.loadPopular(reset: true) }
    }
}
