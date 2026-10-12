# Kazumi macOS

Kazumi 的原生 macOS 客户端。界面沿用 Flutter 版的信息架构和绿色卡片风格，交互改成 Mac 上的 `NavigationSplitView`、工具栏和 AVKit 播放器。原有 Flutter 工程没有改动。

目标系统是 **macOS 14+**，需要 **Xcode 16+**。播放、弹幕层和窗口都使用 SwiftUI / AppKit / AVKit，因此只能在 Mac 上编译运行。规则解析、Bangumi 数据模型和本地资料库放在 `KazumiCore` 里，可以在 Linux 上用 Swift 工具链做单元测试。

本目录与仓库其余部分一样，采用 **GPL-3.0-or-later**。许可证全文见 [LICENSE](LICENSE)，与仓库根目录的许可证相同。

## 架构

```
macos-native/
├── Package.swift                 KazumiCore 包
├── Sources/KazumiCore/           可在 Linux 编译的核心
├── Tests/KazumiCoreTests/        单元测试
├── KazumiMac.xcodeproj           macOS 应用工程
└── KazumiMac/                    SwiftUI 界面
```

`KazumiCore` 负责这些和界面无关的事：

- 解析 Kazumi 规则 JSON，以及 `kazumi://` 分享链接。字段名与 Flutter 版一致，包括历史拼写 `muliSources`、`baseURL`。当前规则 API 级别是 8，更高的规则会被拒绝。
- 官方规则仓库 `index.json`（与 Flutter 的 `ApiEndpoints.pluginShop` 相同，可选 gitcode 镜像）：跳过坏条目、按段比较版本、拒绝降级和名称不一致的文件。
- XPath 子集：`//`、`/`、`*`、`@attr`、`text()`、`[@attr='值']`、`[contains(@attr,'值')]`、`[n]`。这覆盖规则编辑器承诺的「以 `//` 开头」的选择器，不是完整 XPath。
- API 规则：受限 JSONPath（`$`、`.字段`、`[n]`、`[*]`、引号键）、嵌套分集和 `$$$` / `#` / `$` 分隔的分集字符串、`@keyword` 一类模板。
- 分集 URL 归一化，行为对齐 `lib/utils/episode_url.dart`。
- Bangumi 公开接口：趋势、每日放送、按季度搜索、条目搜索、条目详情。
- 弹弹play 评论解析、番剧匹配，以及与 Flutter 版相同的签名 `base64(sha256(AppId + 时间戳 + 路径 + Secret))`。
- 追番、历史、规则和设置的 JSON 文件。
- 封面磁盘缓存，以及从网页里提取 m3u8 / mp4 等直链。

`KazumiMac` 把这些接成一个窗口：

| 侧栏 | 作用 |
| --- | --- |
| 推荐 | Bangumi 趋势，可按 Flutter 版那组标签筛选 |
| 时间表 | 本季 `/p1/calendar`，其他季度走 Bangumi 搜索并按周一到周日分组 |
| 搜索 | 同时搜 Bangumi 和已启用规则 |
| 追番 / 历史 | 本机记录 |
| 规则 | 仓库安装和更新，导入 JSON、链接、剪贴板或文件，启用、删除 |
| 设置 | 外观、倍速、弹幕、弹弹play 凭据 |

详情页展示封面、评分、标签和简介，并可以用中文名去已启用的规则里找片源。分集页解析线路后进入播放器。播放器盖住整个窗口，用 `AVPlayerView` 播 HLS / MP4，上面叠一层滚动、顶部和底部弹幕。

视觉上对齐 Flutter 版：默认种子色是 Material Green `#4CAF50`，封面比例约 0.65，时间表卡片是大圆角横卡，内容区在浅色模式下是淡绿色。侧栏、工具栏和设置表单用的是系统控件，所以它仍然是 Mac 应用，而不是把 Material 控件搬过来。字体用系统字体（中文是苹方），没有内嵌 Mi Sans。Mi Sans 的版权在小米，不适合再打包一份。

图标沿用仓库里的 `assets/images/logo/logo_rounded.png`。它由 Yuquanaaa 创作，授权范围与上游 README 相同，不是可以随意拿走的素材。

## 在 Xcode 里构建

1. 用 Xcode 16 或更新版本打开 `macos-native/KazumiMac.xcodeproj`。
2. 等它解析本地 Swift 包 `KazumiCore`。包和工程在同一层，工程引用的是 `.`。
3. 签名选你的 Personal Team，或者 Signing 里选 “Sign to Run Locally”。
4. 运行 scheme `KazumiMac`。最低系统是 macOS 14。

应用沙盒打开了出站网络，以及用户选择文件的只读权限（用来导入规则）。`Info.plist` 里允许任意 HTTP 加载，因为有的规则站点仍然是 http。

数据写在：

- `~/Library/Application Support/Kazumi/library.json`：规则、追番、历史、设置
- `~/Library/Caches/Kazumi/images/`：封面缓存

命令键：`⌘1` 推荐，`⌘2` 时间表，`⌘F` 搜索，`⌘3` 追番，`⌘4` 历史，`⌘,` 设置。播放器里空格播放暂停，左右方向键快进快退 5 秒，上下方向键调音量，Esc 关闭。

## 在 Linux 上测试核心

这台开发环境没有 Mac SDK，SwiftUI 工程不能在这里编译。核心库可以：

```bash
cd macos-native
swift test
```

需要 Swift 5.9 或更新的工具链。Linux 上的 `URLSession` 在 `FoundationNetworking` 里，核心库已经按这个做了条件导入。

