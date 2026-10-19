# 接手说明

更新日期：2026-10-19（Asia/Shanghai）。当前里程碑：**M7 续验已修复搜索焦点、音量弹窗和队列缩放问题，Debug/Release、89 项逻辑/集成测试与 4 项桌面 UI 测试通过**。队列顶对齐后两项 UI 专项复核也通过。第一阶段人工验收仍未完结，尤其是听音、VoiceOver/完整键盘导航、硬件媒体键、控制中心、真实 Dock/菜单栏点击、Command-Q 与签名沙盒。下一项：**M7 剩余人工验收**，参阅 `docs/VALIDATION.md`。

## 用户最新意图

2026-10-17 完成规划与骨架交接后，用户在 2026-10-18 明确要求继续开发。M7 代码收尾后，本轮通过 macOS 原生 XCUITest 补验实际 App 的搜索/窗口/队列交互，并修复发现的问题；不扩展第二阶段功能。

## 当前实际状态

| 范围 | 现状 | 验证程度 |
|---|---|---|
| 工程 | 原生 Xcode，Swift 6，macOS 26，显式 MainActor UI / nonisolated 默认隔离 | Debug/Release 构建退出码均为 0；Release 含 arm64/x86_64 |
| 应用状态 | App 持有唯一 AppModel / PlaybackController，唯一主窗口与菜单栏复用 | 构建/预览通过；真实主窗口与菜单栏联动待人工验收 |
| 单文件入口 | 工具栏、侧边栏、空状态与 Command-O 统一打开音频文件；非阻塞选择面板 | 导入流程自动测试；真实选择器交互未验收 |
| 异步读取 | 单文件/扫描共用 AudioFileReader；基础标签、albumArtist、曲号/碟号、嵌入封面、文件指纹 | MP3 ID3 与 M4A iTunes 标签测试通过；缺失标签/坏文件有回退或报告 |
| 导入状态 | 显示读取进度和取消；只接受最新选择，失败保留旧曲目 | 过时任务、取消与失败回退测试通过 |
| 文件访问 | 单文件临时 scope；文件夹只读书签、过期刷新、长期根目录租约 | 可控客户端的恢复/失败/释放测试通过，真实签名沙盒待验收 |
| 播放 | AVPlayer，独立状态、旧回调/seek completion 隔离；循环、跳转、历史和拖动编辑 | 真实 AVPlayer 静音循环/回退/重复条目集成测试及纯进度状态测试通过；物理手势与听音待验收 |
| 界面 | 原生 Table/紧凑 List、专辑网格、艺术家/详情、所有音乐；独立玻璃播放条、右侧队列面板/窄窗 popover、大封面 | 原有预览已检查；空库宽窄队列开关/拖动与音量弹窗通过 XCUITest，其余交互待验 |
| 辅助功能 | 中文模式菜单 AXTitle/值、减少动态动画、透明度/对比度回退、Command-F 与 Escape | 搜索输入/清空、隐藏边栏后恢复焦点、音量 Escape 与模式名称/值通过 UI 自动操作；VoiceOver/完整导航待验 |
| 查询 | 后台缓存标签索引，120ms 搜索 debounce、四字段升降序、稳定次级键与结构化专辑标识 | 搜索/排序/分组、过时查询、清除/导航和可见队列顺序测试通过 |
| 生命周期 | 关窗转为最小化，委托转发/还原；Dock/菜单栏恢复同一窗口，退出标记后正常终止 | 真实 NSHostingController + AppKit 桥的程序化关闭/恢复测试通过；物理点击和实际 Command-Q 待验收 |
| 系统媒体 | 按状态启用并执行六种命令；静态元数据/封面复用、5 秒普通进度校准、异步封面 | 替代传输层测试通过（不注册真实系统媒体键）；硬件/控制中心待人工验收 |
| 队列 | UUID 候选/优先项/历史，顺序/循环/随机轮次；当前/接下来/历史分区，重复条目精确跳转 | 18 项纯队列测试通过（含规模回归）；浅/深色及随机/空队列预览渲染成功 |
| 资料库 | GRDB v1/v2 迁移；后台递归扫描、增量复用、进度/取消/报告、确认后更新与失踪索引清理；M4 浏览消费已载入 tracks | 旧库升级、真实格式素材、重扫/取消/确认/陈旧方案及查询测试通过 |
| 封面 | ImageIO 最长边 512 JPEG，内容哈希文件复用；actor + 有界 NSCache 异步读图 | 嵌入封面、下采样、去重、坏图不影响音频导入测试通过 |
| 菜单栏 | MenuBarExtra window 样式，当前曲目/状态/基础控制、恢复与退出 | 浅/深色 Preview 已检查；实际状态项点击待人工验收 |
| 测试 | 独立逻辑测试与桌面 UI target；UI 按构建路径启动，显式隔离真实库/媒体/菜单栏/窗口桥 | 89 项逻辑/集成 + 4 项 UI 通过；共享主 scheme 隔离设置保持不变 |

GRDB 7.11.1 经 SPM 接入并锁定。真实 App 添加文件夹后自动扫描；已有目录可在“音乐文件夹”点击扫描。启动恢复已有索引，不重扫。M1–M7 功能与体验收尾代码已接通，不能据此宣称全部用户场景验收完成。

## 最值得先读的代码

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
- `LiquidmusicUITests/LiquidmusicUITests.swift` / `Scripts/verify-ui.sh`：四项 macOS 桌面事件回归与构建/启动脚本，独立于主 scheme 的 89 项测试。

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
- AudioFixture 在测试 target 内共享，所有真实播放集成测试使用生成 WAV 且音量为零。没有挂载菜单栏、修改媒体注册或关窗生命周期；音量/模式/队列仍未持久化，启动不自动播放。

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

## 下一项：M7 剩余人工验收

可直接复制：

> 阅读 AGENTS.md、docs/HANDOFF.md、docs/VALIDATION.md 与 ROADMAP 的 M7。89 项逻辑/集成与 4 项桌面 UI 测试已通过，人工验收尚未完结。空库搜索、隐藏边栏恢复、音量 Escape 和队列宽窄开关已有回归，不必重复实现；UI 用 bash Scripts/verify-ui.sh，显式按构建目录启动隔离 App，不要恢复旧 inspector。继续 VALIDATION 待验清单，优先非空/长标签、千首模拟索引滚动、Slider 键盘和 VoiceOver/辅助功能设置，再验可听播放、签名沙盒、物理媒体键/控制中心、Dock/菜单栏恢复及 Command-Q。使用明确选择的独立测试目录，不扫描个人音乐库，不修改音频。只针对实际发现的问题修复并运行相关检查，保留 TestAction 的 shouldUseLaunchSchemeArgsEnv=NO 和 AppRuntime 隔离，不扩展第二阶段。无法实测时明确说明，不把编译/替代媒体/程序化窗口或桌面自动操作写成人工通过。不提交/推送。
