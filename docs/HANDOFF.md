# 接手说明

更新日期：2026-10-23（Asia/Shanghai）。当前任务：**UI1 Apple Music 参考图与 Now Playing**。实现、Debug 构建和 36 项定向测试通过，布局预览与隔离宿主尺寸已检查；桌面交互、逐像素对照与真实沙盒授权仍待验。

### UI1 Apple Music 参考图与 Now Playing（2026-10-23，最新）

- 用户先给出界面需求，再补充 Apple Music 实际截图；播放条以最新图为准：左控制、中封面/单行曲名/下沿进度，右更多/歌词/队列/音量。封面/曲名现打开 Now Playing，独立歌词按钮保留 L1 本地读取能力。未加入截图中的在线主页、广播、账号或播放列表编辑；保留所有已有工作区修改，不委派、提交、推送或升级依赖。
- 侧边栏新增最近添加、最近播放与最常播放，并以可折叠的资料库/播放列表/智能列表分组呈现；原生 hover/选择与系统强调色。工具栏支持返回/前进（⌘[ / ⌘]）、歌曲列表/专辑网格切换。LibraryViewModel 保存最多 100 个位置与视图模式，分支导航清除前进栈，保留搜索/排序。
- 独立 v4_listeningActivity 迁移仅新增路径、添加/最近播放时间、次数表，不改扫描索引或音频。LibraryStore actor 与 ListeningActivityController 串行更新；PlaybackController 按一次成功开始播放计数，暂停/恢复/定位不重计，失败不计，交叉渐变仅记录真正开始的新曲。旧库最近添加以首次记录时间为准，无法还原历史添加时间。只在当前库快照中筛选/排名，记录不自动清理。
- 新增独立 NowPlayingView：居中大封面/阴影、模糊封面与语义渐变、歌曲/艺术家/专辑、时间进度、原生玻璃按钮、音量/模式/歌词及关闭/Escape。共享播放器、封面缓存和进度状态机，没有新计时器；高对比/减少透明度关闭装饰背景，动效 .snappy 尊重减少动态效果。预览专用播放器只注入显示状态，不加载音频或注册媒体。
- 主窗口默认 1100×700、最小 640×520；保留 NavigationSplitView + HStack 队列及 900 点 popover 阈值。顶部拖动带改用根 safeAreaInset，修复先前宽窗标题/表头被遮挡；歌曲 Table 使用系统矩形交替背景与更紧凑行高。隔离 NSHostingController 读数确认实际标题为“歌曲”，1100/640 点内容宽度和对应全宽 24 点拖动区。未据此宣称物理三指已通过。
- Debug 构建退出码 0，最终日志 `/tmp/liquidmusic-interface-debug-verified-20261023.log`；只有既有 AppIntents 元数据提示。36 项定向测试退出码 0、0 失败，日志 `/tmp/liquidmusic-interface-tests-20261023.log`，结果包 `Test-Liquidmusic-2026.10.23_15-37-41-+0800.xcresult`。其中新增 8 项覆盖排名/过滤/网格顺序、旧库迁移/记录重开/索引不变、连续事件、导航分支/迟到查询、静音 AVPlayer 暂停/定位/失败和交叉渐变计数；其余为查询、存储、进度和歌词回归。首轮构建发现混用 ToolbarContent 的编译错误，包装 ToolbarItem 后已修复。
- 宽浅/窄深非空播放条、歌曲表头、最近添加网格布局、Now Playing 浅/深紧凑预览均已检查；独立 AlbumsView 预览可显示模拟封面与缺图回退，完整 ContentView 网格预览仍显示占位，集成图片展示待实际窗口确认。预览路径：`/Users/gede/.codex/visualizations/2026/10/23/01a167a9-c679-7090-92fc-18814fd372c0/interface-20261023/`。预览遵循系统强调色，不把截图的 Apple Music 品牌红硬编码为 UI 颜色；尚未完成逐像素比对。
- 沿用前轮用户跳过桌面回归的决定，未启动 UI runner 或系统身份验证。现有导入流程 UI 用例已补 Now Playing 打开/Escape 关闭断言，未执行；鼠标/键盘、双层歌词 sheet 的 Escape 返回、宽窄队列切换、完整 VoiceOver、听音与真实签名沙盒仍需人工验收。未重跑全量、Release、CPU，不把以前结果当成本轮复测。
- 下一项：用临时音频验证浏览前进/后退、列表/网格、智能列表跨启动、Now Playing/歌词/Escape，并结合参考图复核实际窗口；继续补 S1/M7 待验，不自动扩展新功能。

### L1 本地歌词与播放条入口（2026-10-23，较早记录；入口已由 UI1 调整）

- 用户明确新增歌词，并确认仅使用本地 LRC／内嵌歌词。已更新 AGENTS/ROADMAP 的旧边界；保留其余已有改动，不委派、不提交/推送、无依赖升级。
- 点击播放条封面/曲名打开原生 600×460 歌词 sheet；包含曲名/艺术家、播放控制/进度、关闭/Escape、重新读取/选择歌词，页内封面仍能打开大封面。自动尝试音频同名 `.lrc` / `.LRC`，再读取 AVFoundation 内嵌歌词；缺失/失败有可操作状态。手动歌词只用于本次查看，可切回“自动查找”，不持久化关联或改写音频。
- LyricsReader 独立 actor、有上限读取与配对 security scope；LyricsModel 可注入依赖，以代次/取消防止切歌或关闭后的旧结果覆盖。支持 UTF-8 / 带 BOM 的 UTF-16、多时间标签、小数秒、offset、同时间译文合并、间奏空行、纯文本。输入/展开文本 1 MiB 与 10,000 行/标签限制，防止重复时间标签放大内存。未枚举真实音乐目录、修改数据库或扫描流程。
- 同步高亮复用既有播放进度，二分查找当前句，只有换句才滚动；手动滚动停用跟随，可勾选恢复；点击时间行沿原 seek 路径并校验歌曲，超过时长的行不能定位。关闭界面不保留歌词任务/文档，无新增计时器。
- 最终 README Debug 构建退出码 0，日志 `/tmp/liquidmusic-lyrics-build-verified.log`，仅既有 AppIntents 元数据提示。10 项定向测试（6 LyricsTests + 4 PlaybackScrubTests）全部通过、退出码 0，日志 `/tmp/liquidmusic-lyrics-tests-final.log`；结果包 `Test-Liquidmusic-2026.10.23_14-56-30-+0800.xcresult`。包括临时 M4A 实际内嵌歌词读取、损坏同名歌词回退、UTF-16、大小限制、边界/倒退定位和迟到结果保护。首轮构建因复杂元组表达式类型检查超时，拆分后通过，未遗留编译错误。
- 同步歌词浅色、空状态深色 Preview 已目视检查，无内容截断；图片位于本轮 visualizations 的 `lyrics/`。Preview 只注入内存示例，不读真实音乐或自动播放。UI 测试入口从旧大封面改为歌词页，但沿用本会话跳过桌面回归的决定，未执行 runner、未触发系统身份验证，不将 Preview 当作点击/手势验收。
- 未重跑全量/Release/CPU 或真实签名沙盒；实际歌词入口、点击定位、手动滚动恢复、单文件邻接 LRC 授权及完整 VoiceOver 仍待人工验收。原 S1/M7、顶部三指拖动与宽窗视觉待验继续保留。
- 下一项：使用临时音频与同名 LRC 完成桌面交互验收，再补真实授权/听音及原待验；不自动扩展在线歌词。


### 性能与顶部拖动区（2026-10-23，最新）

- 用户本轮要求降低 CPU/内存并扩大顶部三指拖动区域。保留已有工作区修改；未提交、推送、升级依赖或扫描真实音乐目录。
- 新增 ArtworkThumbnailCache actor：ImageIO 后台按显示点数 × 屏幕倍率解码（最长边上限 512），以内容哈希和尺寸共享 CGImage；解码缓存成本目标 16 MiB/160 项，压缩数据缓存从 32 MiB 降到 8 MiB。NSCache 的成本限制为自动淘汰目标，并非进程内存硬上限。保留候选回退、切换代次与取消保护；图片消失时释放视图引用。未改变磁盘缓存或清理用户文件。
- 查询分组改为累计首项/计数，避免每次搜索为专辑和艺术家创建完整歌曲分组数组；顺序、代表曲目和完整专辑封面候选保持原语义。
- ContentView 顶部加入全宽 24 点独立 WindowDragArea，使用 NSWindow.performDrag，支持系统转换后的拖移事件，不注册全局事件或改变系统三指设置。实际 NSHostingController 测试确认 1100×24 布局及可移动属性；物理三指、工具栏相邻边界和全屏交互仍待人工验证。
- 最终 README Debug 构建退出码 0：`/tmp/liquidmusic-perf-build-verified-20261023.log`，只有既有 AppIntents 元数据提示。31 项相关测试通过，退出码 0：`/tmp/liquidmusic-perf-tests-final-20261023.log`，包括 9 项图片加载/缓存、9 项专辑封面、12 项查询及 1 项可见窗口采样。结果包 `Test-Liquidmusic-2026.10.23_13-54-28-+0800.xcresult`。测试仍有既有 weak 变量和 NSTableView 重入诊断，未将它们标为本轮修复。
- 同一 512 像素 JPEG 连续 100 次请求，旧 NSImage 获取 CGImage 路径约 5.90ms，新 64 像素共享缓存约 2.31ms（包含首次解码）。理论像素存储按 bytesPerRow × height 求和分别为 58,982,400 与共享后的 9,216 字节；不是物理内存/RSS 测量，也不能泛化为整个 App 的降幅。
- 千首无封面模拟库、可见 1100×680 窗口、临时静音 WAV，ABBA 四段各 4 秒：改动前开启渐变 11.22%/10.35%，关闭 10.07%/11.45%；最终开启 9.81%/10.41%，关闭 9.07%/10.72%。短时波动内基本持平，不宣称播放 CPU 显著降低；主要改善有封面的加载路径。无真实资料库整体内存测量。
- 窄窗 Preview 已目视检查，控件未截断；宽窗 Preview 有标题表头遮挡/后续快照不完整，未计为宽窗视觉验收。真实宿主窗口布局测试通过。沿用已有跳过桌面自动化的决定，未触发系统验证；未重跑 Release、听音、全量或物理手势。
- 下一项：真实触控板确认新增顶部带的三指拖动与相邻控件，补宽窗视觉验收、带封面资料库滚动的 RSS/CPU 采样，以及原 S1/M7 人工待验。


