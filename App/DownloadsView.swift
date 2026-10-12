// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import KazumiCore
import SwiftUI
import UniformTypeIdentifiers

struct DownloadsView: View {
    @Environment(AppModel.self) private var model
    @State private var picking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("下载目录")
                        .font(.headline)
                    Text(model.downloadFolder?.path ?? "应用默认目录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("选择目录") { picking = true }
                    .accessibilityLabel("选择下载目录")
            }
            .padding(KazumiTheme.pagePadding)
            Divider()
            if model.downloads.isEmpty {
                EmptyHint(
                    title: "还没有下载", message: "在播放器中选择「下载」，将视频保存到本机。", systemImage: "arrow.down.circle")
            } else {
                if activeCount > 0 {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在处理 \(activeCount) 个任务")
                            .font(.callout)
                    }
                    .padding(16)
                    .accessibilityLabel("正在处理 \(activeCount) 个下载")
                }
                List {
                    ForEach(model.downloads) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.title).font(.body.weight(.medium))
                                Spacer()
                                Text(statusTitle(item))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(item.status == "failed" ? Color.red : Color.secondary)
                            }
                            Text(item.episodeName)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            if item.status == "running" || item.status == "queued" {
                                ProgressView()
                                    .controlSize(.small)
                                    .accessibilityLabel(item.status == "queued" ? "等待下载" : "正在下载")
                            }
                            if item.receivedBytes > 0 {
                                Text(byteText(item.receivedBytes))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            if !item.error.isEmpty {
                                Text(item.error).font(.caption).foregroundStyle(.red)
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                        .contextMenu {
                            Button("删除记录", role: .destructive) { model.deleteDownload(item.id) }
                        }
                    }
                }
            }
        }
        .navigationTitle("下载")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                model.rememberDownloadFolder(url)
            }
        }
    }

    private var activeCount: Int {
        model.downloads.filter { $0.status == "running" || $0.status == "queued" }.count
    }

    private func statusTitle(_ item: DownloadRecord) -> String {
        switch item.status {
        case "queued": return "等待"
        case "running": return "下载中"
        case "finished": return "完成"
        case "failed": return "失败"
        default: return item.status
        }
    }

    private func byteText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
