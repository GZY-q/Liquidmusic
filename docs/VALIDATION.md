# 第一阶段验收记录

### UI1 Apple Music 参考图与 Now Playing（2026-10-23，最新）

- Debug 构建退出码 0：`/tmp/liquidmusic-interface-debug-verified-20261023.log`，无 Swift 编译错误，只有既有 AppIntents 元数据提示。最初 ToolbarContent 混用错误已修复；未升级依赖、未改变测试 scheme 隔离配置。
- 36 项定向测试 0 失败、退出码 0，约 2.46 秒：`/tmp/liquidmusic-interface-tests-20261023.log`，结果包 `/tmp/Liquidmusic-build/Logs/Test/Test-Liquidmusic-2026.10.23_15-37-41-+0800.xcresult`。包含 8 项 LibraryInterfaceTests、12 项查询、6 项存储、4 项进度和 6 项歌词。新增覆盖独立记录持久化/旧库迁移、原索引不变、串行计数、智能排名/过滤/网格顺序、导航分支、迟到结果，以及真实静音 AVPlayer 暂停/seek/失败/交叉渐变事件。既有 weak 变量与系统 linkd 诊断未标为本轮修复。
- 已目视检查 1100×680 宽浅、640×520 窄深的主界面，及最近添加网格布局、600×660 浅色/460×520 深色 Now Playing；播放条保留单行，控件无截断。顶部 safeAreaInset 修复了前轮宽窗表头遮挡。独立 AlbumsView 预览显示模拟封面与缺图回退，完整 ContentView 网格预览仍显示占位，未作为集成图片加载通过记录。
- 隔离 NSHostingController 运行读数：实际窗口标题“歌曲”；1100×700 和 640×520 内容区域，顶部 NSView 拖动带分别 1100×24 与 640×24。使用内存模拟曲目与未播放的预览播放器，不读真实库、不注册媒体。宿主位图导出尝试未产出图片，尺寸读数与 Xcode Preview 分开记录，不冒充实际窗口截图。
- 图像保存于 `/Users/gede/.codex/visualizations/2026/10/23/01a167a9-c679-7090-92fc-18814fd372c0/interface-20261023/`。按参考图调整原生侧边栏/条纹表格/玻璃播放条；颜色使用系统强调色，未宣称逐像素完全一致。
- UI 用例新增封面打开 Now Playing 及 Escape 关闭断言，保留独立歌词入口；沿用前轮跳过桌面回归决定，未启动 runner/系统验证，不将修改用例视为运行通过。未重跑全量、Release、CPU 或听音。
- 待验：真实点击与快捷键、前进/后退分支、网格/列表切换、智能记录跨启动、Now Playing/歌词双层 sheet 的 Escape、物理缩放/三指、VoiceOver/减少透明度、真实签名沙盒及 S1/M7 历史待验。

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


## 2026-10-23 原生玻璃与侧边栏精简（最新）

- 播放条直接使用系统 glassEffect，进度改为 SwiftUI Slider；侧边栏底部仅保留曲目统计，工具栏/Command-O 不变。
- README Debug 构建退出码 0，日志 `/tmp/liquidmusic-native-glass-build-20261023.log`；4 项 PlaybackScrubTests 通过、退出码 0，日志 `/tmp/liquidmusic-native-glass-scrub-tests-20261023.log`。依赖沿用固定 GRDB 7.11.1 本地缓存。
- 宽浅/窄深 Preview 已目视检查，未见截断；截图保存于本轮 visualizations 的 `native-glass-player/`。按用户要求跳过桌面回归，未触发系统身份验证。未重跑 CPU/全量/Release/听音；原人工待验有效。

## 2026-10-23 细播放条与降低透明度