### 原生玻璃与侧边栏精简（2026-10-23，最新）

- 按用户最新要求，播放条直接使用系统 glassEffect(.regular, in: .capsule)，撤去额外的 0.88 不透明底色；减少透明度/增加对比度仍有语义不透明回退。保留单行悬浮结构和曲名截尾。
- SlimPlaybackSlider 改为纯 SwiftUI Slider，mini 尺寸，由系统呈现轨道/玻璃旋钮，替换先前自绘 NSSliderCell。保留原拖动状态、切歌隔离、辅助功能值/提示、显式焦点及左右 5 秒跳转；进度区为 18 点，不引入新计时器。
- 移除 SidebarView 底部“打开音频文件…”按钮及无用闭包参数，只保留资料库统计；工具栏、Command-O 与空库操作继续可用。
- README Debug 构建退出码 0（`/tmp/liquidmusic-native-glass-build-20261023.log`），仅既有 AppIntents 元数据提示；4 项 PlaybackScrubTests 通过、退出码 0（`/tmp/liquidmusic-native-glass-scrub-tests-20261023.log`）。宽浅/窄深 Preview 已目视检查，按钮移除、原生 Slider 与布局均符合预期；截图在本轮 visualizations 的 `native-glass-player/`。
- 按用户上一条决定跳过桌面回归，不触发系统自动化授权；未重跑全量/Release/CPU/听音，不把预览当作交互验收。保留既有工作区与用户 scheme 管理文件，无提交/推送。下一项仍为原 S1/M7 人工待验，后续桌面进度应按当前 SwiftUI Slider 复测。

### 细播放条与更实背景（2026-10-22 至 23，较早记录）

- 用户提供 Apple Music 窄播放条截图/GIF，要求进一步压薄并降低透明度。移除常驻副标题和时间标签，封面缩至 32 点，曲名单行截尾，模式改为省略号图标，左右控件保持单行；背景为 0.88 不透明度的语义底色 + 单层系统玻璃，辅助功能回退仍为不透明。
- 新增 SlimPlaybackSlider，用 NSSlider/NSSliderCell 绘制 3 点细轨道；聚焦/拖动时显示旋钮。沿用 PlaybackScrubState 的拖动提交与旧条目保护，左右键仍为 5 秒，时间进入 AXValueDescription 和悬停提示。未改播放时钟、音频、库或计时器。
- 宽浅/窄深 Preview 已目视检查，单行控件无截断；截图位于本轮 visualizations 的 `slim-player/`。修正 Coordinator 的 MainActor 隔离警告。2026-10-22 首批窄窗音量/队列通过，进度用例失败。2026-10-23 回看录屏确认 XCTest 的原生 slider.click() 点击了当前旋钮，未点击轨道中点；已改为 normalizedOffset(0.5, 0.5) 的坐标点击，并兼容数值 AXValue，移除临时诊断输出和无必要的手动定位代码。
- 2026-10-23 最终 README Debug 构建退出码 0，日志 `/tmp/liquidmusic-slim-build-final-20261023.log`；4 项 PlaybackScrubTests 全部通过，退出码 0，日志 `/tmp/liquidmusic-slim-scrub-tests-20261023.log`。复用原有固定 GRDB 源缓存，未升级依赖。
- 本次桌面续验日志 `/tmp/liquidmusic-slim-ui-verified-20261023.log`，退出码 65，结果包 `Test-LiquidmusicUITests-2026.10.23_13-03-19-+0800.xcresult`。用例未开始，截图明确显示 XCTest“Enable UI Automation”触控 ID/密码系统验证弹窗；不是应用断言失败。用户随后明确“本轮跳过桌面回归”，不再重试或等待系统验证；不能把测试修正当作进度交互已通过。
- 本轮不重跑全量、Release 或 CPU 采样，不将前轮性能数字当作本轮复测。保留工作区，无提交/推送。下一项仍为非空播放条手势/VoiceOver 与原 S1/M7 人工待验。

### 播放刷新与悬浮布局（2026-10-22，最新）

- 用户报告 CPU 占用高并要求 Apple Music 式悬浮播放条。本轮只处理该范围，保留已有工作区修改，无提交/推送、依赖升级或真实音乐目录扫描。
- S1 的 50ms 观察间隔原本也用于关闭渐变的普通播放；现在关闭渐变为 250ms，开启仍为 50ms，开关时配对重建观察者。两种模式的 UI 进度/定期媒体检查均限制为约 4Hz，曲尾检测直接读音频时钟。seek 立即反馈，20ms 音量渐变任务不变。声波改为 200ms periodic + 固定尺寸 Canvas，暂停/减少动态效果时不创建时间线。
- 播放条移入 detail 底部 safeAreaInset，透明外边距、圆角系统玻璃，侧边栏延伸到底。宽布局左控制/中封面进度/右模式队列音量；窄布局三行，保留原生 Slider、键盘定位、音量 Escape 和辅助功能背景回退。
- 默认 Debug 命令遇 GRDB 子模块网络检出停滞，已中止并复用原有固定 7.11.1 缓存。最终 32 项播放/渐变/媒体/模式/性能测试通过，退出码 0（`/tmp/liquidmusic-floating-final-tests.log`，约 70.81 秒）。新增真实时钟刷新频率切换及暂停 seek 回归，未重跑全量。
- Debug 隔离采样使用 1100×680 可见窗口、1000 个不同路径模拟索引、90 秒临时静音 WAV、替代媒体传输层、getrusage 进程 CPU，ABBA 顺序每段 4 秒。最终开启渐变为 19.07%/18.81%，关闭为 18.34%/18.71%，暂停 0.68%；此前尚未解耦 UI、未改 Canvas 的相同条件样本开启约 45–49%、关闭约 22%。这不是完整原版或 Apple Music 对照，不可泛化成所有设备的降幅。初次误用相同路径的千行样本已弃用，保留日志便于审计。
- Release 同条件采样通过，退出码 0（`/tmp/liquidmusic-floating-cpu-release-testable.log`）：开启 18.69%/18.40%，关闭 18.01%/19.46%，暂停 0.65%。命令额外传 `ENABLE_TESTABILITY=YES` 支持现有 `@testable`，只运行这一项、arm64，不等于发布签名或双架构验收。首次未带此参数的 Release 测试因模块未启用测试而退出 65，未记为通过。最终 Debug 构建日志 `/tmp/liquidmusic-floating-build-verified.log`；测试仍有既有 weak 变量提示和 AppIntents 元数据提示。
- `bash Scripts/verify-ui.sh` 定向音量/队列窄窗与宽窄切换两项通过，退出码 0（`/tmp/liquidmusic-floating-ui.log`，结果包 `Test-LiquidmusicUITests-2026.10.22_21-01-59-+0800.xcresult`）。本次自动化初始化成功，但未重跑设置分页，不能销掉旧 S1 待验项。
- 两张预览已目视检查：`/Users/gede/.codex/visualizations/2026/10/22/01a163af-2e7a-7bc2-b5c4-13b8df344ce0/floating-player/`。下一项：同一音频、相同窗口/库规模下测量 Release 与 Apple Music 的实际 CPU；补非空播放条听音、辅助功能及原 S1/M7 人工验收。未宣称 CPU 已达到 Apple Music 水平。

## 用户最新意图

最新追加：按 Apple Music 实际截图完善三栏浏览、单行玻璃播放条、独立歌词入口与 Now Playing，补最近添加/最近播放/最常播放和浏览历史。UI1 已实现并完成构建/定向测试/布局检查，实际点击与逐像素对照待验；本地歌词不做在线自动匹配，前轮 S1/M7 的真实听音/系统交互待验保留。

2026-10-20 用户提供 Apple Music 设置截图，要求同类设置面板，只通过苹果原生应用菜单进入，并加入可开关、可调时长的交叉渐入渐出。2026-10-21 用户要求继续按 Apple Music 迭代；2026-10-22 明确继续完善、可适当减少自动化测试。本轮完善 S1 日常使用细节，只运行相关设置测试，不因 UI 自动化环境问题停在重复验证。AW1–AW3 已实现，M7 人工待验项保留。

### S1 设置交互完善（2026-10-22，当前）

