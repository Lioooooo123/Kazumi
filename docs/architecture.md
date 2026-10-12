# 架构

小栗子是 Kazumi 的原生 macOS 端口，许可证为 GPL-3.0-or-later。上游项目在 <https://github.com/Predidit/Kazumi>。

## 两层

`Sources/KazumiCore` 只依赖 Foundation（Linux 上再加 `FoundationNetworking`）。它不引用 SwiftUI、AppKit、AVKit 或 WebKit，所以 `swift test` 可以在 Linux 上跑。

`App/` 是 Xcode 目标 `XiaoLizi`。`XiaoLizi.xcodeproj` 用本地包引用 `.`，把 `KazumiCore` 链进应用。源文件按文件夹同步进目标；`Info.plist` 和 `XiaoLizi.entitlements` 排除在同步编译之外，分别作为 Info.plist 和沙盒授权。

显示名「小栗子」来自 `App/Info.plist` 的 `CFBundleDisplayName` 和 `CFBundleName`。产品文件名是 `XiaoLizi.app`，bundle id 是 `app.xiaolizi.macos`。

## 仍然沿用的上游名称

这些名字属于协议或上游项目，没有改成小栗子：

- Swift 模块 `KazumiCore`，以及 `import KazumiCore`
- 规则分享方案 `kazumi://`
- 官方规则索引 KazumiRules
- WebDAV 路径 `/kazumiSync`
- Bangumi 请求使用的上游 User-Agent

## 数据

`App/AppModel.swift` 里的 `AppPaths` 把资料放在：

- `~/Library/Application Support/XiaoLizi/library.json`
- `~/Library/Caches/XiaoLizi/images/`

下载目录由用户选择，并用 security-scoped bookmark 记在 Application Support 里。

## 播放

播放器是盖住窗口的一层，不是独立路由。换集时用页面 URL 作为视图标识，避免沿用上一个 `AVPlayer`。自动下一集不会在时间观察回调里直接移除观察者。