- 播放条约 56 点高，32 点封面、单行曲名、3 点细轨道，窄窗保持单行。语义底色不透明度 0.88，系统玻璃单层；辅助功能回退保持不透明。宽浅/窄深 Preview 已目视检查。
- 最终 Debug 构建退出码 0（`/tmp/liquidmusic-slim-build-final-20261023.log`），4 项 PlaybackScrubTests 通过、退出码 0（`/tmp/liquidmusic-slim-scrub-tests-20261023.log`）。未重跑全量、Release、CPU 或听音。
- 前日窄窗音量/队列用例通过，进度用例失败；录屏确认默认原生 slider.click() 点在当前旋钮，已改显式轨道中点坐标，并读取数值 AXValue。2026-10-23 续验因 XCTest“Enable UI Automation”系统身份验证未完成而初始化超时，退出码 65，用例未开始，不能记为通过。日志 `/tmp/liquidmusic-slim-ui-verified-20261023.log`。
- 用户在 2026-10-23 明确“本轮跳过桌面回归”，本轮不再重试或等待系统验证。轨道定位、左右键、音量/队列和大封面入口的最终桌面复测保留为待验；听音/物理手势/VoiceOver 与原 S1/M7 待验仍保留。

## 2026-10-22 播放刷新与悬浮播放条

- 最终 Debug 构建通过，退出码 0；日志 `/tmp/liquidmusic-floating-build-verified.log`。复用已有 GRDB 7.11.1 SourcePackages 缓存，无依赖升级。
- 最终 32 项相关测试 0 失败，退出码 0，约 70.81 秒；日志 `/tmp/liquidmusic-floating-final-tests.log`。覆盖两种渐变设置下的 UI 限频、暂停定位、交叉渐变 1/6/12 秒、播放模式、替代系统媒体和隔离 CPU 采样。
- `Scripts/verify-ui.sh` 的窄窗音量/队列与宽窄队列切换两项通过，退出码 0；日志 `/tmp/liquidmusic-floating-ui.log`。本次 runner 初始化成功，不代表未重跑的 S1 设置用例已验收。
- 宽浅/窄深 Preview 已目视检查，无控件截断；预览位于本轮 visualizations 的 `floating-player/` 目录。未测试可听音频、物理媒体键、签名沙盒或完整辅助功能。
- 普通观察回调由 20Hz 降为 4Hz；开启渐变保留 20Hz 曲尾检查，但 UI/定期媒体检查同样限为约 4Hz。声波使用 5Hz periodic + 固定 Canvas，暂停移除时间线。
- Debug CPU 采样：可见 1100×680 窗口、1000 条不同路径模拟索引、临时静音 WAV、替代媒体、getrusage 总 CPU / 墙钟时间，以单核心 100% 计；ABBA 四段各 4 秒。最终开启渐变 19.07%/18.81%，关闭 18.34%/18.71%，暂停 0.68%。此前同条件未解耦 UI/未换 Canvas 的样本约 45–49%/22%（`/tmp/liquidmusic-floating-cpu-distinct.log`）。这是短时测试宿主采样，不是完整原版或 Apple Music 对照，不能宣称普遍降幅。初次同路径样本会让所有行被识别为当前曲，已修正测试并弃用该批数字。
- Release 同条件采样 1 项通过，退出码 0；开启渐变 18.69%/18.40%，关闭 18.01%/19.46%，暂停 0.65%。日志 `/tmp/liquidmusic-floating-cpu-release-testable.log`，arm64、`ENABLE_TESTABILITY=YES`（保留优化，只为 `@testable` 开放模块）；首次未带该参数的测试模块编译失败，退出 65。未进行完整 Release 测试、签名沙盒或 Apple Music 实测对照。

更新：2026-10-22。M1–M7、AW1–AW3 与用户追加的 S1 设置/交叉渐变代码已接通；**自动化验证通过不等于人工验收全部完成**。原 M7 待验项继续保留。

本文 `/tmp` 日志和 xcresult 是运行时的临时产物，环境恢复后可能已不存在；历史退出码保留在文档，复现命令以 README 为准。

## S1 设置交互完善（2026-10-22，最新）