- SettingsController 记住本次运行最后选择的分页，重开设置回到该页；新增 ⌘1–⌘4 分页快捷键和悬停提示，首次仍打开播放页。不新增主窗口入口，不将导航状态写入 SQLite。
- 外观草稿立即预览设置窗口，保存后才应用主窗口/菜单栏；取消仍放弃草稿。通用、播放、高级页提供“恢复本页默认值”，只改当前页的草稿，其他页保留，文件夹页不提供重置。
- 底部明确未保存状态和保存进度；无修改直接点“好”关闭，不重复写库。读取失败显示明确错误及重试按钮，不再一直显示读取转圈；重试时清理旧错误，重开设置清理旧保存错误。启动音量增加百分比辅助功能值。
- 本轮未改音频、队列、扫描或持久化格式。README Debug 构建退出码 0，最终日志 `/tmp/liquidmusic-settings-polish-build-final.log`，无 Swift 编译警告，只有既有 AppIntents 元数据跳过提示；5 项 SettingsTests 通过，退出码 0，日志 `/tmp/liquidmusic-settings-polish-tests.log`，结果包 `Test-Liquidmusic-2026.10.22_20-40-50-+0800.xcresult`。修正了分页快捷键提示的 Character 本地化插值警告。
- 播放浅色、通用深色 Preview 渲染并目视检查，620×440 内容含底部恢复按钮，无内容截断。图片保存在 `/Users/gede/.codex/visualizations/2026/10/20/01a159dd-db67-7f92-bac2-8bb9ffb43349/liquidmusic-settings-polish-20261022/`。预览使用内存偏好、不注册媒体、不打开库或自动播放。
- 按用户要求未新增镜像 UI 测试，未重跑全量 135 项、Release 或已知初始化超时的 UI runner；真实快捷键、重开分页、取消外观预览及保存/恢复默认的桌面交互仍待验，不能将 Preview 当作通过。原听音/签名沙盒/硬件媒体待验项有效；保留工作区，无提交/推送。

### S1 时长、格式与媒体续验（2026-10-22，较早记录）

- 本轮新增 8 项检查：1/6/12 秒渐变由真实 AVPlayer 音频时钟自然完成，校验中点增益、互补总音量、队列仅推进一次与旧播放器释放；WAV/M4A 双向解码切换、短 MP3；损坏 M4A/FLAC 准备失败；重叠时注入媒体暂停/恢复/定位及新条目元数据同步。CrossfadeTests 现为 11 项，CrossfadeFormatTests 4 项，复用记录型媒体传输层，未注册真实媒体键。
- 本机 tone.flac 可通过元数据预检，但实际解码报帧数范围错误。测试先独立播放探测，再验证交叉准备失败不提前打断旧曲、自然换曲后停在失败条目且不跳过后续条目；不把元数据可读当作 FLAC 播放通过。其他格式切换及 1/6/12 秒时序通过。所有素材为临时合成音频或 bundle 测试副本，全部静音，无新增依赖。
- 完整 135 项逻辑/集成通过，0 失败、0 跳过，退出码 0，约 56.12 秒；日志 `/tmp/liquidmusic-s1-tests-verified-20261022.log`，结果包 `/tmp/Liquidmusic-build/Logs/Test/Test-Liquidmusic-2026.10.22_20-29-59-+0800.xcresult`。初次测试把 FLAC 预检通过误当作可播放，失败后改为独立播放探测并验证失败路径；未隐藏失败或放宽播放器行为。
- 最终 README Debug 与 Release 构建退出码均为 0，日志 `/tmp/liquidmusic-s1-debug-final-20261022.log` / `/tmp/liquidmusic-s1-release-20261022.log`；`lipo -archs` 确认 Release 为 x86_64 + arm64。Release 仅有既有 AppIntents 元数据跳过提示，无编译错误。脚本语法及 `git diff --check` 通过；测试隔离变量和共享 scheme 未改。
- `Scripts/verify-ui.sh` 定向设置用例：Debug App 和 runner 构建通过，runner 在启用自动化模式时超时（64.23 秒），退出码 65，**用例未开始**。日志 `/tmp/liquidmusic-s1-ui-settings-20261022.log`，结果包 `Test-LiquidmusicUITests-2026.10.22_20-05-04-+0800.xcresult`。本轮截屏已成功，不能继续归因为无显示；`DevToolsSecurity -status` 同时报告开发者模式未启用，尚未确认与超时的因果关系，未更改系统安全设置。
- 不修改产品功能或扩展新里程碑；可听音频、真实菜单栏开关/外观、签名沙盒及最终分页点击仍待验。保留原有工作区与素材，不提交/推送。

### S1 实现与验证（2026-10-21 历史）

- SwiftUI Settings 场景提供应用菜单“设置…”和 ⌘,；主窗口不增加按钮。顶部通用/播放/文件/高级四页、系统图标/字体/语义颜色，原生勾选框与 1–12 秒滑块，取消/好操作。分页补全矩形点击区域，滑块隐藏重复视觉标签并保留辅助功能名称。
- 通用：跟随系统/浅色/深色，菜单栏迷你播放器开关；播放：交叉渐变与默认播放模式；文件：原 LibraryFoldersView，所有扫描/授权和审阅沿用原流程；高级：下次启动音量。文件夹操作即时生效，界面明确说明。截图中的视频、流媒体、声音增强和音量标准化未实现，不放空控件。
- AppPreferences 为 Codable/Sendable 值类型；SettingsController 由 AppModel 持有，共用 LibraryStore actor，v3_appSettings 只新增独立设置表。成功写入后才应用；取消/关窗放弃草稿，读写失败可见且读取失败禁止保存。普通保存不重置播放条临时音量/模式，除非确实修改默认模式；启动恢复不自动播放。隔离宿主/Preview 只用内存，不碰真实偏好或库。
- PlaybackController 准备队列副本和静音第二路 AVPlayer，readyToPlay 后进入重叠区才提交。线性互补增益乘主音量，按新曲音频时间渐变；默认关闭/6 秒，短曲最多重叠各自时长一半。自动顺序/列表循环/随机均支持，单曲循环与手动切歌不交叉。暂停两路并停止定时任务；恢复继续。定位/切歌/禁用/失败/终止释放旧音频和授权；插队/模式变化丢弃预备项。旧播放器通知按身份/代次失效。
- 新增 7 项 CrossfadeTests、5 项 SettingsTests，并扩展旧 v1 数据库迁移测试。真实 AVPlayer 全部静音，覆盖两路增益、暂停/恢复、全局音量、完成/定位/禁用/快速切歌/释放、插队和重复条目、循环/随机、缺失文件不提前打断。设置覆盖重开、草稿、读失败、归一化及旧索引保留。
- 2026-10-21 环境恢复后 `/tmp` 旧日志/构建消失，重新执行 README Debug 构建：退出码 0，日志 `/tmp/liquidmusic-settings-build.log`；完整 127 项测试 0 失败、退出码 0、约 23.19 秒，日志 `/tmp/liquidmusic-settings-tests.log`。复用既有 GRDB 7.11.1 SourcePackages 缓存，不升级依赖。主 scheme 隔离变量保持。
- 2026-10-20 曾通过 125 项测试；随后补暂停定时任务、释放/循环/随机测试和分页点击修正。历史 UI 中开关 AXValue 为 NSNumber，已修正测试；保存/取消/12 秒恢复通过，但分页点击未过且有其他窗口遮挡。未将旧未完成批次记为全绿。2026-10-21 运行 `bash Scripts/verify-ui.sh`，App/runner 构建成功，但 runner 在执行用例之前因 `Timed out while enabling automation mode` 初始化失败，退出码 65；系统截屏也返回 `could not create image from display`。日志 `/tmp/liquidmusic-settings-ui-all.log`，结果包 `/tmp/Liquidmusic-build/Logs/Test/Test-LiquidmusicUITests-2026.10.21_19-31-43-+0800.xcresult`。设备交互工具只提供 iOS 模拟器，无法恢复 macOS 显示，不反复重跑同一环境。
- 最终布局用五个无副作用 Preview 验证：播放浅/深色、通用、文件、高级。初始化直接使用当前偏好作草稿，避免启用状态首次绘制滞后；时长仍有 AX 名称，隐藏重复视觉标签。最后一次 README Debug 构建日志 `/tmp/liquidmusic-settings-build-final.log`，退出码 0，只有既有 AppIntents 元数据跳过提示。最终 UI 点击修正仍待恢复显示后重跑，不以 Preview 代替交互验收。
- 尚未进行可听音频、不同压缩格式过渡、AirPlay/蓝牙、真实菜单栏开关、外观切换或签名沙盒人工验收；原 M7 人工待验项有效。保留既有工作区与 Design 素材，不提交/推送。

历史背景：2026-10-17 完成规划与骨架交接后，用户在 2026-10-18 明确要求继续开发。M7 代码收尾后的上一轮通过 macOS 原生 XCUITest 补验实际 App 的搜索/窗口/队列交互，并修复发现的问题；不扩展第二阶段功能。

### M7 本地文件与键盘进度续验

