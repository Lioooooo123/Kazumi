// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import SwiftUI
import KazumiCore
import UniformTypeIdentifiers

struct RulesView: View {
    @Environment(AppModel.self) private var model
    @State private var pasted = ""
    @State private var message = ""
    @State private var importing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("规则与 Flutter 版使用同一份 JSON。可以粘贴规则数组、单条规则，或 kazumi:// 分享链接。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextEditor(text: $pasted)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))
                HStack {
                    Button("导入文本") { importText(pasted) }
                        .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("从文件导入") { importing = true }
                    if !message.isEmpty {
                        Text(message).font(.callout).foregroundStyle(.secondary)
                    }
                }
                if model.rules.isEmpty {
                    EmptyHint(title: "没有规则", message: "导入后即可在搜索和详情页使用。", systemImage: "puzzlepiece.extension")
                } else {
                    ForEach(model.rules) { installed in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(installed.plugin.name).font(.headline)
                                Text(meta(installed))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            Toggle("启用", isOn: Binding(
                                get: { installed.enabled },
                                set: { model.setRuleEnabled(installed.id, $0) }
                            ))
                            .toggleStyle(.switch)
                            Button(role: .destructive) {
                                model.deleteRule(installed.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(12)
                        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 860, alignment: .leading)
        }
        .navigationTitle("规则")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText, .text]) { result in
            switch result {
            case .success(let url):
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                if let text = try? String(contentsOf: url) {
                    importText(text)
                } else {
                    message = "无法读取文件"
                }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
    }

    private func meta(_ installed: InstalledRule) -> String {
        let plugin = installed.plugin
        return "v\(plugin.version.isEmpty ? "-" : plugin.version) · 搜索 \(plugin.searchMode) · 分集 \(plugin.chapterMode) · \(plugin.baseURL)"
    }

    private func importText(_ text: String) {
        let result = model.importRules(text)
        if result.plugins.isEmpty {
            message = result.failures.first ?? "没有导入任何规则"
        } else {
            message = "导入 \(result.plugins.count) 条" + (result.failures.isEmpty ? "" : "，\(result.failures.count) 条失败")
            pasted = ""
        }
    }
}