- 完成运行期间分页记忆、⌘1–⌘4 分页、设置窗口的外观草稿预览、当前页默认值恢复、未保存/保存进度提示及错误重试。恢复默认与外观预览不提前写库；无改动点“好”不重复保存；文件夹操作流程未改。
- Debug 构建退出码 0，日志 `/tmp/liquidmusic-settings-polish-build-final.log`；仅有既有 AppIntents 元数据提示，无 Swift 编译错误/警告。只运行已有 5 项 SettingsTests，0 失败、退出码 0，日志 `/tmp/liquidmusic-settings-polish-tests.log`，结果包 `Test-Liquidmusic-2026.10.22_20-40-50-+0800.xcresult`。`git diff --check` 通过。
- 播放浅色、通用深色 Preview 渲染并目视检查，新增底栏不遮挡内容，保持系统字体、语义颜色与 620×440 内容尺寸；不打开真实库、不播放音频或注册媒体。布局预览不等于真实快捷键、分页重开、外观取消或默认值保存交互验收。
- 用户明确可适当减少自动化；本轮 UI 为主，未加镜像测试、未重跑全量 135 项、Release 或 UI runner。下方全量/Release 通过记录是较早代码，不能当作本轮复测。实际听音、菜单栏/外观、签名沙盒及 M7 待验项保持。

## S1 时长、格式与媒体续验（2026-10-22，较早记录）

- 新增 8 项，完整 135 项逻辑/集成通过，0 失败、0 跳过，退出码 0，56.12 秒。日志 `/tmp/liquidmusic-s1-tests-verified-20261022.log`，结果包 `/tmp/Liquidmusic-build/Logs/Test/Test-Liquidmusic-2026.10.22_20-29-59-+0800.xcresult`。复用已有 GRDB 7.11.1 源缓存，无依赖升级。
- 最终 README Debug/Release 构建均通过、退出码 0；日志 `/tmp/liquidmusic-s1-debug-final-20261022.log` / `/tmp/liquidmusic-s1-release-20261022.log`。Release 二进制经 `lipo -archs` 确认为 x86_64 + arm64，仅有既有 AppIntents 元数据跳过提示；脚本语法、`git diff --check` 通过。
- 1/6/12 秒由真实静音 AVPlayer 自然推进完整重叠时段，验证中点增益、总音量、结束时间、队列仅推进一次及旧播放器释放；不以 seek 提前结束冒充时长通过。
- WAV/M4A 双向切换、短 MP3 切换与两路增益通过。损坏 M4A 不提前打断旧曲，换曲时报告错误且不跳过失败项。tone.flac 元数据预检通过，实际解码报帧数范围错误；新增测试先独立完整播放探测，再验证相同失败路径，本轮不记为 FLAC 交叉播放成功。最初测试误将预检成功当作解码支持而失败，已纠正测试前提，未改播放器。
- 交叉重叠时注入 SystemMediaTransport 验证新条目 ID/速率发布、暂停两路/恢复、定位结束旧曲与退出清理。没有注册真实媒体键，不等于控制中心或硬件通过。
- 定向设置 UI 经 `Scripts/verify-ui.sh` 执行：Debug App 和 runner 构建成功，自动化模式启用超时（64.23 秒），用例未开始，退出码 65；日志 `/tmp/liquidmusic-s1-ui-settings-20261022.log`，结果包 `Test-LiquidmusicUITests-2026.10.22_20-05-04-+0800.xcresult`。显示截屏已恢复；`DevToolsSecurity -status` 报告开发者模式未启用，尚不能证明是超时原因，未更改系统安全设置，也未重复同一失败环境。
- 设置最终四页点击、菜单栏开关、真实外观、1/6/12 秒可听声音及蓝牙/AirPlay、签名沙盒与 M7 人工项仍待验。全部自动音频测试静音，只使用临时合成素材和 bundle 副本，不扫描个人库。

## S1 设置与交叉渐入渐出（2026-10-21 历史）

