// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import AppKit
import SwiftUI
import KazumiCore
import UniformTypeIdentifiers

struct RulesView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var filter = RuleCatalogFilter.all
    @State private var sort = RuleCatalogSort.lastUpdate
    @State private var remoteURL = ""
    @State private var pasted = ""
    @State private var message = ""
    @State private var importing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                catalogSection
                importSection
                installedSection
            }
            .padding(20)
            .frame(maxWidth: 860, alignment: .leading)
        }
        .navigationTitle("规则")
        .task { await model.refreshCatalog() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText, .text]) { result in
            switch result {
            case .success(let url):
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                if let text = try? String(contentsOf: url) {
                    submit(text)
                } else {
                    message = "无法读取文件"
                }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
    }

    private var installedPlugins: [PluginRule] {
        model.rules.map(\.plugin)
    }

    private var visibleCatalog: [RuleCatalogItem] {
        RuleCatalog.visible(
            items: model.catalog,
            installed: installedPlugins,
            query: query,
            filter: filter,
            sort: sort
        )
    }

    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("规则仓库")
                .font(.title3.weight(.semibold))
            Text("浏览 Kazumi 官方规则仓库，一键安装，并在有新版本时更新。版本号按段比较，不会用旧版本覆盖本地规则。")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Toggle("使用规则镜像", isOn: Binding(
                    get: { model.settings.useRuleMirror },
                    set: { enabled in
                        model.updateSettings { $0.useRuleMirror = enabled }
                        Task { await model.refreshCatalog() }
                    }
                ))
                .toggleStyle(.switch)
                Spacer()
                Button("全部更新") {
                    Task {
                        let text = await model.updateAllRules()
                        if !text.isEmpty { message = text }
                    }
                }
                .disabled(model.updatingAllRules || model.catalogLoading || updateCount == 0)
                Button("刷新") { Task { await model.refreshCatalog() } }
                    .disabled(model.catalogLoading)
            }
            if model.catalogLoading {
                ProgressView().controlSize(.small)
            }
            TextField("搜索规则或作者", text: $query)
                .textFieldStyle(.roundedBorder)
            HStack {
                Picker("筛选", selection: $filter) {
                    Text("全部 \(model.catalog.count)").tag(RuleCatalogFilter.all)
                    Text("已安装 \(installedCount)").tag(RuleCatalogFilter.installed)
                    Text("可更新 \(updateCount)").tag(RuleCatalogFilter.updates)
                }
                .pickerStyle(.segmented)
                Picker("排序", selection: $sort) {
                    Text("最近更新").tag(RuleCatalogSort.lastUpdate)
                    Text("名称").tag(RuleCatalogSort.name)
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            if let error = model.catalogError, model.catalog.isEmpty {
                ContentUnavailableView(
                    "无法访问规则仓库",
                    systemImage: "icloud.slash",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else if model.catalogLoading && model.catalog.isEmpty {
                ProgressView("正在读取规则仓库")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if visibleCatalog.isEmpty {
                ContentUnavailableView(
                    model.catalog.isEmpty ? "仓库暂无规则" : "没有符合条件的规则",
                    systemImage: "puzzlepiece.extension",
                    description: Text(model.catalog.isEmpty ? "刷新后会显示官方规则列表。" : "换一个关键词，或改筛选条件。")
                )
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ForEach(Array(visibleCatalog.enumerated()), id: \.offset) { _, item in
                    catalogRow(item)
                }
            }
            if let error = model.catalogError, !model.catalog.isEmpty {
                Text("刷新失败，正在显示上次获取的规则。\(error)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var installedCount: Int {
        model.catalog.filter { RuleUpdates.itemStatus(item: $0, installed: installedPlugins) != .install }.count
    }

    private var updateCount: Int {
        model.catalog.filter { RuleUpdates.itemStatus(item: $0, installed: installedPlugins) == .update }.count
    }

    private func catalogRow(_ item: RuleCatalogItem) -> some View {
        let status = RuleUpdates.itemStatus(item: item, installed: installedPlugins)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.headline)
                Text(catalogMeta(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            catalogAction(item, status: status)
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func catalogMeta(_ item: RuleCatalogItem) -> String {
        var parts = ["v\(item.version)", "作者 · \(item.author.isEmpty ? "未知" : item.author)"]
        if let date = item.updatedAt {
            parts.append("更新于 \(Self.dayFormatter.string(from: date))")
        }
        if item.antiCrawlerEnabled { parts.append("含验证支持") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func catalogAction(_ item: RuleCatalogItem, status: RuleCatalogItemStatus) -> some View {
        if model.busyRuleNames.contains(item.id) {
            ProgressView().controlSize(.small)
        } else if status == .installed {
            Label("已安装", systemImage: "checkmark")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            Button(status.actionTitle) {
                Task {
                    let text = await model.applyCatalogRule(named: item.name)
                    if !text.isEmpty { message = text }
                }
            }
            .disabled(model.updatingAllRules)
        }
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("导入")
                .font(.title3.weight(.semibold))
            Text("可以粘贴规则 JSON、kazumi:// 链接，或填一个规则文件的网址。剪贴板里的内容走同一条导入。")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                TextField("https:// 规则地址", text: $remoteURL)
                    .textFieldStyle(.roundedBorder)
                Button("导入链接") { submit(remoteURL) { remoteURL = "" } }
                    .disabled(remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack {
                Button("从剪贴板导入") { importClipboard() }
                Button("从文件导入") { importing = true }
                if !message.isEmpty {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            TextEditor(text: $pasted)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))
            Button("导入文本") { submit(pasted) { pasted = "" } }
                .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var installedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("已安装")
                .font(.title3.weight(.semibold))
            if model.rules.isEmpty {
                EmptyHint(title: "没有规则", message: "从上面的仓库安装，或导入 JSON / kazumi:// 链接。", systemImage: "puzzlepiece.extension")
            } else {
                ForEach(model.rules) { installed in
                    installedRow(installed)
                }
            }
        }
    }

    private func installedRow(_ installed: InstalledRule) -> some View {
        let plugin = installed.plugin
        let availability = RuleUpdates.availability(plugin: plugin, catalog: model.catalog, loaded: model.catalogLoaded)
        let author = RuleUpdates.displayAuthor(plugin: plugin, catalog: model.catalog)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(plugin.name).font(.headline)
                Text(installedMeta(plugin, author: author, availability: availability))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            if availability == .updatable {
                if model.busyRuleNames.contains(plugin.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Button("更新") {
                        Task {
                            let text = await model.applyCatalogRule(named: plugin.name)
                            if !text.isEmpty { message = text }
                        }
                    }
                    .disabled(model.updatingAllRules)
                }
            }
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

    private func installedMeta(_ plugin: PluginRule, author: String, availability: RuleUpdateAvailability) -> String {
        let version = plugin.version.isEmpty ? "-" : plugin.version
        let authorText = author.isEmpty ? "未知" : author
        return "v\(version) · 作者 · \(authorText) · \(availability.title) · 搜索 \(plugin.searchMode) · 分集 \(plugin.chapterMode)"
    }

    private func importClipboard() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        submit(text)
    }

    private func submit(_ text: String, clear: @escaping () -> Void = {}) {
        Task {
            let result = await model.importRemote(text)
            message = result
            if result.hasPrefix("导入 ") { clear() }
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