- PlaybackProgressView 的原生 Slider 增加显式焦点和同时识别的点击手势；聚焦后左右方向键通过已有 seek 跳转 −5/+5 秒，保留鼠标精细定位与原拖动状态机。增加已播时间 AX identifier，便于根据显示时间断言，未改播放控制器或队列。
- 新增两项桌面用例：Command-O 打开真实 NSOpenPanel 后 Escape 取消，空库/播放器不变且无错误；新建 120 秒、8kHz、PCM 全零 WAV，通过真实路径面板选择，验证长英文曲名、暂停、专辑/艺术家进入与返回、鼠标定位后左右键跳转、窄窗与大封面面板入口。
- 进度断言先等鼠标定位到约 60 秒，再在暂停状态下检查三次右键 +15 秒、一次左键 −5 秒，避免把迟到的鼠标 seek 或自然播放当成键盘成功。音量先用界面调到零并检查原生 NSNumber 值；音频本身也完全静音。
- 测试只创建/清理 UI runner 自己的临时目录，路径框先全选替换并核对，再检查“打开”按钮可用。未扫描用户目录、不修改音频/资料库、不放宽沙盒。隔离 App 仍用普通 reader，因此大封面测试只是无图占位面板入口，不代表嵌入图片或真实沙盒已验收。
- 收紧步长断言后的完整六项 UI 在本轮前半段通过（约 135.8 秒），完整 115 项测试通过。随后会话恢复导致临时产物丢失，重新构建并验证：Debug 通过（UI 脚本首条构建，日志 `/tmp/liquidmusic-m7-local-ui-all.log`），Release 退出码 0、包含 arm64/x86_64（`/tmp/liquidmusic-m7-local-release-cached.log`）；完整 115 项逻辑/集成 0 失败、退出码 0、约 8.16 秒（`/tmp/liquidmusic-m7-local-tests.log`）。未把缺失的旧日志当作当前产物。
- 恢复后的六项 UI 批次五项通过，首个搜索输入因系统事件合成超时失败、批次退出码 65；不改搜索业务，单独重试通过、退出码 0。日志 `/tmp/liquidmusic-m7-local-ui-all.log` / `/tmp/liquidmusic-m7-local-ui-search-retry.log`。六项用例均已获得通过记录，但恢复后的批次不是单次全绿。结果包分别在 `/tmp/Liquidmusic-build/Logs/Test/Test-LiquidmusicUITests-2026.10.20_22-33-51-+0800.xcresult` 与 `Test-LiquidmusicUITests-2026.10.20_22-37-51-+0800.xcresult`。
- 恢复后依赖准备停在 SQLiteLib 子模块网络检出，已停止该次构建，复用本机完整且干净的 GRDB v7.11.1 源缓存 `/Users/gede/Library/Developer/Xcode/DerivedData/Liquidmusic-bhiafbjgjlfrxvfnyafwklpxbypv/SourcePackages`。Debug/Release/test 追加 `-clonedSourcePackagesDirPath` 指向该目录及 `-skipPackageUpdates -disableAutomaticPackageResolution`。UI 脚本新增可选 `LIQUIDMUSIC_SOURCE_PACKAGES`，两个命令统一使用缓存；脚本语法检查与实际运行通过，未改依赖版本、Package.resolved 或项目配置。`git diff --check` 通过。
- 保留既有工作区修改与 Design 素材，未提交/推送。物理听音、完整 Tab/VoiceOver、千首及万首以上实际滚动、真实系统外观切换、签名沙盒和系统媒体待验项仍保留。

### AW3 实现与验证（上一轮历史）

- 新增 `Core/Playback/ArtworkAudioFileReader.swift` actor，组合现有 AudioMetadataReading 与 ArtworkCache：一次读取元数据、延迟解析缓存目录、生成同版本缩略图并返回带 artworkPath 的 Track。无封面不解析目录；图片/目录/写入错误返回警告，取消仍抛出。
- `AudioFileReading.readResult` 与 Sendable AudioFileReadResult 把警告随本次结果传递，默认实现兼容原 read/测试替身。AppModel 保留整个读取/缓存期间的 AudioFileAccess、取消和 generation；新选择/取消清掉旧警告，失败保留已播曲目。ContentView 显示可关闭的 AudioImportNotice，不弹阻断播放的图片错误。
- 真实 App 显式注入适配器，XCTest/UI/Preview 仍用普通 AudioFileReader，不创建真实目录。LibraryPaths 复用原 Application Support/Liquidmusic 定位；适配器直接使用其 Artwork 子目录，不调用 LibraryStore.artworkDirectory 或打开数据库。数据库位置、迁移、GRDB 版本、音频文件与扫描审阅流程不变。
- 库内同路径保留持久化 Track/稳定 ID/旧封面；新发现封面而索引无图时提示在音乐文件夹重扫并审阅。没有通过临时单文件覆盖库记录；可能产生未引用缓存，沿用已有不自动清理策略。
- Debug 构建退出码 0，日志 `/tmp/liquidmusic-aw3-build.log`；新增 10 项定向测试通过，`/tmp/liquidmusic-aw3-targeted-tests.log`；完整 115 项逻辑/集成测试通过，0 失败、退出码 0，`/tmp/liquidmusic-aw3-tests.log`（约 8.44 秒），使用 `/tmp/Liquidmusic-build`。`git diff --check` 通过，仅原有 AppIntents 元数据跳过提示；系统 linkd 诊断未影响结果。
- 测试覆盖临时 MP3/带图 M4A（系统 AVAssetExportSession 在测试中生成）、无图不访问缓存、坏图仍可静音播放、目录/写入失败、取消传播、取消后迟到读取、快速重选、旧曲保留/警告清空、库内同路径不写索引及假 SystemMediaTransport 的新封面发布/清空。未安装新依赖，运行测试不需要 FFmpeg。
- AudioImportNotice 的 400 点浅/深色 Preview 已渲染并目视检查；真实选择器、播放听音、跨进程沙盒、控制中心等仍未验收。四项桌面 UI 回归全部通过，退出码 0，日志 `/tmp/liquidmusic-aw3-ui-tests.log`；仍为空库合成事件，不能代替真实封面交互。本轮未重跑 Release。
- 保留已有未提交代码、文档与 Design 图标素材，未扫描用户音乐目录，未提交/推送。

### AW2 实现与验证（上一轮历史）

- AlbumsView 使用 LibraryAlbum.artworkCandidates；LibraryView 的非空专辑详情增加 AlbumHeaderView，以同源 albumArtworkCandidates 显示封面/专辑名/专辑艺术家。原返回、空态、查询和播放入口保留。
- ArtworkView 保留 `track:size:`，新增 `paths:size:loadArtwork:`。完整路径数组作为 task 身份；ArtworkLoadingState 在 MainActor 管理图片，异步按序尝试缓存，缺失/无法解码则回退。每次请求清空旧图，generation + Task 取消拒绝迟到数据，离开视图清理；新请求调度前也不会显示不同路径组的旧图片。
- 实际文件 I/O 仍用 ArtworkCache actor；注入 Sendable Data loader。LibraryView 把同一 loader 通过环境传给歌曲行，保证专辑详情预览不访问模拟文件路径。SPXArtwork 仅在内存绘制图案，含有图/无图/坏图/同名不同艺术家场景，不创建缓存或真实播放器。
- Debug 构建退出码 0，`/tmp/liquidmusic-aw2-build.log`；7 项新 ArtworkLoadingTests + 9 项 AlbumArtworkTests + 12 项 LibraryQueryTests 共 28 项通过，0 失败，退出码 0，`/tmp/liquidmusic-aw2-tests.log`。使用 `/tmp/Liquidmusic-build`；没有 Swift 编译错误，仅原有 AppIntents 元数据跳过提示。`git diff --check` 通过。
- Xcode Preview 已渲染并目视检查：浅色专辑网格、深色窄窗、400 点宽专辑详情、缺失/坏图后成功回退与无图占位。预览不等于实际交互/VoiceOver 验收；千首索引逻辑回归通过，实际持续滚动帧率仍未测。
- 既有四项桌面 UI 首次有搜索框缺失/按钮不可点击两项失败，日志含其他窗口遮挡；补充测试启动忽略恢复状态、固定宽窗并激活后，四项全部通过，退出码 0。初次日志 `/tmp/liquidmusic-aw2-ui-tests.log`，复测 `/tmp/liquidmusic-aw2-ui-repeat.log`，结果包 `/tmp/Liquidmusic-build/Logs/Test/Test-LiquidmusicUITests-2026.10.19_23-31-24-+0800.xcresult`。未修改产品搜索/队列行为。这些仍是空库合成事件，不等于非空封面交互验收。
- 本轮未实现 AW3，不修改音频/数据库/扫描/媒体注册/主窗口队列结构，不提交/推送，保留已有 Design 素材。

### AW1 实现与验证（上一轮历史）

- `Core/Models/AlbumArtwork.swift` 的 AlbumArtworkSelector 校验结构化专辑标识，排除 nil/空白路径，按正碟号/曲号/稳定 ID 排序（未知编号置后），按原始路径去重；筛选、排序、去重阶段检查取消，无文件读写。
- LibraryQueryIndex 初始化时一次分组并缓存完整专辑候选，搜索/排序/艺术家筛选复用。LibraryAlbum.artworkCandidates 保留原 representative/count 语义与旧构造兼容；LibraryQueryResult.albumArtworkCandidates 只在非空专辑 scope 结果中赋值，无结果/其他 scope 为空。
- 新增 `Tests/AlbumArtworkTests.swift` 的 9 项测试：首曲缺图、编号与 ID 顺序（含 Int.max/未知编号）、原始空格路径与去重、合辑/大小写/分隔符身份、四字段双向排序与过滤、空详情、VM 源替换与纯预览、千首索引、取消。路径均虚拟，不读取图片或个人音乐目录。
- README Debug 命令构建退出码 0，日志 `/tmp/liquidmusic-aw1-build.log`；选择 AlbumArtworkTests 与 LibraryQueryTests 共 21 项测试退出码 0、0 失败，日志 `/tmp/liquidmusic-aw1-tests.log`。构建与测试使用 `/tmp/Liquidmusic-build`；仅原有 AppIntents 元数据跳过提示，无 Swift 编译错误。`git diff --check` 通过。
- 尚未接封面 UI，当前专辑网格仍读取 representative，单文件入口仍不提取封面。未新增图片读取服务、改数据库/扫描/播放/工程配置；完整逻辑套件、Release 与 UI 本轮未重跑。保留已有图标素材与文档修改，未提交/推送。

### AW 框架交付与验证（上一轮历史）