- Debug 构建通过，退出码 0，最终日志 `/tmp/liquidmusic-settings-build-final.log`。完整 127 项逻辑/集成测试通过，0 失败、退出码 0、23.19 秒，日志 `/tmp/liquidmusic-settings-tests.log`，结果包 `Test-Liquidmusic-2026.10.21_19-31-03-+0800.xcresult` 位于 `/tmp/Liquidmusic-build/Logs/Test/`。最后仅调整设置预览/初始草稿与滑块视觉标签，已重新 Debug 构建。无新增依赖，继续 GRDB 7.11.1，未重跑 Release。
- 新增 7 项 CrossfadeTests 使用临时合成 WAV 和静音 AVPlayer：两路真实 volume 互补、全局音量乘积、暂停音频时间冻结/恢复、自然完成、定位/禁用/快速切换/释放清理、缺失下一首不提前打断、插队替换预备项、重复条目、循环与随机队列恰好提交一次。未注册真实媒体键或扫描用户目录。
- 新增 5 项 SettingsTests：默认值、SQLite 重开恢复并保留索引、草稿不生效/成功保存才应用、启动音量和模式恢复且不自动播放、无关设置不覆盖临时播放模式、无效数值归一化、读取失败禁止保存。原 v1 数据库升级用例扩展覆盖 v3 设置表保存及旧曲目保留。
- 设置播放页浅/深色、通用、文件、高级五个 Preview 已成功渲染并目视检查。620×440 内容尺寸，无截断；红色系统强调色、系统字体、原生滑块/勾选框/Picker、四图标分页；预览只用内存偏好和 LibraryController.preview，不打开真实库、不播放或注册系统媒体。Preview 不证明真实点击、VoiceOver 或菜单栏开关已验收。
- 2026-10-20 中间版桌面操作验证了 ⌘, 打开、取消不保存、确认保存开关/12 秒后重开；后来在切通用页时断言失败，日志有其他窗口遮挡。修正 AXValue 为 NSNumber、补全分页 contentShape/激活及等待。历史批次未完成，不能报告 7 项 UI 全绿。
- 2026-10-21 重新执行 `LIQUIDMUSIC_SOURCE_PACKAGES=... bash Scripts/verify-ui.sh`；App/runner 构建成功，runner 初始化自动化模式超时，**用例尚未开始**，退出码 65。日志 `/tmp/liquidmusic-settings-ui-all.log`；结果包 `Test-LiquidmusicUITests-2026.10.21_19-31-43-+0800.xcresult`。`screencapture` 返回无法从显示创建图片；Xcode 设备交互仅提供 iOS 模拟器，无法修复 macOS 会话，因此未继续无效重试。
- 待验：在有显示的 macOS 会话重跑七项 UI（优先设置四页/保存/取消）；真实音频的 1/6/12 秒交叉听感及 MP3/M4A/FLAC 差异、蓝牙/AirPlay、菜单栏开关、真实外观切换、签名沙盒跨启动和 M7 的其余人工项。默认关闭交叉渐变，单曲循环/手动切歌保持直接切换，不宣称样本级无缝或音量标准化。

## M7 本地文件面板与键盘续验（2026-10-20）

