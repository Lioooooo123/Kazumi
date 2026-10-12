// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import KazumiCore
import SwiftUI

@main
struct KazumiMacApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
                .tint(KazumiTheme.accent(model.settings.accent))
                .preferredColorScheme(KazumiTheme.scheme(model.settings.themeMode))
        }
        .defaultSize(width: 1280, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("前往") {
                Button("推荐") { model.sidebar = .popular }.keyboardShortcut("1", modifiers: .command)
                Button("时间表") { model.sidebar = .timeline }.keyboardShortcut("2", modifiers: .command)
                Button("搜索") { model.sidebar = .search }.keyboardShortcut("f", modifiers: .command)
                Button("追番") { model.sidebar = .favorites }.keyboardShortcut("3", modifiers: .command)
                Button("历史") { model.sidebar = .history }.keyboardShortcut("4", modifiers: .command)
                Button("下载") { model.sidebar = .downloads }.keyboardShortcut("6", modifiers: .command)
                Divider()
                Button("规则") { model.sidebar = .rules }.keyboardShortcut("5", modifiers: .command)
            }
            CommandMenu("播放") {
                Button("播放或暂停") { model.sendPlayer(PlayerCommand.toggle) }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(model.nowPlaying == nil)
                Button("后退 5 秒") { model.sendPlayer(PlayerCommand.back) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(model.nowPlaying == nil)
                Button("前进 5 秒") { model.sendPlayer(PlayerCommand.forward) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(model.nowPlaying == nil)
                Button("下一集") { model.sendPlayer(PlayerCommand.next) }
                    .keyboardShortcut("n", modifiers: [])
                    .disabled(model.nowPlaying == nil)
                Button("全屏") { model.sendPlayer(PlayerCommand.fullscreen) }
                    .keyboardShortcut("f", modifiers: [])
                    .disabled(model.nowPlaying == nil)
            }
        }
        Settings {
            SettingsView().environment(model)
        }
    }
}
