// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import SwiftUI
import KazumiCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("外观") {
                Picker("深色模式", selection: themeBinding) {
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
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                    Text(item.name).font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Toggle("时间表显示评分", isOn: boolBinding(\.showRating))
            }
            Section("播放") {
                Picker("默认倍速", selection: rateBinding) {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        Text(rate == 1 ? "1.0x" : String(format: "%.2gx", rate)).tag(rate)
                    }
                }
            }
            Section("弹幕") {
                Toggle("显示弹幕", isOn: boolBinding(\.danmakuEnabled))
                Slider(value: opacityBinding, in: 0.3...1.0) { Text("不透明度") }
                Slider(value: fontBinding, in: 12.0...32.0) { Text("字号") }
                Slider(value: durationBinding, in: 4.0...16.0) { Text("滚动时长") }
                TextField("屏蔽词，用逗号分隔", text: shieldBinding)
                TextField("弹弹play AppId", text: secretBinding(\.dandanAppID))
                SecureField("弹弹play AppSecret", text: secretBinding(\.dandanAppSecret))
                Text("弹幕接口需要开发者凭据。签名是 base64(sha256(AppId + 时间戳 + 路径 + Secret))，与 Flutter 版一致。凭据只保存在本机。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("关于") {
                LabeledContent("版本", value: "Kazumi macOS \(KazumiCore.version)")
                LabeledContent("规则 API", value: "\(KazumiCore.ruleAPILevel)")
                Text("本原生端口基于 Kazumi，采用 GPL-3.0。图标来自 Yuquanaaa，使用范围与上游项目说明一致，不是可自由再分发的素材。界面字体使用系统字体，不内嵌 Mi Sans。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("项目主页", destination: URL(string: KazumiCore.projectURL)!)
                Link("Bangumi", destination: URL(string: "https://bangumi.tv/")!)
                Link("弹弹play", destination: URL(string: "https://www.dandanplay.com/")!)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
    }

    private var themeBinding: Binding<String> {
        Binding(get: { model.settings.themeMode }, set: { value in model.updateSettings { $0.themeMode = value } })
    }

    private var rateBinding: Binding<Double> {
        Binding(get: { model.settings.playbackRate }, set: { value in model.updateSettings { $0.playbackRate = value } })
    }

    private var opacityBinding: Binding<Double> {
        Binding(get: { model.settings.danmakuOpacity }, set: { value in model.updateSettings { $0.danmakuOpacity = value } })
    }

    private var fontBinding: Binding<Double> {
        Binding(get: { model.settings.danmakuFontSize }, set: { value in model.updateSettings { $0.danmakuFontSize = value } })
    }

    private var durationBinding: Binding<Double> {
        Binding(get: { model.settings.danmakuDuration }, set: { value in model.updateSettings { $0.danmakuDuration = value } })
    }

    private var shieldBinding: Binding<String> {
        Binding(
            get: { model.settings.danmakuShield.joined(separator: ", ") },
            set: { value in
                let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                model.updateSettings { $0.danmakuShield = parts }
            }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(get: { model.settings[keyPath: keyPath] }, set: { value in model.updateSettings { $0[keyPath: keyPath] = value } })
    }

    private func secretBinding(_ keyPath: WritableKeyPath<AppSettings, String>) -> Binding<String> {
        Binding(get: { model.settings[keyPath: keyPath] }, set: { value in model.updateSettings { $0[keyPath: keyPath] = value } })
    }
}