- 新增真实 NSOpenPanel 取消与静音 WAV 导入两项 XCUITest，连同原四项共六项。导入后验证长英文曲名、暂停、专辑/艺术家进入与返回、窄窗播放条和大封面占位面板入口。创建的 120 秒 PCM 音频全零，UI 音量另调为零；只使用 runner 自己的临时目录，不扫描个人音乐。
- 发现点击进度后方向键未推进可见时间，PlaybackProgressView 增加显式焦点、同时识别点击手势与左右键 −5/+5 秒处理，继续调用原 seek。回归先等鼠标定位约 60 秒，再在暂停时验证右键三次 +15 秒、左键一次 −5 秒，避免自然播放/迟到定位造成假通过。
- 文件面板路径框需要全选替换并核对值；macOS 原生音量滑块可能以 NSNumber 返回 AXValue。runner 不能直接写 `/private/tmp`，测试保持在自己的临时目录，不扩大权限。曾中断卡在事件合成的测试；最终用例在真实面板中完成选择，没有添加生产 App 的测试素材入口。
- 本轮前半段六项 UI 全部通过（约 135.8 秒），完整 115 项逻辑/集成通过；环境恢复后缓存丢失，重新构建的 Debug 与 Release 退出码 0，Release 含 arm64/x86_64，完整 115 项测试再次通过（0 失败、约 8.16 秒、退出码 0）。当前日志 `/tmp/liquidmusic-m7-local-ui-all.log`（含 Debug 构建）、`/tmp/liquidmusic-m7-local-release-cached.log`、`/tmp/liquidmusic-m7-local-tests.log`。
- 恢复后的 UI 批次五项通过，首个搜索文本输入因系统事件合成超时失败（批次退出码 65）；单独重试该项通过（退出码 0、约 7.1 秒），未改搜索业务。六项用例均有通过记录，恢复后的整批不是单次全绿。重试日志 `/tmp/liquidmusic-m7-local-ui-search-retry.log`，结果包路径见 HANDOFF。
- 依赖检出停在 SQLiteLib 网络准备后，复用已有干净的 GRDB v7.11.1/SQLiteLib v3.47.2 源缓存，未升级版本。三个构建/测试命令共用已解析 SourcePackages 路径并禁用更新；脚本新增 LIQUIDMUSIC_SOURCE_PACKAGES，可同时传给 App 与 UI runner。脚本语法、实际构建/测试及 diff 空白检查通过。源缓存的本机路径与复现参数见 HANDOFF。
- 六项合成事件不等于人工验收；单文件 UI 在隔离模式仍用无图 reader，只证明大封面占位面板可打开。实际嵌入图片显示、千首持续滚动、物理听音、完整 Tab/VoiceOver、系统外观切换、签名沙盒与硬件媒体仍待验。

## AW3 单文件封面续验（此前记录）

- README Debug 构建退出码 0，日志 `/tmp/liquidmusic-aw3-build.log`；10 项新定向测试通过，`/tmp/liquidmusic-aw3-targeted-tests.log`；完整 115 项逻辑/集成通过，0 失败、退出码 0，约 8.44 秒，`/tmp/liquidmusic-aw3-tests.log`。使用 `/tmp/Liquidmusic-build`，GRDB 7.11.1 未升级，无源码警告，仅原有 AppIntents 元数据跳过提示。
- 真实 MP3 与系统临时导出的嵌入封面 M4A 都验证了缓存路径及图片可解码；无图不解析缓存目录。注入坏图、目录错误/写失败、取消与忽略取消的迟到读取，验证警告不会阻断播放或串到新曲。库内同路径测试确认稳定 ID、标签、旧封面和数据库读回基线未改变，提示通过扫描审阅补齐。
- 单文件新封面与清空通过假 SystemMediaTransport 发布测试，原媒体迟到/注销用例也在完整套件内。真实 AVPlayer 测试全部静音；无真实系统媒体注册，不扫描个人音频目录。测试 M4A 由 AVAssetExportSession 生成，无 FFmpeg 运行依赖。
- AudioImportNotice 400 点浅/深色 Preview 已渲染并目视检查，提示与关闭入口可见，无选择器/数据库/自动播放副作用。
- `bash Scripts/verify-ui.sh` 四项桌面 UI 全部通过，0 失败、退出码 0，日志 `/tmp/liquidmusic-aw3-ui-tests.log`。仍只覆盖空库搜索、边栏恢复、窄窗音量与队列切换，不属于真实单文件选择器、非空封面或硬件操作验收。本轮未重跑 Release。
- 尚需人工验证：真实面板打开测试音频后封面/提示、专辑返回/搜索/长标签、可听播放、签名沙盒跨启动、控制中心/媒体键、Dock/菜单栏/退出与 VoiceOver。AW3 完成代码与自动验证，未把这些待验项记为通过。

## AW2 专辑封面展示续验（2026-10-19 历史）

