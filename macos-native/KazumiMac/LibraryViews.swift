// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import SwiftUI
import KazumiCore

struct FavoritesView: View {
    @Environment(AppModel.self) private var model
    private let columns = [GridItem(.adaptive(minimum: 148, maximum: 190), spacing: 12)]

    var body: some View {
        Group {
            if model.favorites.isEmpty {
                EmptyHint(title: "还没有追番", message: "在番剧详情页点「追番」，会记在这台 Mac 上。", systemImage: "heart")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(model.favorites) { item in
                            Button {
                                if let subject = model.subject(id: item.subjectID) {
                                    model.open(subject)
                                } else {
                                    model.path.append(AppRoute.detail(item.subjectID))
                                }
                            } label: {
                                FavoriteCard(item: item)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("取消追番", role: .destructive) { model.removeFavorite(item.subjectID) }
                            }
                        }
                    }
                    .padding(20)
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
        VStack(alignment: .leading, spacing: 0) {
            CoverImage(url: item.imageURL)
                .aspectRatio(0.65, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()
            Text(item.displayName)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
                .padding(8)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
        }
        .background(KazumiTheme.card(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.history.isEmpty {
                EmptyHint(title: "没有播放记录", message: "开始播放后，进度会记在本地。", systemImage: "clock")
            } else {
                List {
                    ForEach(model.history) { item in
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
                                    ProgressView(value: item.progress)
                                        .frame(maxWidth: 220)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("删除", role: .destructive) { model.removeHistory(item.id) }
                        }
                    }
                }
            }
        }
        .navigationTitle("历史")
        .toolbar {
            if !model.history.isEmpty {
                ToolbarItem {
                    Button("清空") { model.clearHistory() }
                }
            }
        }
    }
}
