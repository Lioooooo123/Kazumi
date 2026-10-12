// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import KazumiCore
import SwiftUI

struct FavoritesView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    private let columns = KazumiTheme.posterColumns

    private var visible: [FavoriteRecord] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return model.favorites }
        return model.favorites.filter { $0.displayName.lowercased().contains(needle) }
    }

    var body: some View {
        Group {
            if model.favorites.isEmpty {
                EmptyHint(
                    title: "还没有追番", message: "在番剧详情页选择「追番」，就能在这里找到。", systemImage: "heart", retryTitle: "浏览推荐"
                ) { model.sidebar = .popular }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        SectionHeading(title: "我的追番", subtitle: "\(model.favorites.count) 部番剧")
                        TextField("搜索追番", text: $query)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("搜索追番")
                            .frame(maxWidth: 320)
                        if visible.isEmpty {
                            ContentUnavailableView(
                                "没有符合条件的追番", systemImage: "magnifyingglass", description: Text("换一个关键词。")
                            )
                            .frame(minHeight: 180)
                        }
                        LazyVGrid(columns: columns, spacing: KazumiTheme.cardSpacing) {
                            ForEach(visible) { item in
                                Button {
                                    if let subject = model.subject(id: item.subjectID) {
                                        model.open(subject)
                                    } else {
                                        model.path.append(AppRoute.detail(item.subjectID))
                                    }
                                } label: {
                                    FavoriteCard(item: item)
                                }
                                .buttonStyle(ContentButtonStyle())
                                .accessibilityLabel(item.displayName)
                                .accessibilityHint("打开详情")
                                .contextMenu {
                                    Button("取消追番", role: .destructive) { model.removeFavorite(item.subjectID) }
                                }
                            }
                        }
                    }
                    .padding(KazumiTheme.pagePadding)
                    .frame(maxWidth: KazumiTheme.pageWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("追番")
    }
}

struct FavoriteCard: View {
    var item: FavoriteRecord
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PosterArtwork(url: item.imageURL)
            Text(item.displayName)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ContinueCard: View {
    var item: HistoryRecord
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            CoverImage(url: item.imageURL)
                .frame(width: 46, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.headline)
                    .lineLimit(2)
                Text(item.episodeName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ProgressView(value: item.progress)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 272, alignment: .leading)
        .background(KazumiTheme.card(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmClear = false

    var body: some View {
        @Bindable var model = model
        let rows = model.filteredHistory()
        Group {
            if model.history.isEmpty {
                EmptyHint(
                    title: "还没有播放记录", message: "开始观看后，可以在这里继续播放。", systemImage: "clock", retryTitle: "搜索番剧"
                ) { model.sidebar = .search }
            } else {
                VStack(spacing: 0) {
                    HStack {
                        TextField("搜索历史", text: $model.historyQuery)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("搜索历史")
                        Toggle("只看未看完", isOn: $model.historyUnfinishedOnly)
                            .toggleStyle(.checkbox)
                    }
                    .padding(KazumiTheme.pagePadding)
                    if rows.isEmpty {
                        ContentUnavailableView(
                            "没有符合条件的记录", systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("换一个关键词，或关掉未看完筛选。"))
                    } else {
                        List {
                            ForEach(rows) { item in
                                Button {
                                    model.play(model.playback(from: item))
                                } label: {
                                    HStack(spacing: 12) {
                                        CoverImage(url: item.imageURL)
                                            .frame(width: 54, height: 76)
                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.displayName).font(.body.weight(.medium))
                                            Text(item.episodeName).font(.callout).foregroundStyle(.secondary)
                                            HStack(spacing: 8) {
                                                ProgressView(value: item.progress)
                                                    .frame(maxWidth: 220)
                                                Text("\(Int((item.progress * 100).rounded()))%")
                                                    .font(.caption.monospacedDigit())
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(ContentButtonStyle())
                                .accessibilityLabel(
                                    "\(item.displayName)，\(item.episodeName)，已看 \(Int((item.progress * 100).rounded()))%"
                                )
                                .contextMenu {
                                    Button("删除", role: .destructive) { model.removeHistory(item.id) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("历史")
        .toolbar {
            if !model.history.isEmpty {
                ToolbarItem {
                    Button("清空") { confirmClear = true }
                        .accessibilityLabel("清空播放历史")
                }
            }
        }
        .confirmationDialog("清空播放历史？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空", role: .destructive) { model.clearHistory() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("本机的播放进度会被删掉。")
        }
    }
}