- Debug 构建与 28 项相关逻辑测试通过，退出码均为 0：7 项加载、9 项选图、12 项查询。日志 `/tmp/liquidmusic-aw2-build.log` / `/tmp/liquidmusic-aw2-tests.log`，使用 `/tmp/Liquidmusic-build`。本轮未重跑全部逻辑测试或 Release。
- 加载测试用合成测试 bundle 图片/内存数据和可控 actor，不扫描音乐目录、不注册媒体键。覆盖缺失/坏图回退、成功后停止、空/全失败清空、次候选变化、generation、取消及离开视图的迟到数据。
- Preview 在 macOS 27.0.1 成功渲染并目视检查：AlbumsView 浅色 760 点宽、深色 360 点宽；LibraryView 400 点宽封面详情；ArtworkView 缺失/坏图后成功回退及无图占位。同名不同艺术家保持独立入口；详情歌曲行仍显示自身图片。SPXArtwork 内存绘图与注入 loader 避免真实目录读取，无自动播放。
- 原有四项桌面 UI 首次运行有两项失败：启动搜索框不存在、窄窗队列按钮不可点击；日志包含 ChatGPT 窗口遮挡。测试启动改为忽略恢复状态、统一拉宽到 1000 点并激活，窄窗音量弹窗关闭后再激活；未改产品搜索/队列行为。复测四项全部通过，0 失败，退出码 0；测试执行约 57.4 秒。首次日志 `/tmp/liquidmusic-aw2-ui-tests.log`，复测 `/tmp/liquidmusic-aw2-ui-repeat.log`；结果包见 HANDOFF。测试为空库，不把它写成非空封面点击/滚动验收。
- 实际千首持续滚动、完整键盘/VoiceOver、真实图片库跨启动、系统媒体与听音仍待人工验收；AW3 单文件封面尚未实现。以下 M7 记录为此前结果。

## 本轮环境与边界

- Xcode 27.1 / Swift 6.4，macOS 27.0.1，arm64 测试宿主；最低部署 macOS 26，未在 macOS 26 真机运行。
- 沿用已解析 GRDB 7.11.1 的 `/tmp/Liquidmusic-m2-verify.Ll36gl`；常规验证带 `-skipPackageUpdates -disableAutomaticPackageResolution`，UI 脚本使用该已有缓存，未升级依赖。
- 自动测试仅使用临时目录、合成音频、测试数据库和虚拟歌曲索引，播放器静音；未扫描个人音乐文件夹。
- 共享 scheme 保持 `shouldUseLaunchSchemeArgsEnv="NO"`、`LIQUIDMUSIC_TESTING=1`；宿主隔离断言通过。Preview 无真实库、媒体键、菜单栏或自动播放。

## 构建和测试

通用命令见 README。本轮日志：

| 验证 | 结果 | 日志 |
|---|---|---|
| Debug build | 通过，退出码 0 | `/tmp/liquidmusic-m7-followup-build.log` |
| Release build | 通过，退出码 0，arm64 + x86_64 | `/tmp/liquidmusic-m7-followup-release.log` |
| Debug XCTest | 89 项通过，0 失败，退出码 0 | `/tmp/liquidmusic-m7-followup-tests.log` |
| macOS XCUITest | 4 项通过，0 失败，退出码 0 | `/tmp/liquidmusic-m7-ui-tests.log` |
| 队列顶对齐后专项回归 | 2 项 UI 再次通过，0 失败，退出码 0 | `/tmp/liquidmusic-m7-ui-layout.log` |

M7 新增两项规模回归，原有 87 项全部保留。构建阶段没有 Swift 源码警告；AppIntents 的无依赖元数据跳过提示不属于源码编译问题。测试中的 linkd/音频系统诊断未导致用例失败。

## 桌面 UI 自动操作（M7 续验）

独立 `LiquidmusicUITests` target 使用 macOS XCUITest 合成键盘与鼠标事件，在实际 App 上验证；不属于人工操作或物理键盘验收。四项覆盖：