- 已有能力核对：扫描读取嵌入封面、512 像素缓存和单曲/系统媒体展示已实现。实际缺口是专辑取过滤排序后的首曲、单文件读取跳过图片；不能宣称目前完全没有封面功能。
- 新契约只有 `AlbumArtworkCandidate` / `AlbumArtworkSelecting`，无实现或调用者。AW1 完成稳定候选与查询，AW2 接专辑网格/详情和缺图回退，AW3 接单文件导入。文件清单、排序规则、测试矩阵和可复制提示词见 `docs/ALBUM_ARTWORK.md`。
- 本轮按 README 命令执行 Debug 构建（`/tmp/Liquidmusic-build`），退出码 0、BUILD SUCCEEDED，新 AlbumArtwork.swift 已参与编译；日志 `/tmp/liquidmusic-artwork-framework-build.log`。无编译错误，仅原有 AppIntents 未依赖的元数据跳过提示；`git diff --check` 通过。无业务实现，未新增或重跑逻辑/UI 测试。原专辑首曲选择与单文件无图行为尚未改变。
- 保留本轮开始前已有的 HANDOFF 图标设计补充及未跟踪 `Design/` 素材；不更改数据库、依赖、项目配置或用户音频，不提交/推送。

## 当前实际状态

| 范围 | 现状 | 验证程度 |
|---|---|---|
| 工程 | 原生 Xcode，Swift 6，macOS 26，显式 MainActor UI / nonisolated 默认隔离 | Debug/Release 构建退出码均为 0；Release 含 arm64/x86_64 |
| 应用状态 | App 持有唯一 AppModel / PlaybackController，唯一主窗口与菜单栏复用 | 构建/预览通过；真实主窗口与菜单栏联动待人工验收 |
| 单文件入口 | 统一打开音频、元数据与嵌入封面、非阻断警告；非阻塞选择面板 | AW3 十项测试与真实面板导入/取消合成事件通过；实际听音/图片交互待验 |
| 异步读取 | 单文件/扫描共用 AudioFileReader；基础标签、albumArtist、曲号/碟号、嵌入封面、文件指纹 | MP3 ID3 与 M4A iTunes 标签测试通过；缺失标签/坏文件有回退或报告 |
| 导入状态 | 显示读取进度和取消；只接受最新选择，失败保留旧曲目 | 过时任务、取消与失败回退测试通过 |
| 文件访问 | 单文件临时 scope；文件夹只读书签、过期刷新、长期根目录租约 | 可控客户端的恢复/失败/释放测试通过，真实签名沙盒待验收 |
| 播放 | AVPlayer，独立状态、旧回调/seek completion 隔离；循环、跳转、历史、拖动编辑与双路交叉渐变 | 含交叉渐变的真实 AVPlayer 静音集成测试通过；物理手势与听音待验收 |
| 设置 | 原生应用菜单/⌘,，四页设置与 SQLite 偏好，取消/好保存语义 | 5 项设置测试及旧库迁移通过，浅深色预览已检查；真实菜单栏/外观切换待人工验收 |
| 界面 | 原生 Table/紧凑 List、专辑网格、艺术家/详情、所有音乐；独立玻璃播放条、右侧队列面板/窄窗 popover、大封面 | 原有预览已检查；空库宽窄队列开关/拖动与音量弹窗通过 XCUITest，其余交互待验 |
| 辅助功能 | 中文模式菜单 AXTitle/值、减少动态动画、透明度/对比度回退、Command-F 与 Escape | 搜索输入/清空、隐藏边栏后恢复焦点、音量 Escape 与模式名称/值通过 UI 自动操作；VoiceOver/完整导航待验 |
| 查询 | 后台缓存标签索引，120ms 搜索 debounce、四字段升降序、结构化专辑标识及全量专辑封面候选 | 本轮 9 项选图与 12 项查询测试通过；AW2 网格与详情已消费候选 |
| 生命周期 | 关窗转为最小化，委托转发/还原；Dock/菜单栏恢复同一窗口，退出标记后正常终止 | 真实 NSHostingController + AppKit 桥的程序化关闭/恢复测试通过；物理点击和实际 Command-Q 待验收 |
| 系统媒体 | 按状态启用并执行六种命令；静态元数据/封面复用、5 秒普通进度校准、异步封面 | 替代传输层测试通过（不注册真实系统媒体键）；硬件/控制中心待人工验收 |
| 队列 | UUID 候选/优先项/历史，顺序/循环/随机轮次；当前/接下来/历史分区，重复条目精确跳转 | 18 项纯队列测试通过（含规模回归）；浅/深色及随机/空队列预览渲染成功 |
| 资料库 | GRDB v1/v2 索引、v3 设置迁移；后台递归扫描、增量复用、进度/取消/报告、确认后更新与失踪索引清理 | 旧库升级含设置保留、真实格式素材、重扫/取消/确认/陈旧方案及查询测试通过 |
| 封面 | 512 JPEG 缓存、全专辑稳定候选、网格/详情、异步回退；真实单文件入口已提取嵌入图片 | 加载/选择/单文件与替代系统媒体测试通过；真实控制中心封面待验 |
| 菜单栏 | MenuBarExtra window 样式，当前曲目/状态/基础控制、恢复与退出 | 浅/深色 Preview 已检查；实际状态项点击待人工验收 |
| 测试 | 独立逻辑测试与桌面 UI target；隔离真实库/媒体/菜单栏/窗口桥 | 本轮 5 项设置测试通过，较早 135 项通过；UI 自动化初始化超时未重试，主 scheme 隔离保持 |

GRDB 7.11.1 经 SPM 接入并锁定。真实 App 添加文件夹后自动扫描；已有目录可在“音乐文件夹”点击扫描。启动恢复已有索引，不重扫。M1–M7 功能与体验收尾代码已接通，不能据此宣称全部用户场景验收完成。

## 最值得先读的代码

- `Liquidmusic/Core/Playback/ArtworkAudioFileReader.swift` / `Core/Models/AudioFileReadResult.swift`：AW3 单文件图片缓存与非阻断警告结果。
- `Liquidmusic/Core/Library/LibraryPaths.swift` / `Features/Library/AudioImportNotice.swift`：共享目录定位与可关闭提示。
- `Tests/ArtworkAudioFileReaderTests.swift`：AW3 十项测试、临时 M4A 导出与替代媒体 transport。
- `Liquidmusic/App/AppModel.swift`：共享依赖、非阻塞文件选择、可取消导入、终止通知。
- `Liquidmusic/App/LiquidmusicApp.swift`：唯一 AppModel、窗口注入、Command-O。
- `Liquidmusic/App/ContentView.swift`：组合界面、进度与错误呈现、无副作用的 SPXData 预览。
- `Liquidmusic/Core/Playback/AudioFileReader.swift`：actor 异步校验/基础标签，AudioFileAccess 配对访问。
- `Liquidmusic/Core/Playback/PlaybackController.swift`：状态、播放意图、代次校验、seek、清理。
- `Tests/LiquidmusicTests.swift`：临时 PCM WAV 生成器、可控读取器与八个测试。
- `Liquidmusic/Core/Library/LibraryStore.swift`：数据库位置、迁移、稳定 ID 和事务读写。
- `Liquidmusic/Core/Library/FolderAccessController.swift`：可注入书签客户端、准备/提交/丢弃授权、根目录租约。
- `Liquidmusic/Features/Library/LibraryController.swift`：连接/恢复状态、文件夹选择和保存流程。
- `Liquidmusic/Features/Library/LibraryFoldersView.swift`：文件夹状态、添加/重新授权与错误入口。
- `Tests/LibraryStoreTests.swift` / `Tests/FolderAccessTests.swift`：M2 的 13 项测试。
- `Liquidmusic/Core/Library/LibraryScanner.swift`：递归发现、最具体根目录归属、复用指纹、准备/校验/提交方案。
- `Liquidmusic/Core/Library/ArtworkCache.swift`：ImageIO 下采样、不可变缓存文件、有界内存读图。
- `Liquidmusic/Core/Models/LibraryScan.swift`：FileFingerprint、AudioMetadata、ScanProgress/Report/Plan。
- `Liquidmusic/Features/Library/ImportProgressView.swift` / `ScanReviewView.swift`：进度、报告与具体变更审阅。
- `Tests/LibraryScannerTests.swift` / `Tests/Fixtures/`：M3 的 16 项测试、合成格式素材和旧库快照。
- `Liquidmusic/Core/Models/LibraryQuery.swift`：纯值查询索引、排序比较器、结构化维度标识与分组结果。
- `Liquidmusic/Features/Library/LibraryViewModel.swift`：窗口查询/导航状态、缓存 worker、取消与代次、统一播放快照。
- `Liquidmusic/Features/Library/LibraryView.swift` / `SongsTable.swift` / `AlbumsView.swift` / `ArtistsView.swift`：内容与状态、原生歌曲表格、维度入口。
- `Tests/LibraryQueryTests.swift`：M4 的 11 项测试，包含可见顺序建队列与预览初始化回归。
- `Liquidmusic/Core/Playback/PlaybackQueue.swift`：M5 的 UUID 队列、可重现随机轮次、插队与历史；upcomingEntries 为纯快照投影。
- `Liquidmusic/Core/Models/PlaybackScrubState.swift` / `Features/Player/PlaybackProgressView.swift`：临时拖动、键盘 seek 与旧条目回调隔离。
- `Liquidmusic/Features/Player/QueueView.swift`：共享播放器包装与可独立预览的纯 QueueContents，当前/待播/历史分区。
- `Tests/PlaybackQueueTests.swift` / `PlaybackModeIntegrationTests.swift`：M5 的 17 项队列、4 项进度状态与3 项真实 AVPlayer 静音集成测试。
- `Liquidmusic/App/WindowLifecycle.swift`：AppRuntime 隔离、唯一主窗口弱注册、原委托代理/转发、NSViewRepresentable 桥、App delegate 与菜单栏组合。
- `Liquidmusic/Core/Playback/SystemMediaController.swift` / `SystemMediaTransport.swift`：命令路由、可用性、发布策略与真实系统边界；测试注入记录型传输层。
- `Tests/SystemMediaTests.swift` / `WindowLifecycleTests.swift`：M6 八项媒体和七项窗口测试，包含后台回调、迟到封面与真实 AppKit 程序化关窗恢复。
- `Liquidmusic/Features/Settings/` / `Core/Models/AppPreferences.swift`：设置草稿、持久化协调、外观与交叉渐变偏好；`Tests/SettingsTests.swift` / `CrossfadeTests.swift` / `CrossfadeFormatTests.swift` 覆盖新增行为。
- `LiquidmusicUITests/LiquidmusicUITests.swift` / `Scripts/verify-ui.sh`：七项 macOS 桌面事件回归与构建/启动脚本，独立于主 scheme 的 135 项测试；脚本支持复用已解析源缓存。

