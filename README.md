# 小栗子

小栗子是 [Kazumi](https://github.com/Predidit/Kazumi) 的原生 macOS 客户端。界面沿用原项目的信息架构和绿色卡片风格，交互使用 Mac 上的 `NavigationSplitView`、工具栏和 AVKit 播放器。

本仓库现在只包含这个 macOS 应用。Finder、程序坞和菜单栏显示名是 **小栗子**。Xcode 目标、scheme 和产品名是 `XiaoLizi`，bundle id 是 `app.xiaolizi.macos`。规则格式、`kazumi://` 和官方 KazumiRules 仓库仍沿用上游名称。核心库模块名仍是 `KazumiCore`。

目标系统是 **macOS 14+**，需要 **Xcode 16+**。播放、弹幕层和窗口使用 SwiftUI / AppKit / AVKit，需要在 Mac 上编译。规则解析、Bangumi 数据模型和本地资料库放在 `KazumiCore` 里，可以在 Linux 上用 Swift 工具链做单元测试。

本项目采用 **GPL-3.0-or-later**，与 Kazumi 相同。许可证全文见 [LICENSE](LICENSE)。小栗子基于 Kazumi 及其贡献者的作品；版权行和关于页保留这一署名。

## 目录

```
├── App/                      SwiftUI 应用（目标 XiaoLizi）
├── XiaoLizi.xcodeproj        Xcode 工程，scheme 为 XiaoLizi
├── Package.swift             本地 Swift 包
├── Sources/KazumiCore/       可在 Linux 编译的核心
├── Tests/KazumiCoreTests/    单元测试
├── docs/                     架构和贡献说明
├── scripts/                  测试和 macOS 构建脚本
└── .github/workflows/        macOS 上的测试与编译
```

更细的模块划分见 [docs/architecture.md](docs/architecture.md)，界面约定见 [docs/DESIGN.md](docs/DESIGN.md)。

## 架构

`KazumiCore` 负责和界面无关的部分：

- 解析 Kazumi 规则 JSON，以及 `kazumi://` 分享链接。字段名与上游一致，包括历史拼写 `muliSources`、`baseURL`。当前规则 API 级别是 8，更高的规则会被拒绝。
- 官方规则仓库 `index.json`（与上游 `ApiEndpoints.pluginShop` 相同，可选 gitcode 镜像）：跳过坏条目、按段比较版本、拒绝降级和名称不一致的文件。
- XPath 子集：`//`、`/`、`*`、`@attr`、`text()`、`[@attr='值']`、`[contains(@attr,'值')]`、`[n]`。这覆盖规则编辑器承诺的「以 `//` 开头」的选择器。
- API 规则：受限 JSONPath（`$`、`.字段`、`[n]`、`[*]`、引号键）、嵌套分集和 `$$$` / `#` / `$` 分隔的分集字符串、`@keyword` 一类模板。
- 分集 URL 归一化，行为对齐上游 `episode_url`。
- Bangumi 公开接口：趋势、每日放送、按季度搜索、条目搜索、条目详情、角色、Staff、评论。
- 弹弹play 评论解析、番剧匹配，以及与上游相同的签名 `base64(sha256(AppId + 时间戳 + 路径 + Secret))`。
- 追番、历史、规则和设置的 JSON 文件。
- 封面磁盘缓存，以及从网页里提取 m3u8 / mp4 等直链。

`App/` 把这些接成一个窗口：

| 侧栏 | 作用 |
| --- | --- |
| 推荐 | Bangumi 趋势，可按上游那组标签筛选 |
| 时间表 | 本季 `/p1/calendar`，其他季度走 Bangumi 搜索并按周一到周日分组 |
| 搜索 | 同时搜 Bangumi 和已启用规则 |
| 追番 / 历史 | 本机记录 |
| 下载 | 本机视频文件 |
| 规则 | 仓库安装和更新，导入 JSON、链接、剪贴板或文件，启用、删除 |
| 设置入口 | 独立设置窗口：外观、播放、弹幕、下载、同步、代理、一起看 |

详情页展示封面、评分、标签和简介，并可以用中文名去已启用的规则里找片源。分集页解析线路后进入播放器。播放器盖住整个窗口，用 `AVPlayerView` 播 HLS / MP4，上面叠一层滚动、顶部和底部弹幕。

默认强调色沿用上游绿色 `#4CAF50`，用于选择和主要操作。封面比例约 0.65，标题位于图片外；内容区使用 macOS 系统中性色。侧栏、工具栏和设置表单使用系统控件；设置由 `⌘,` 打开独立窗口，按外观、播放、同步、网络和关于分类。字体用系统字体（中文是苹方）。图标放在 `App/Assets.xcassets`，由 Yuquanaaa 创作，授权范围与上游项目说明一致。

封面使用静态占位，悬停和键盘焦点显示描边，点击有短暂按压反馈；有评分时显示分数。推荐、时间表、详情和分集在等待数据时用骨架，失败时可以重试。规则仓库安装时会显示进度。下载进行中时，侧栏「下载」带数量，播放器控制条用毛玻璃并带快进快退。窗口内容最小为 900×600。深色、浅色和 OLED 纯黑都走同一套颜色。

## 构建

1. 用 Xcode 16 或更新版本打开仓库根目录的 `XiaoLizi.xcodeproj`。
2. 等它解析本地 Swift 包 `KazumiCore`。包和工程在同一层，工程引用的是 `.`。
3. 签名选你的 Personal Team，或者 Signing 里选 “Sign to Run Locally”。
4. 运行 scheme `XiaoLizi`。产物是 `XiaoLizi.app`，最低系统是 macOS 14。

命令行（关闭代码签名，适合 CI）：

```bash
scripts/test.sh
scripts/build-macos.sh
```

`scripts/ci.sh` 会先跑测试，再调用 `xcodebuild`。GitHub Actions 在 `macos-latest` 上执行同一脚本。

应用沙盒打开了出站网络，以及用户选择文件的读写和书签权限。`Info.plist` 允许任意 HTTP 加载，因为有的规则站点仍然是 http。菜单栏名称和关于面板来自 `CFBundleName` / `CFBundleDisplayName`（小栗子）。

数据写在：

- `~/Library/Application Support/XiaoLizi/library.json`：规则、追番、历史、设置
- `~/Library/Caches/XiaoLizi/images/`：封面缓存

命令键：`⌘1` 推荐，`⌘2` 时间表，`⌘F` 搜索，`⌘3` 追番，`⌘4` 历史，`⌘6` 下载，`⌘5` 规则，`⌘,` 设置。播放器里空格播放暂停，左右方向键快进快退 5 秒，`N` 下一集，`F` 全屏，Esc 关闭。没有打开播放器时，这些键不会抢走文本框里的空格。

## 功能

| 功能 | 小栗子 |
| --- | --- |
| 推荐 / 标签 | 有，走 Bangumi 趋势和搜索 |
| 番剧日历 | 有，本季放送加历史季度 |
| Bangumi 搜索和详情 | 有 |
| 规则 JSON / `kazumi://` / 网址 / 剪贴板导入 | 有。网址会先下载再按 JSON 或 `kazumi://` 解析 |
| 规则商店：浏览、安装、检查更新 | 有。索引、版本比较和「不降级」与上游一致；规则页显示版本、作者和更新状态 |
| XPath 搜索和分集 | 有，常见 `//` 子集 |
| API 规则（嵌套、分隔符、播放页模板） | 有 |
| 规则编辑器 | 有基础表单：名称、版本、作者、网址、搜索和分集选择器。完整 API 模板仍用 JSON |
| 验证码 / WebView | 有。验证页用 WKWebView 打开，完成后把 Cookie 带到下一次搜索。自动点按钮和自定义脚本没有移植 |
| 内置播放器 | AVPlayer，直链和页面里的 m3u8/mp4 |
| 网页嗅探 | 有。页面里找不到直链时用 WKWebView 收集 video / iframe / 资源地址，并丢掉广告域名。强混淆脚本仍可能拿不到地址 |
| 弹幕 | 有。按标题匹配作品、按集数匹配分集；滚动弹幕按文字宽度避让。凭据在设置里 |
| 倍速、续播、下一集 | 有。推荐页有「继续观看」，播完自动下一集，开头 1 秒和结尾 5 秒不续播 |
| 追番、历史 | 有，本机 JSON。历史可搜索、只看未看完、删除；追番可搜索和取消 |
| 外观 | 深色、种子色、OLED 纯黑背景。动态取色没有做，使用固定种子色 |
| 下载、外部播放器 | 有。mp4 直接保存，m3u8 分片拼成一个文件；可交给 IINA、VLC 或浏览器。没有多集队列调度 |
| 超分辨率 | 播放时可用 Core Image 锐化，分效率和质量两档。完整 Anime4K 需要单独的 Metal 渲染器，这里没有移植 |
| 一起看、DLNA | 有基础能力。一起看走 Syncplay 的 Hello / State JSON，默认 `syncplay.pl:8996`。DLNA 发 SSDP 搜索并用 SOAP 设置地址后播放。房间事件和设备兼容性都不完整 |
| WebDAV / Bangumi 同步 | WebDAV 同步历史、追番和弹幕屏蔽词。屏蔽词文档与上游 version 1 格式相同。历史写在 `/kazumiSync/history/macos-library.json`。Bangumi 收藏可在填写令牌后标为在看 |
| 评论、角色、Staff | 有 |
| 以图搜番 | 有。把图片网址交给 trace.moe，不上传本地文件 |
| GBK 网页 | 有。Content-Type 或 HTML meta 声明 GBK / GB18030 / Big5 时用 iconv 解码 |

## 验证

在一台 Mac 上用 **Xcode 27.0 / Swift 6.4 / macOS 27.2** 编译运行过早期外壳（当时目标名还是 `KazumiMac`）。修正两处编译错误后可以启动：使用 `KazumiCore` 类型的文件需要自己 `import KazumiCore`；`ContentUnavailableView` 的 `description` 必须是 `Text`。

在 **Xcode 27 / macOS 27.2** 上，当前这棵树 `BUILD SUCCEEDED`，`swift test` 37 个测试通过，`XiaoLizi.app` 可以启动。编译前修了三处：`@Observable` 的 `init` 不能在全部存储属性就绪前改 `settings`；DLNA 的 `describe` 不能和错误描述函数同名；macOS 上 `KazumiCore` 需要链接 `libiconv`。GitHub Actions 的 macOS 作业执行 `scripts/ci.sh`，会编应用并跑这组测试。

核心库在 Linux（Ubuntu 24.04，Swift 6.2）上同样是 37 个测试通过，并用 `-swift-version 6` 和 `-strict-concurrency=complete` 编译通过。

还没有在本机点过：启动之后的页面、AVKit 实际播放、弹幕是否跟着进度走，以及真实 Bangumi / 弹弹play / 规则站点。