- Command-F 后不点击输入框直接输入，再用 Escape 清空。
- 点击系统工具栏隐藏侧边栏，再用 Command-F 展开并恢复可输入的搜索焦点。
- 拖动窗口到 640 点宽，打开音量滑块并用 Escape 关闭；检查播放模式的中文 AXTitle/当前值；打开、关闭窄窗口队列。
- 1000 点宽窗口队列反复开关，队列展开时拖到 640 点，自动收起后可重新打开窄窗口弹出面板。

本轮发现并修复：

1. 折叠期间设置 FocusState 会丢失搜索焦点，改为视图进入后通过可取消 task 聚焦。
2. 没有焦点入口的音量 popover 无法稳定响应 Escape，增加可聚焦容器和原生“完成”取消按钮。
3. 本机系统 inspector 在窄宽切换时触发 AppKit 约束更新异常，改为 SwiftUI 原生水平布局的右侧队列面板；窗口不足 900 点时使用 popover。跨该阈值自动收起队列，播放状态不变。已通过实际拖动回归。
4. 图标菜单的原生辅助功能名称显示为英文“Right”，改用文字“播放模式”，验证 AXTitle 和当前模式值；尚未实际启用 VoiceOver 听读。

使用 `bash Scripts/verify-ui.sh` 复现。脚本先构建 App，再运行 Xcode 自动生成的 `LiquidmusicUITests` scheme；UI runner 使用本地 ad-hoc 签名，避免沿用失效的 Apple 模板签名，不需要开发者证书。`TEST_TARGET_NAME=Liquidmusic` 仅作为命令参数传入（Xcode 工具的设置注册表不接受此键）。这不等于发布签名或沙盒跨进程授权验收。

另用不含 `xcuserdata` 的临时工程副本执行 `xcodebuild -list`，确认仍能识别 `LiquidmusicUITests`，不依赖本机个人 scheme 列表；副本未启动 App、未读取用户库。

测试按 runner 所在构建目录显式指定 App URL，避免同标识的其他构建/Preview 实例；启动环境显式传入 `LIQUIDMUSIC_TESTING=1`。因此不打开真实库、不注册媒体键、不插入菜单栏，不播放音频。运行需要可用的 macOS 图形会话，勿同时操作被测窗口。设备交互工具仅支持其他平台的模拟器，本轮未使用它冒充 macOS 验证。

完整结果与截图附件：`/tmp/Liquidmusic-m2-verify.Ll36gl/Logs/Test/Test-LiquidmusicUITests-2026.10.19_21-21-10-+0800.xcresult`。UI 用例只覆盖空库；非空/长标签/千首真实滚动和播放手势仍待验。

截图复核后将空队列的标题/内容固定在面板顶部，再次运行窄窗口与队列缩放两项回归均通过；结果为 `/tmp/Liquidmusic-m2-verify.Ll36gl/Logs/Test/Test-LiquidmusicUITests-2026.10.19_21-23-51-+0800.xcresult`。

## 界面检查

已渲染并检查：主窗口 1100×680 浅/深色、640×520 窄窗口浅色与深色增加对比度、800×560 空库、深色艺术家列表，以及 1000 首模拟歌曲 Table。

- 主体与播放条使用实际垂直布局，侧边栏页脚不再透入底部玻璃。
- 原生窗口工具栏显式跟随内容区 colorScheme，修复本机普通深色预览中工具栏图标不可见的问题；复核深色宽窗口与浅色窄窗口图标可见，仍使用系统工具栏材质。
- 内容宽度低于 560 点时使用原生紧凑 List，仍显示标题、艺术家、专辑和时长；排序入口位于工具栏。宽布局保留四列表格和列头排序。
- 播放条使用 ViewThatFits，窄布局为两行，音量改从按钮弹出滑块；模式和队列仍在播放条上。
- 右侧队列使用原生布局/List，窄窗口从队列按钮弹出；不再使用本机缩放时会崩溃的系统 inspector。
- 增加对比度时播放条使用语义背景和清晰边框；减少透明度走相同代码分支。后者未通过系统设置实测。
- 控件具有辅助功能标签/值；声波已尊重减少动态效果，队列展开动画也遵循该设置。VoiceOver 实际朗读与系统设置切换未实测。
- Command-F 聚焦输入、恢复隐藏侧边栏焦点与 Escape 清空已通过上述 XCUITest；完整 Tab/Shift-Tab、Slider 方向键与物理操作仍待人工验收。