## M1 实现约定

- 当前单文件导入成功后替换临时列表为一首歌曲并自动播放；M3 通过 AppModel 合并库内歌曲与临时歌曲，按路径去重，不会清空持久化资料库。导入验证失败/取消时保留原列表及播放器。
- 快速重选时取消旧 Task，并通过 generation + Task.checkCancellation 拒绝过时结果。测试中的可控 reader 刻意忽略取消，确保保护有效。
- AudioFileAccess 对成功 start 的 scope 才 stop。校验用与播放器用的 scope 独立配对。M2 文件夹书签不要复用为“扫描结束立即释放根目录权限”。
- 主控制按钮按 wantsToPlay 表示用户意图，waiting 时仍可暂停；声波按实际 playing 状态变化。
- item 状态、时长、结束/失败通知和 seek completion 都核对代次；周期时间读取执行时的当前 item，seek 期间不覆盖目标进度。
- paused、ended、failed 是独立状态。播放结束后按播放从头开始；failed 禁用普通播放按钮，通过重新选择重试。
- AppModel.start 只在真实 App 的窗口出现时调用，内部幂等。Preview 只构造注入 model，不调用 start，不打开选择器或自动播放。
- shutdown 为终止清理，调用后该 PlaybackController 不再重新启动。普通关窗不能调用它；M6 已实现最小化且保持共享模型。
- `isolated deinit` 需要支持该语法的 Swift 工具链；当前 Xcode 27.1 / Swift 6.4 已编译验证。

## M2 实现约定

- AppModel 注入可选 LibraryController；真实 App start 打开 Application Support/Liquidmusic/Library.sqlite，预览和普通 AppModel 测试不打开磁盘库。
- M2 引入共享 scheme 的 LIQUIDMUSIC_TESTING=1，但 M6 测试发现此前 TestAction 继承 Launch 环境导致该变量被忽略；已修正 shouldUseLaunchSchemeArgsEnv=NO 并添加 AppRuntime XCTest/Preview 检测和断言。旧记录只能保证用例显式注入了临时库，不能据旧 scheme 配置推断当时宿主已可靠隔离；本轮未清理或修改任何用户库。不要移除现在的隔离设置。
- 数据库/Artwork 目录创建、迁移与 SQL 均在 LibraryStore actor 执行。数据库失败呈现 failed 状态，可重试，不回退内存或清库。
- `saveFolder` 对规范路径去重且保留原 ID；`upsertTracks` 是基础存储接口。真实扫描使用 applyScan 进行事务写入后重新查询 tracks，保证 UI 使用稳定 ID。
- `prepareSelection/prepareRestoration` 创建待提交租约；写库成功后 `commit` 才替换旧租约，失败 `discard`。过期书签先刷新再保存；无效/缺失目录保留记录，标记需要重新授权。
- 扫描通过 `access.validatedURL(for:)` 获取并重新验证根目录，租约持续到 shutdown，不能扫描完成就释放。
- M1 关闭播放器后再调度文件夹授权释放；测试可 await `LibraryController.shutdown().value` 确认释放完成。应用退出时由进程生命周期最终回收资源。
- 新增 app-scoped bookmark entitlement，现有 App Sandbox / user-selected readonly 继续由 Xcode 配置提供。Xcode 的 AddEntitlement 注册表未识别该键；依据 Apple 官方文档配置了独立 entitlements 文件（参考链接在 ARCHITECTURE），未关闭沙盒或扩大为读写权限。
- 用户约定要求删除、覆盖或其他不可逆操作前展示具体方案并确认。M3 的已有索引覆盖/清理必须通过应用内审阅；未执行任何真实用户库的清理或音频修改。

## M3 实现约定

- 新增 v2_fileFingerprint 迁移，只添加可空 fileSize；保留 M2 数据，首次重扫补齐大小/修改时间。旧库升级有独立测试快照，不要改写 v1 迁移。
- LibraryScanner 每个根目录串行读取，跳过隐藏项、包及符号链接；扩展名大小写不敏感，支持 aif 别名。重叠路径归最具体的已注册根目录，避免扫描顺序改变归属。
- AudioFileReader 同时实现 AudioFileReading / AudioMetadataReading，单文件不提取图片，扫描提取。标题缺失回退文件名，艺术家/专辑回退未知值，专辑艺术家优先 iTunes albumArtist 或 ID3 Band，最后回退 artist。
- 扫描只读音频并生成 LibraryScanPlan。已有路径的有效指纹和封面缓存可复用；读取失败保留其旧索引，坏图只增加问题，不丢弃音频。
- 纯新增自动提交；包含更新或失踪记录的方案显示路径、字段变化、数量，等待“应用索引变更”。取消不保存当前方案。源文件重现、指纹变化或数据库基线变化会拒绝陈旧方案，要求重扫。
- 只有完整枚举才提出失踪记录清理；无权限/枚举不完整/取消时不清理。事务保存方案中的新增/更新/删除及问题记录，lastScanAt 仅在完整枚举后推进。删除仅针对索引，不删除音频。
- 扫描进度分为发现、索引、待审阅、保存、完成/取消/失败，UI 约 100ms 节流。保存阶段不提供取消按钮；多个根目录逐个提交，取消不会回滚先前已完成目录。
- 新文件夹自动扫描由真实 App 设置 automaticallyScanNewFolders=true；测试和预览默认 false。load 仅恢复数据库与授权、读取已有 tracks，不在启动时重扫。
- 缩略图按 SHA-256 命名，最长边 512。写文件使用 withoutOverwriting；取消方案可能留下未引用的缓存文件，暂不自动删除。NSCache 上限 160 项/32MB。
- 进度/报告/审阅都有无副作用 Preview。审阅 List 行显式包裹 ZStack，修复本机 Preview 的自定义不透明行崩溃；不要在未复核的情况下去掉。

## M4 实现约定

- ContentView 每窗口持有 LibraryViewModel，并在 AppModel.tracks 变化时更新快照；播放器、源索引、扫描和授权仍共享原有实例。浏览 VM 不直接连接数据库或文件夹授权。
- LibraryQueryIndex 位于 Core/Models，不依赖 SwiftUI/AppKit。LibraryQueryWorker actor 缓存规范化字段，120ms debounce 合并搜索；排序、筛选、分组都不在 View body 或 MainActor 全库执行。取消与 generation 校验拒绝迟到结果。
- 搜索匹配 title/artist/album，忽略大小写与变音符号，修剪首尾空白；中文子串，不提供拼音。专辑按结构化 album + albumArtist 分组，艺术家按 track.artist；数量为搜索匹配数量，详情保留 query/sort，返回恢复分类，切换 Sidebar 清除 scope。
- Table 与排序菜单共享 TrackSort；四字段升降序，时长使用秒，多个比较器依次执行，最终以标题/ID 稳定破同值。专辑/艺术家入口按名称排序，不受歌曲排序字段影响。
- SongsTable 使用原生 selection/contextMenu primaryAction 处理双击/主操作，行内播放和右键播放也调用 LibraryViewModel.play。该方法使用当前显示的 result.tracks 同一快照创建队列，过时选择 ID 无操作。多选“下一首播放”按可见顺序插入；空队列直接播放所选列表。M5 沿用这些入口并收敛队列状态机。
- Sidebar 的歌曲与所有音乐使用独立 tag；播放列表分类仅显示固定“所有音乐”。搜索框使用系统语义背景，依赖系统侧边栏材质，避免额外叠一层玻璃。
- LibraryView 分开显示未导入、读取/导入中、读取失败、空文件夹、搜索无结果和已失效分类；保留导入进度/报告/授权与错误入口，已有数据刷新时继续显示旧快照及进度。
- 每个新增 UI 有无副作用 #Preview。ContentView 支持注入模拟浏览 VM；preview 同步计算 SPXData，不调度查询或触碰文件。Observation 初始化赋值可能执行 didSet，isConfigured 在所有初始字段完成后才打开，避免空查询覆盖模拟结果；有回归测试。

## M5 实现约定

