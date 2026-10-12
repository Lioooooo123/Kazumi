// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import KazumiCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            Form {
                Section("外观") {
                    Picker("外观", selection: themeBinding) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("配色方案")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                            ForEach(KazumiCore.accentPalette, id: \.id) { item in
                                Button {
                                    model.updateSettings { $0.accent = item.id }
                                } label: {
                                    VStack(spacing: 6) {
                                        Circle()
                                            .fill(Color(hex: item.hex))
                                            .frame(width: 28, height: 28)
                                            .overlay {
                                                if model.settings.accent == item.id {
                                                    Image(systemName: "checkmark")
                                                        .font(.caption.bold())
                                                        .foregroundStyle(.primary)
                                                        .padding(4)
                                                        .background(.background, in: Circle())
                                                }
                                            }
                                        Text(item.name).font(.caption)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(ContentButtonStyle())
                                .accessibilityLabel(item.name)
                                .accessibilityValue(model.settings.accent == item.id ? "已选中" : "")
                            }
                        }
                    }
                    Toggle("显示番剧评分", isOn: boolBinding(\.showRating))
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("外观", systemImage: "paintbrush") }
            playbackSettings
                .tabItem { Label("播放", systemImage: "play.rectangle") }
            Form {
                Section("同步") {
                    TextField("WebDAV 地址", text: secretBinding(\.webDavURL))
                    TextField("用户名", text: secretBinding(\.webDavUsername))
                    SecureField("密码", text: secretBinding(\.webDavPassword))
                    Toggle("启用 WebDAV", isOn: boolBinding(\.webDavEnabled))
                    HStack(spacing: 8) {
                        Button(model.syncing ? "同步中" : "立即同步") { Task { await model.syncWebDAV() } }
                            .disabled(model.syncing || !model.settings.webDavEnabled)
                            .accessibilityLabel(model.syncing ? "正在同步" : "立即同步")
                        if model.syncing {
                            ProgressView().controlSize(.small)
                        }
                    }
                    Text("同步播放历史、追番和弹幕屏蔽词。Bangumi 令牌用于在详情页标记「在看」。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !model.notice.isEmpty {
                        Text(model.notice).font(.callout).foregroundStyle(.secondary)
                    }
                    SecureField("Bangumi 访问令牌", text: secretBinding(\.bangumiToken))
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("同步", systemImage: "arrow.triangle.2.circlepath") }
            Form {
                Section("网络") {
                    Toggle(
                        "使用 HTTP 代理",
                        isOn: Binding(
                            get: { model.settings.proxyEnabled },
                            set: { value in
                                model.updateSettings { $0.proxyEnabled = value }
                                model.refreshNetwork()
                            }
                        ))
                    TextField("代理主机", text: secretBinding(\.proxyHost))
                    TextField("端口", value: intBinding(\.proxyPort), format: .number)
                    Text("代理只作用于这个应用自己的请求。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("一起看") {
                    TextField("服务器", text: secretBinding(\.syncplayHost))
                    TextField("端口", value: intBinding(\.syncplayPort), format: .number)
                    Toggle("TLS", isOn: boolBinding(\.syncplayTLS))
                    Text("默认服务器为 syncplay.pl:8996。连接房间后可同步播放进度；当前支持基础房间同步。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("网络", systemImage: "network") }
            Form {
                Section("关于") {
                    LabeledContent("版本", value: "小栗子 \(KazumiCore.version)")
                    LabeledContent("规则 API", value: "\(KazumiCore.ruleAPILevel)")
                    Text("小栗子是 Kazumi 的原生 macOS 客户端，采用 GPL-3.0-or-later。图标由 Yuquanaaa 创作，授权范围沿用上游说明。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("项目主页", destination: URL(string: KazumiCore.projectURL)!)
                    Link("Bangumi", destination: URL(string: "https://bangumi.tv/")!)
                    Link("弹弹play", destination: URL(string: "https://www.dandanplay.com/")!)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 640, height: 600)
        .tint(KazumiTheme.accent(model.settings.accent))
        .preferredColorScheme(KazumiTheme.scheme(model.settings.themeMode))
    }

    private var playbackSettings: some View {
        Form {
            Section("播放") {
                Picker("默认倍速", selection: rateBinding) {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        Text(rate == 1 ? "1.0x" : String(format: "%.2gx", rate)).tag(rate)
                    }
                }
            }
            Section("画面") {
                Toggle("深色时使用纯黑背景", isOn: boolBinding(\.oled))
                Picker("超分", selection: intBinding(\.superResolution)) {
                    ForEach(SuperResolutionMode.allCases, id: \.rawValue) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                Text(SuperResolutionMode.fromStorage(model.settings.superResolution).detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("外部播放器", selection: secretBinding(\.externalPlayer)) {
                    Text("系统默认").tag("")
                    Text("IINA").tag("iina")
                    Text("VLC").tag("vlc")
                    Text("浏览器").tag("browser")
                }
            }
            Section("弹幕") {
                Toggle("显示弹幕", isOn: boolBinding(\.danmakuEnabled))
                Slider(value: opacityBinding, in: 0.3...1.0) {
                    Text("不透明度 \(Int((model.settings.danmakuOpacity * 100).rounded()))%")
                }
                Slider(value: fontBinding, in: 12.0...32.0) {
                    Text("字号 \(Int(model.settings.danmakuFontSize.rounded()))")
                }
                Slider(value: durationBinding, in: 4.0...16.0) {
                    Text("滚动时长 \(Int(model.settings.danmakuDuration.rounded())) 秒")
                }
                TextField("屏蔽词，用逗号分隔", text: shieldBinding)
                DisclosureGroup("弹弹play 凭据") {
                    TextField("AppId", text: secretBinding(\.dandanAppID))
                    SecureField("弹弹play AppSecret", text: secretBinding(\.dandanAppSecret))
                    Text("填写弹弹play 开发者凭据后可加载弹幕。凭据保存在本机。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("下载") {
                Toggle("下载时保存弹幕文本", isOn: boolBinding(\.saveDanmakuWithDownload))
                Text("在「下载」页选择视频保存目录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var themeBinding: Binding<String> {
        Binding(
            get: { model.settings.themeMode },
            set: { value in model.updateSettings { $0.themeMode = value } })
    }

    private var rateBinding: Binding<Double> {
        Binding(
            get: { model.settings.playbackRate },
            set: { value in model.updateSettings { $0.playbackRate = value } })
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { model.settings.danmakuOpacity },
            set: { value in model.updateSettings { $0.danmakuOpacity = value } })
    }

    private var fontBinding: Binding<Double> {
        Binding(
            get: { model.settings.danmakuFontSize },
            set: { value in model.updateSettings { $0.danmakuFontSize = value } })
    }

    private var durationBinding: Binding<Double> {
        Binding(
            get: { model.settings.danmakuDuration },
            set: { value in model.updateSettings { $0.danmakuDuration = value } })
    }

    private var shieldBinding: Binding<String> {
        Binding(
            get: { model.settings.danmakuShield.joined(separator: ", ") },
            set: { value in
                let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                model.updateSettings { $0.danmakuShield = parts }
            }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in model.updateSettings { $0[keyPath: keyPath] = value } })
    }

    private func intBinding(_ keyPath: WritableKeyPath<AppSettings, Int>) -> Binding<Int> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in model.updateSettings { $0[keyPath: keyPath] = value } })
    }

    private func secretBinding(_ keyPath: WritableKeyPath<AppSettings, String>) -> Binding<String> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in model.updateSettings { $0[keyPath: keyPath] = value } })
    }
}