预览只证明这些尺寸下的静态渲染；没有以此代替悬停、双击、多选、键盘或滚动流畅度验收。

续验重新渲染了少量歌曲的窄窗浅色和宽窗深色。切换 Preview 外观覆盖后，本机浅色画布的工具栏图标出现不可见；实际浅色 XCUITest 截图中图标可见，深色 Preview 也可见。保留系统材质与随 colorScheme 的窗口工具栏设置，真实 App 的浅深色来回切换仍需验收，不用固定颜色掩盖预览与运行环境的差异。

## 合成数据规模记录

`SPXData.largeLibrary` 包含 1000 条虚拟路径、100 张专辑、10 位艺术家。用例验证分组数量、四字段排序查询与精确搜索，同时检查预览快照完整；队列用固定随机种子验证插队顺序、无重复、投影不改变真实队列。

以下为 Debug XCTest 单次观测值，不作为性能承诺或严格计时阈值：

| 操作 | 耗时 |
|---|---|
| 构建 1000 条查询索引 | 16.35 ms |
| 六次查询（全库、四字段维度查询、精确搜索）合计 | 17.15 ms |
| 顺序队列连续插入 20 项 | 13.08 ms |
| 顺序队列投影 1019 个待播条目 | 1.74 ms |
| 随机队列连续插入 20 项 | 9.55 ms |
| 随机队列投影 1019 个待播条目 | 1.73 ms |

计时不含文件扫描、图像解码、SQLite 导入或实际滚动；未测万首以上索引、内存峰值及持续交互帧率。当前测量未发现需要更换架构或增加依赖的理由。

## 待人工验收

建议使用自己明确选择的独立测试文件夹，音频可复制自 `Tests/Fixtures/`；不要对个人音乐库做破坏性实验。以下完整人工场景仍未执行；其中空库搜索/窗口/弹出面板的自动操作子集已验证，见上节。后续逐条记录机器、素材、动作和观察结果。

- [ ] 签名沙盒 App：选择目录、取消、首次导入、重扫审阅的取消/确认、权限失效和重新授权；退出再启动仍可访问。确认前旧索引不变，音频始终只读。
- [ ] 听音：播放/暂停、音量、鼠标拖动/键盘定位、自然结束、快速切歌；拖动过程中切歌不会定位新曲。
- [ ] 浏览：空库/少量/1000 首合成索引的滚动、实时搜索、四字段排序、列头、多选右键插队、双击、悬停、专辑/艺术家往返；窄宽切换后选中项和可见队列顺序正确。
- [ ] 布局：640 点宽、侧边栏折叠、队列展开、全屏及持续拖动调整窗口；长曲名/艺术家/专辑不挤掉控制按钮。
- [ ] 辅助功能：浅/深色切换，减少透明度、减少动态效果、增加对比度；VoiceOver 朗读名称/当前值并执行控件；开启键盘导航后 Tab、Shift-Tab、Command-F、Escape 和 Slider 方向键可用。
- [ ] 四模式：自然结束与手动切换、随机轮次、多次插队、重复歌曲 UUID 跳转；界面、实际声音与队列一致。
- [ ] 真正点击菜单栏与 Dock：红色关窗转最小化且不断音，恢复同一窗口和状态；全屏关窗也可恢复；Command-Q 与菜单栏退出真正结束进程。
- [ ] 物理媒体键/系统控制中心：曲名、封面、速率、进度、暂停/切歌/定位，与主窗口同步；反复恢复窗口不重复注册。

底层播放、媒体命令、窗口代理与 AppKit 程序化关窗已有自动测试；它们不能将以上勾选项自动变成“通过”。