- 队列候选、优先项、历史使用 QueueEntry UUID，数组下标仅用于索引；相同 Track 是独立条目。replace 清空历史/插队但保留模式；缺失起点回退首项，空队列插入首曲直接成为当前项，不留在优先列表。
- 可注入 shuffleSeed 的值类型随机源。初始轮当前项已播；后续完整轮包含全部条目，只避免首项立即重复上一轮末曲（单项除外）。插队不重洗余下候选，跳转/消费优先项同步移除候选；线性遍历跳过本轮已消费的插入项，循环新轮恢复完整列表。
- 下一首优先重走回退后的前进分支，再消费优先项和模式候选；单曲循环自然结束先重复当前项，手动下一首才消费待播。插队/跳转/切模式清除前进分支，但模式切换保留历史和待插队项；重复设置相同模式不重置随机轮。
- 上一首使用最近 200 次真实访问；无历史的随机模式不能按物理下标回退，线性模式可退到物理上一项。PlaybackController 保留大于 3 秒先回曲首的规则；新测试验证了它与重复歌曲 UUID 跳转、快速切换的衔接。
- upcomingEntries 在队列副本中推演本轮手动切换顺序，不改变真实随机源，不展开下一轮。QueueContents 只接收纯快照和选择回调，预览不需要把假曲目载入 AVPlayer。队列行显式 ZStack 修复了本机 Preview 的 TableViewListCore 自定义行崩溃；勿在未验证时去掉。
- PlaybackScrubState 管理临时进度：拖动不立即 seek、不随 tick 回跳，释放提交；无编辑手势的键盘写入立即提交。PlaybackProgressView 的闭包捕获条目 ID，切歌重建 Slider、取消临时位置，拒绝旧回调。AVPlayer 的 seekID/loadGeneration 保持不变；结束回调额外忽略 failed/ended。
- AudioFixture 在测试 target 内共享，所有真实播放集成测试使用生成 WAV 且音量为零（S1 增益验证另注入 isMuted 的真实 AVPlayer）。不挂载菜单栏或注册真实媒体。M5 当时未持久化偏好；S1 已新增默认模式/启动音量持久化，整个队列仍不保存，启动不自动播放。

## M6 实现约定

- App 场景改为唯一 Window(id: main) + MenuBarExtra(.window)，AppModel/播放器仍由 App 持有。MiniPlayerView 的显示/退出回调注入，Preview 都为空操作；App 实际回调恢复旧窗口，缺失时 openWindow(main)，退出调用 NSApplication.terminate。Command-O 先恢复窗口，再打开选择面板。
- WindowLifecycleController 弱持有主窗口，窗口桥只安装于真实主窗口，不作用于选择器、sheet 或 Preview。代理尊重原委托的 close 否决，只把允许的普通关闭改为最小化；其他可选方法用 NSObject 动态转发，detach 时不覆盖后来安装的其他委托。SwiftUI 初始配置后下一次主线程调度再核对一次原委托；全屏先退出再最小化，恢复可取消待最小化。
- Dock reopen 与菜单栏调用同一 restore；没有窗口时交还 SwiftUI 默认重开。App delegate 退出时标记 isTerminating 并返回 terminateNow，使正常退出不转为最小化；AppModel 原有 willTerminate 清理保留。关窗不会释放共享播放器或调用 shutdown。
- SystemMediaTransport 是实际可替换的系统边界：真实实现保存六种命令 token，测试实现只记录命令/发布。控制器同步切到主线程检查/执行后返回状态，不用异步排队后无条件报告 success。空队列 noSuchContent，失败或无效 seek commandFailed；next/previous 根据队列可行动性启用，play/pause 根据意图启用。模式变更与插队也立即刷新可用性。
- NowPlayingSnapshot 与静态元数据是 Sendable 值类型。曲目/速率/状态/定位变化立即发布，普通播放进度 5 秒校准；静态字典和 MPMediaItemArtwork 不随 tick 重建。封面通过原有 ArtworkCache actor 异步读，取消/路径/终止检查拒绝迟到数据，同一路径跨条目复用。shutdown 幂等取消封面、仅移除自己的 token、禁用命令并清空元数据；释放和晚回调有测试。
- AppRuntime 同时识别 LIQUIDMUSIC_TESTING、XCTestConfigurationFilePath / XCTestBundlePath 与 XCODE_RUNNING_FOR_PREVIEWS；隔离时不创建真实 LibraryController、不调用 AppModel.start、不插入菜单栏或连接真实主窗口桥。M6 修复共享 scheme 的 shouldUseLaunchSchemeArgsEnv=NO，保持测试变量真正来自 TestAction，而非 LaunchAction。
- 媒体单测使用记录型传输层与生成 WAV，不注册真实媒体键；窗口单测使用探针窗口与注入的无操作激活回调。另一个独立测试创建临时真实 NSWindow + NSHostingController + WindowLifecycleBridge，执行 performClose、观察 isMiniaturized，再恢复并关闭临时窗口；这是程序化验证，不等同于实际 Dock/状态栏点击、Command-Q 或控制中心测试。

## M7 实现约定

- 本轮开始发现 ContentView 的局部 Bindable 声明与 NavigationSplitView 之间换行损坏，阻塞编译/预览，已修正。未重建工程或改动依赖。
- 主窗口分别布局资料库与 PlayerBar，不再把播放条作为 split view 的 safeAreaInset。底部语义背景隔开两者；浅深色预览已确认侧边栏页脚不透入播放条。
- M7 续验发现系统 inspector 在队列展开后拖窄时触发 AppKit 约束更新崩溃，已改为原生 HStack/Divider 右侧队列，最外层 GeometryReader 测量完整窗口宽度。900 点以下从队列按钮弹出 popover，跨阈值自动收起，播放状态保持；实际拖动回归通过。不要重新接回未经验证的 inspector。
- 窗口根视图通过 toolbarColorScheme 跟随内容区 colorScheme；深色预览和实际浅色 UI 截图中图标可见。续验中来回切换 Preview 外观覆盖后，浅色画布出现工具栏图标不可见，实际 App 的跨外观切换仍需人工确认；不硬编码颜色或替换系统材质。
- 窗口最小 640×520。SongsTable 根据内容宽度在原生 Table 与 List 间切换，仍共用同一 VM 快照、selection、主操作/上下文菜单，工具栏排序始终可用。窄宽切换保留选择 ID，真实鼠标/键盘行为待验收。
- PlayerBar 的 ViewThatFits 在横向和两行间选择；窄布局音量使用 popover，模式/队列保持可见。减少透明度或增加对比度采用不透明语义背景与边框；减少动态效果关闭队列展开动画，声波沿用原有暂停逻辑。
- 控件补充标签/值/help，前后曲按钮根据 canSkip 启用。模式菜单用文字“播放模式”避免 AppKit 将图标读作英文 Right，AXTitle/值有 UI 断言。音量 popover 提供可聚焦容器和带 cancelAction 快捷键的“完成”，Escape 回归通过。
- Command-F 使用 focusedSceneValue 路由当前窗口；Sidebar 的可取消 task 等视图进入后聚焦，修复折叠期间 FocusState 请求失效。输入、Escape 清除、隐藏侧边栏后恢复输入已通过系统合成事件，不注册全局键盘监听。
- LibraryViewModel.preview 可注入模拟 tracks；SPXData.largeLibrary 为 1000 条纯虚拟索引。两项规模回归覆盖查询分组/过滤和顺序/随机插队投影，计时数据见 VALIDATION；不加载虚拟音频、不扫描用户库。
- 续验增加独立 LiquidmusicUITests target，位于 App 同步目录之外；Xcode 自动生成 UI scheme。通过 `bash Scripts/verify-ui.sh` 运行，先构建同目录 App 再跑 UI runner；可用 LIQUIDMUSIC_DERIVED_DATA 指定缓存目录。runner 用本地 ad-hoc 签名，命令参数 TEST_TARGET_NAME=Liquidmusic 不写入工程。预览/单测继续原有隔离；UI launchEnvironment 显式传 LIQUIDMUSIC_TESTING=1，并使用 XCUIApplication(url:) 避免误启其他构建目录实例。脚本和四项 UI 用例已实际运行通过。
- 详细构建、预览、规模记录和人工待验清单集中在 `docs/VALIDATION.md`。减少透明度/减少动态的系统切换、VoiceOver、完整 Tab/Slider 键盘与物理手势仍未人工验收。

## M1–M6 历史验证记录

Debug 构建：

```sh
xcodebuild -project Liquidmusic.xcodeproj \
  -scheme Liquidmusic -configuration Debug \
  -derivedDataPath /tmp/Liquidmusic-build \
  CODE_SIGNING_ALLOWED=NO build
```

自动化测试：

```sh
xcodebuild -project Liquidmusic.xcodeproj \
  -scheme Liquidmusic -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/Liquidmusic-build \
  CODE_SIGNING_ALLOWED=NO test
```