## 和 Flutter 版的功能对照

| 功能 | Flutter | 这个 macOS 版本 |
| --- | --- | --- |
| 推荐 / 标签 | 有 | 有，走 Bangumi 趋势和搜索 |
| 番剧日历 | 有 | 有，本季放送加历史季度 |
| Bangumi 搜索和详情 | 有 | 有 |
| 规则 JSON / `kazumi://` / 网址 / 剪贴板导入 | 有 | 有。网址会先下载再按 JSON 或 `kazumi://` 解析 |
| 规则商店：浏览、安装、检查更新 | 有 | 有。索引、版本比较和「不降级」与 Flutter 一致；规则页显示版本、作者和更新状态 |
| XPath 搜索和分集 | 有 | 有，常见 `//` 子集 |
| API 规则（嵌套、分隔符、播放页模板） | 有 | 有 |
| 规则编辑器 | 有 | 没有。不能在应用里改选择器 |
| 验证码 / WebView | 有 | 能识别验证页并提示，不能过验证 |
| 内置播放器 | media_kit | AVPlayer，直链和页面里的 m3u8/mp4 |
| 网页嗅探、旧版 iframe 解析 | 有 | 没有。只做简单 URL 提取 |
| 弹幕 | 弹弹play | 有叠加层和按时间错开的轨道；播放器里可调不透明度、字号、滚动时长。凭据仍在设置里 |
| 倍速、续播、下一集 | 有 | 有。推荐页有「继续观看」，播完自动下一集，开头 1 秒和结尾 5 秒不续播 |
| 追番、历史 | 有 | 有，仅本机 JSON。时间表上已追的条目有书签 |
| 外观：深色、种子色 | 有 | 有。内容区用绿色容器色，封面卡和时间表 28pt 圆角卡对齐 Flutter，侧栏仍是系统控件 |
| 动态取色、OLED、窗口按钮 | 有 | 没有 |
| 下载、外部播放器 | 有 | 没有 |
| Anime4K 超分 | 有 | 没有 |
| 一起看、DLNA | 有 | 没有 |
| WebDAV / Bangumi 同步 | 有 | 没有 |
| 评论、角色、Staff | 有 | 没有 |
| GBK 网页 | 有 | 没有，目前按 UTF-8 解码 |

## 已经做完的

- 侧栏导航、推荐、时间表、搜索、详情、追番、历史、规则、设置。
- 封面懒加载，进入列表时预取最多 16 张到磁盘，显示时缩到约 480 像素。内存大约 180 张，磁盘缓存默认 200MB。
- 规则搜索和分集解析不放在主线程上跑网络；列表用 `LazyVGrid` / `LazyHStack`。
- 播放器桌面控制条：进度在上，播放、下一集、时间和倍速在下。鼠标停下约 3 秒后收起。`N` 下一集。
- 弹幕按车道占用时间错开，不再只按序号取模。播放器里可以直接调不透明度、字号和滚动时长。
- 规则页可以刷新官方仓库、按名称或作者筛选、一键安装和全部更新。已安装规则显示版本、作者，以及未检查 / 不在仓库 / 可更新 / 已是最新。
- 核心库单元测试覆盖规则索引解析、版本比较、更新判定、Bangumi、弹幕分车道、续播、下一集、继续观看、封面预取和直链提取。

## 还需要做的

- 在 Mac 上把推荐、时间表、搜索、详情、规则导入、播放和弹幕各点一遍。工程已经能编译并启动，这些交互还没有完整走查。
- WebView 过验证码，以及 Flutter 版那套视频地址嗅探（含 `useLegacyParser`）。
- 非 UTF-8 页面。
- 规则可视化编辑。仓库安装和更新已经有了。
- 下载、投屏、一起看、同步、超分。
- 弹幕避让按时间间隔分车道，还没有按文字宽度做像素级碰撞。
- 这一轮的界面和播放改动还没有在 Mac 上重新编译。

## 这次验证了什么

在一台 Mac 上用 **Xcode 27.0 / Swift 6.4 / macOS 27.2** 执行了 `cd macos-native && swift test`（19 个测试通过），并编译运行了 `KazumiMac`。修正两处编译错误后 **BUILD SUCCEEDED**，应用可以启动：

- 使用 `KazumiCore` 类型的文件需要自己 `import KazumiCore`（Xcode 27 不再让这个导入跨文件可见）。
- `ContentUnavailableView` 的 `description` 参数是 `Text`，不能再传闭包。

同一套核心库在 Linux（Ubuntu 24.04，Swift 6.2）上 `swift test` 为 32 个测试通过，并用 `-swift-version 6` 和 `-strict-concurrency=complete` 编译过。规则仓库这一轮在 Linux 上验证了索引解析和版本比较；规则页的 SwiftUI 还需要在 Xcode 27 上再编一次。卡片、预取、续播和弹幕分车道的界面改动同样还需要在 Mac 上再编一次。

还没有验证：

- 启动之后的页面点击、AVKit 实际播放、弹幕是否跟着进度走。
- 真实 Bangumi / 弹弹play / 规则站点的网络行为。
- Xcode 27 编译应用时剩下的告警。这里没有那份告警列表；核心库本身没有并发告警。`AVPlayer`、`NSImage`、`NSCache` 来自系统框架，如果告警集中在它们的 Sendable 标注上，那不是规则引擎的数据竞争。

打开工程后如果本机包解析失败，确认 `macos-native/Package.swift` 和 `KazumiMac.xcodeproj` 在同一层。
