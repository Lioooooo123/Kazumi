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

播放器是盖住窗口的一层，不是独立路由。播放器身份由分集页面 URL、规则和线路组成；同一分集网页可以服务多条播放线路，换线也必须重新解析和创建播放条目。自动下一集由媒体实际结束事件触发，不使用距结尾的时间阈值。

播放层按主内容区的可用尺寸布局，播放期间隐藏窗口工具栏并禁用下层导航。`PlaybackController` 对 libmpv 的加载、缓冲、失败和结束事件统一管理；未包含媒体框架时使用 AVKit 回退，并单独观察 `AVPlayerItem.status`。条目未就绪时设加载超时。失败先尝试剩余候选地址和网页嗅探，再显示重试与返回分集入口。关闭或换集时取消网页解析、超时及媒体观察，过期回调不能修改当前播放。

媒体地址按 URL 自身的路径及响应类型识别，网页查询参数里的媒体地址不会把网页变成直链；脚本、样式和 HLS 分片不作为播放候选。按上游 Apple WebView 逻辑截获 `Response.text()` 和 XHR 中以 `#EXTM3U` 开头的响应，支持无扩展名、无 HLS MIME 的播放列表。网页嗅探结果保留媒体请求所需的 Referer 和匹配 Cookie。规则显式 Referer 优先，其余请求使用实际播放页或嗅探帧地址。

稀饭 Next 由 `XifanPlaybackService` 从页面数据读取当前番剧和集数，播放线路使用分集 API 返回的所选 source id，缺少 id 时才使用网页默认线路。用规则已有的匿名请求配置取得签名媒体地址，再交给原生播放器。返回地址必须匹配当前集数和线路。

历史记录保存片源页面 URL、规则、条目来源、所选线路及完整分集。续播重新读取线路，保留同一线路和分集，然后重新解析媒体；旧历史无这些字段时仍能解码并播放。签名直链和验证 Cookie 不写入播放上下文。弹幕独立加载，不阻塞视频。规则搜索逐项显示返回结果，慢片源不阻塞已有结果。

XPath 的位置谓词按各父节点下匹配兄弟元素计算，例如 `//div[4]`；结果保持文档顺序。这个语义与上游位置选择器规则一致。

源码基线为上游 Kazumi `dc18be2af7636ae852cb49d0c4460e49b04b467c`；对应参考包括 `video_webview_apple_impl.dart`、`player_playback_controller.dart`、`history_playback_service.dart` 和 `xpath_rule_strategy.dart`。界面继续使用 SwiftUI 与 AppKit，默认播放内核使用与上游一致的 libmpv；未包含媒体框架的开发构建可使用 AVKit 回退。`MPVBridge` 动态加载应用内的运行时，不使核心库测试依赖本机安装的 libmpv。打包脚本仅带入媒体框架，不包含 Flutter；框架缺失时打包失败。OpenGL 渲染上下文由视频视图持有，先释放上下文再销毁 mpv handle。

## 界面

颜色、间距和短暂交互集中在 `App/Theme.swift`，封面与内容按钮集中在 `App/Components.swift`。封面图片在固定区域内裁切，不参与网格单元的固有尺寸计算。

应用使用 `Settings` scene 提供独立设置窗口；表单按外观、播放、同步、网络和关于分类。主窗口按侧栏项保存 `NavigationPath`，切换浏览入口后可以回到先前的详情或分集。界面约定见 [DESIGN.md](DESIGN.md)。