- Xcode 27.1 / Swift 6.4，arm64，测试运行系统 macOS 27.0.1。未在 macOS 26 真机执行。
- 87 项 XCTest 全部通过，0 失败。测试使用生成的临时文件或 bundle 内合成素材，播放器音量为 0，不扫描用户真实音乐文件夹。
- 覆盖：读取/损坏/缺失/目录、旧任务晚返回、取消读取、失败保留旧曲目、真实播放/暂停/seek/继续/自然结束/重播、切歌时旧回调隔离、失败与重复 shutdown、控制器释放与音量边界。
- M2 覆盖：数据库迁移/重开、书签 BLOB 和问题记录、路径去重/稳定 UUID、folderID 过滤、目录冲突、事务回滚/外键、无效时长、数据库失败不回退、重复目录租约、过期书签刷新、无效书签重新授权、丢弃失败授权、start=false 的配对停止。
- M3 覆盖：真实 MP3/M4A 标签、嵌入封面，WAV/AIFF/FLAC 候选；隐藏项/包/符号链接、损坏文件、重复扫描缓存复用、重叠目录、取消与迟到结果、确认前不写入、确认后清理、文件重现/文件或库变化、权限失败不清理、自动导入、重开不重扫、v1 数据保留升级。
- M4 覆盖：三字段及中文/大小写/变音符号搜索、空查询恢复，四字段双向排序、同值/多比较器稳定性，同名专辑/合辑/分隔符碰撞、艺术家维度，scope+query+sort 组合，1,000 条模拟数据快速查询和源替换，分类/详情返回，过滤排序后队列与过时选择，多选插队顺序及预览快照稳定性。没有把这视作超大库性能验收。
- M5 覆盖：空/单项/末尾、顺序与两个循环模式、重复 Track UUID 跳转、后插优先、空队列插入、多固定 seed 多轮随机不重复/轮次交界/插队候选不重洗/跳转去重、真实历史前后退、模式切换/相同模式幂等、replace 与投影不变性、200 次历史边界。另有拖动/tick/键盘/取消/旧条目/时长变更状态测试，真实 AVPlayer 自然单曲循环与待插队保持、列表循环回绕、3 秒回首和快速重复条目切换测试。
- M6 覆盖：空/失败/合法内容的命令可用性、播放/暂停/定位/切换及返回值，无效 seek，发布节流/暂停/定位立即更新，后台回调主线程执行，连接与终止幂等/释放/晚回调，封面取消/迟到/复用；窗口关闭最小化、原委托转发/否决/拆卸、Dock 路由和恢复逻辑、退出标志、全屏待最小化/取消、播放器继续前进、弱窗口注册/宿主隔离，以及真实 AppKit + SwiftUI 桥的程序化最小化与恢复。全屏/Dock/退出流程中的部分测试是替代对象或直接调用委托，不是物理系统交互。
- Tests/Fixtures 中的音频/纯色图由本机已有 FFmpeg 合成，已随 XCTest bundle 提供；运行测试不需要 FFmpeg。FLAC 依 AVFoundation 实际能力接受或记录跳过，不泛化为支持所有变体。
- 本轮沿用已解析依赖的构建目录 `/tmp/Liquidmusic-m2-verify.Ll36gl`，加 `-skipPackageUpdates -disableAutomaticPackageResolution`。Debug 构建退出码 0，测试退出码 0；日志 `/tmp/liquidmusic-m6-build.log` / `/tmp/liquidmusic-m6-tests.log`。通用命令如上，可替换 derivedDataPath 使用独立目录。
- 主窗口 `#Preview` 在 macOS 成功渲染，检查了注入模拟数据的列表和播放条。没有注册预览媒体键。
- M3 的 LibraryFoldersView、ImportProgressView、含问题的 ImportReportView、含新增/更新/移除的 ScanReviewView 均渲染成功；审阅视图检查了浅色/深色。M2 的包加载阻塞已解除。
- M4 的 SongsTable、AlbumsView、ArtistsView、主窗口、专辑详情、无结果、固定播放列表、首次导入、导入中和读取失败预览均成功渲染。主窗口、专辑/艺术家检查浅/深色；没有模拟真实鼠标双击、悬停、标题排序或键盘手势，不等同于交互验收。
- M5 的空队列、含当前/待播/历史的浅深色队列、随机队列、PlaybackProgressView 和 PlayerBar Preview 成功渲染并检查。没有模拟真实滑块、队列行点击或硬件媒体键，未做可听声音验收。
- M6 的菜单栏 MiniPlayerView 浅/深色 Preview 已渲染并检查。Preview 不挂载真实 MenuBarExtra、不连接媒体键，恢复与退出按钮为空操作；不等同于真实状态栏弹出/退出验收。当前 Debug 构建没有 Swift 编译警告，只有 AppIntents 元数据提取跳过提示。
- 编译日志中 AppIntents 元数据跳过提示不是编译错误。运行测试时系统可能输出 linkd/音频诊断，不影响测试通过。
- 没有提交/推送 Git。保留了前次工作区中未提交文件。

## 仍需人工验收

M7 续验已通过空库 Command-F/Escape、隐藏侧边栏恢复、音量弹窗、队列宽窄切换的桌面自动操作；VoiceOver、系统辅助功能、千首列表实际滚动和完整物理交互仍待验，见 `docs/VALIDATION.md`。下列历史待验项仍有效，没有把它们改记为人工通过。

1. 用 Xcode 运行，点击“打开音频文件…”或 Command-O，用测试 WAV 或自己选择的音频验证系统面板；取消面板不显示错误。
2. 听音，检查暂停、音量、拖动进度以及聚焦 Slider 后用方向键调整。自动化验证了底层 seek，未模拟真实鼠标/键盘手势。
3. 快速连续选择两首，检查曲名、时长、状态与实际声音一致；坏文件提示可见并能重新选择。
4. M6 已改为唯一主窗口。验证主窗口最小化后菜单栏仍显示当前曲目且能控制同一个播放器，恢复后浏览和播放状态保持一致。
5. 媒体键、Now Playing/控制中心、真实沙盒授权、实际 Command-Q/菜单栏退出仍需人工验证；不能用替代传输层或直接调用委托的测试代替。
6. M2：在签名沙盒 App 中用“音乐文件夹”添加测试目录，退出并重启，验证无需重新选择仍有权限；改名/移动/断开目录后验证状态与重新授权。单测使用可控书签客户端，不代表真实跨进程权限验证已完成。
7. M3：用自己选择的测试文件夹验证首次引导/自动导入、正在播放时移动窗口和调整控件、取消、查看问题报告。重扫时检查审阅清单的取消/确认按钮，以及确认前旧索引不变。不要未经确认扫描真实个人资料库做验收。
8. M4：搜索与标题/艺术家/专辑/时长升降序组合后，双击中间一首，确认队列与表格一致；清除搜索恢复列表。检查行内播放悬停、当前行声波、右键/多选插队、专辑/艺术家返回，以及独立的歌曲/所有音乐选择高亮。
9. M5：连续快速上一首/下一首、随机中多次插队、重复歌曲队列行跳转，确认界面/声音/当前波形一致；拖动中等待 tick 或切歌，旧拖动不得定位新曲。聚焦 Slider 后方向键应 seek；四模式的自然结束和手动切歌分别验证。自动化已验证底层状态，真实手势与听音未代替。
10. M6：在真实签名 App 中播放时点击红色关闭按钮，检查 Dock 最小化、播放持续，再通过 Dock/菜单栏恢复；全屏关闭后也应最小化。检查物理媒体键、系统 seek/暂停/切歌、控制中心标签/封面/速率，最后分别 Command-Q 与菜单栏退出。当前只完成程序化窗口/状态测试与预览，未执行这些实际系统操作。

## 后续已知问题

- 系统媒体已改为状态驱动发布与定期校准，仍需在真实控制中心/物理媒体键环境验证；Dock reopen 与 Command-Q 的最终系统行为未人工操作验证。
- 书签和歌曲索引已持久化，真实签名沙盒的跨进程权限仍待人工验收。完成报告保存在当前会话，问题行追加到 SQLite；尚无跨会话报告历史界面。
- 首版扫描把当前根目录的变更暂存内存，串行处理文件；未做超大库规模验证，M7 可按实际测量优化。未实现缓存垃圾回收，取消可能留下未引用缩略图。
- M7 已测量 1000 条合成索引查询与约 1000 条队列投影/插入，见 VALIDATION；仍未测量万首以上库、内存峰值与持续滚动帧率，不要为此扫描真实个人目录。随机去重按条目 UUID，用户主动重复加入的相同歌曲允许分别播放。
- 播放条叠层、隐藏边栏后的搜索焦点、音量 Escape 与队列宽窄切换均已修复并分别通过预览或桌面自动操作；持续缩放/全屏、长标签、非空队列和完整辅助功能人工验收仍待补。
- 本机浅色 Preview 在切换外观覆盖后出现工具栏图标不可见，实际浅色 UI 自动操作截图中图标可见，深色 Preview 正常；优先在实际 App 中来回切换系统外观复核，详见 VALIDATION。

## 下一项：UI1 桌面续验与 S1/M7 剩余人工验收

可直接复制：

> 阅读 AGENTS.md、HANDOFF、VALIDATION 与 ROADMAP 的 UI1。浏览历史/智能列表与 Now Playing 已实现，36 项定向测试及布局检查通过；不要重复开发。用户前轮明确跳过桌面回归，未获新意图前不反复启动需要系统身份验证的 UI runner。优先用临时音频补浏览切换、成功播放后的智能列表、重启恢复记录、Now Playing/歌词/Escape 与参考图对照；图片网格、听音、三指拖移、VoiceOver、设置和真实签名沙盒仍待验。保留 NavigationSplitView + HStack 队列与顶部安全区拖动带，不恢复 inspector。只使用自建或用户明确选择的素材，不扫描个人库、不修改音频或绕过扫描审阅、不擅改系统安全设置、不提交/推送。

## 2026-10-19 图标设计素材补充

用户要求参考 Apple Music，为 Icon Composer 提供可编辑的 Liquid Glass 分层素材。本次新增 `Design/IconComposer/Liquidmusic-Coral-v1/` 与同名 ZIP：1024 × 1024 背景、后层液面、前层液面、完整音符、可选水滴，分别提供 SVG/PNG；附平面组合预览、内置 imagegen 生成的独立玻璃概念图和中文导入说明（含提示词）。正式图层为独立矢量路径，不预烘焙玻璃高光/阴影；概念图不是图层精确渲染。

验证：5 个 SVG XML 可解析；5 个图层 PNG 尺寸一致，前景含真实 alpha；平面构图已目视检查。README 指定 Debug 构建退出码 0，BUILD SUCCEEDED。未更改 AppIcon、运行代码与项目配置；尚未在 Icon Composer 内实际导入或验收动态光照/深浅色/单色效果。下一项图标工作为用户在 Composer 导入调节材质并导出 .icon；原 M7 人工验收仍待完成。
