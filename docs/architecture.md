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

播放层按主内容区的可用尺寸布局，播放期间禁用下层导航。`PlaybackController` 单独观察 `AVPlayerItem.status`，因为失败的条目可能不触发时间回调；失败时暂停播放并显示重试与返回分集入口。关闭播放器时释放时间和状态观察者。

媒体地址按 URL 自身的路径及响应类型识别，网页查询参数里的媒体地址不会把网页变成直链；脚本、样式和 HLS 分片不作为播放候选。网页嗅探结果保留媒体请求所需的 Referer 和匹配 Cookie。

稀饭 Next 由 `XifanPlaybackService` 从页面数据读取当前番剧、集数和线路，用规则已有的匿名请求配置取得签名媒体地址，再交给原生播放器。返回地址必须匹配当前集数和线路。历史记录保存片源页面 URL，续播和重试重新解析，不持久化会过期的签名直链。

## 界面

颜色、间距和短暂交互集中在 `App/Theme.swift`，封面与内容按钮集中在 `App/Components.swift`。封面图片在固定区域内裁切，不参与网格单元的固有尺寸计算。

应用使用 `Settings` scene 提供独立设置窗口；表单按外观、播放、同步、网络和关于分类。主窗口按侧栏项保存 `NavigationPath`，切换浏览入口后可以回到先前的详情或分集。界面约定见 [DESIGN.md](DESIGN.md)。
