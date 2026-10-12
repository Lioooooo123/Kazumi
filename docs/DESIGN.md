# 小栗子界面约定

## 1. 方向
以番剧封面为视觉中心，界面使用安静的 macOS 系统表面。保留绿色强调色，不以整页绿色承载内容。信息架构继续围绕推荐、放送、搜索、追番、历史、下载和规则。

## 2. 颜色
内容背景使用 `NSColor.windowBackgroundColor`；列表与表单使用系统样式；局部表面使用 `NSColor.controlBackgroundColor`。正文使用 primary，说明使用 secondary。绿色或用户选择的种子色只用于主要操作、选中状态与进度。播放器保持黑色背景和独立深色控件。

## 3. 字体
使用 SwiftUI 系统语义字体，中文由系统苹方显示。页面分区为 title2/标题 headline；卡片名称为 headline；正文 body；说明 callout；元数据 caption。时长、评分和进度使用等宽数字，不使用人为字距。

## 4. 组件
封面比例为 0.65，圆角 10 pt，标题位于图片外，保留两行高度。列表行与横向续播卡不沿用海报样式。主要操作使用 borderedProminent；普通操作使用系统按钮。封面按钮有按压反馈、悬停描边和键盘焦点。错误、空、加载三种状态有不同文案。

## 5. 布局
间距采用 4、8、12、16、24、32 pt。内容页边距 24 pt，阅读宽度上限 1100 pt；详情上限 980 pt；规则上限 900 pt。海报网格间距 20 pt，单列最小 144 pt。侧栏使用原生 NavigationSplitView。

## 6. 层级
内容不用装饰性玻璃或大阴影。图片只保留轻微内描边，列表由系统背景和分隔线表达层级。播放器控制层使用 material，以便隔离视频与控件。

## 7. 约束
保留 Bangumi、规则格式、片源解析、同步和播放契约。技术实现说明放在文档，界面只解释操作及必要限制。普通页面不添加营销标题。设置使用 Settings scene 和分类标签；规则使用已安装、仓库、导入三个入口。切换侧栏保留各页导航位置。

## 8. 适配与辅助使用
主窗口最低 900×600 pt，默认 1280×840 pt。网格按可用宽度调整列数；长标题自然换行；表单在独立设置窗口滚动。尊重 Reduce Motion，图片占位不持续闪烁。播放器按钮点击区为 36 pt，适配 Mac 指针；iOS 的 44 pt 触摸规则不直接套到桌面工具栏。

## 9. 后续实现提示
新增海报使用 PosterArtwork 和 ContentButtonStyle，比例 0.65、圆角 10 pt、headline 名称、20 pt 网格间距。新增内容分区使用 SectionHeading，title2 semibold 标题和 callout secondary 说明。新增设置使用 grouped Form，保留系统标签、控件和键盘行为。短暂交互使用 KazumiTheme.pressFeedback，Reduce Motion 时不缩放。
