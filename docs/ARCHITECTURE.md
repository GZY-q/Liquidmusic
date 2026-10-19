# 架构约定

本文区分已实现部分和待人工验收部分。M1–M7 已实现本地播放/索引/浏览/队列、系统集成和体验收尾代码，人工验收尚未完结；验证记录见 HANDOFF 与 VALIDATION。

## 1. 产品边界与布局

第一阶段支持本地 m4a / mp3 / flac / wav / aiff（含 aif 扩展名）。通过 AVFoundation 判断文件实际是否可播放；不能解码的文件跳过并记录，不能仅凭扩展名宣称支持 FLAC。

窗口结构：

- 左侧 Sidebar：搜索、歌曲/专辑/艺术家/播放列表固定入口、所有音乐、导入文件夹。
- 中间 Library：歌曲表格、专辑网格、艺术家列表及维度详情。
- 右侧 Queue：可开关的原生布局面板，窄窗口从播放条按钮弹出。
- 底部 Player：跨内容区域固定的玻璃播放条；封面点击打开大封面面板。

主体使用 `NavigationSplitView`，右侧队列不必永久占用一列。窄窗口可折叠侧边栏/队列，播放控件通过自适应布局保证不截断。允许设置合理的最小可用窗口尺寸。工具栏使用 `.toolbar`，列表使用 `Table`/`List`。系统色彩和材质跟随深浅色与辅助功能设置。

M7 分开布局资料库与底部播放条，避免 sidebar 的安全区内容透入玻璃；窗口最小 640×520。外层 GeometryReader 测量完整窗口，资料库区域用原生 HStack/Divider 并列 NavigationSplitView 与队列；不足 900 点时队列改从按钮弹出，跨阈值自动收起。续验在系统 inspector 的宽窄切换中复现 AppKit 约束更新异常，因此不再使用 inspector。内容区不足 560 点时歌曲切为紧凑 List，选择、主操作、右键菜单与 Table 共用 VM 快照，排序菜单保留。

播放条 ViewThatFits 在横排/两行中选择，窄布局音量放入可聚焦、支持 Escape/“完成”关闭的 popover。模式菜单用原生中文文字标题，避免 AX 名称回退到图标英文名。减少透明度或增加对比度时播放条改为语义不透明背景和边框；减少动态效果停用队列展开动画。Command-F 通过场景 focused value 展开边栏，再由可取消 task 等视图进入后聚焦，Escape 清除搜索/退出焦点；不安装全局键盘事件监听。

## 2. 分层与依赖方向

```mermaid
flowchart TD
    App[App：组合依赖、窗口、命令、菜单栏] --> LibraryVM[LibraryViewModel：窗口查询与导航]
    App --> LibraryController[LibraryController：连接与授权状态]
    LibraryController --> Scope[FolderAccessController actor]
    LibraryController --> Store[LibraryStore actor / GRDB]
    LibraryController --> Scanner[LibraryScanner actor]
    App --> Playback[PlaybackController：M1 已实现]
    LibraryUI[Features/Library + Sidebar] --> LibraryVM
    PlayerUI[Features/Player] --> Playback
    LibraryVM --> Query[LibraryQueryWorker actor：缓存查询]
    Query --> Index[LibraryQueryIndex：纯值过滤、排序、分组]
    Scanner --> Metadata[AudioFileReader actor：共享标签规则]
    Scanner --> Artwork[ArtworkCache actor]
    Scanner --> Store
    Playback --> AVPlayer[AVPlayer]
    Playback --> Queue[PlaybackQueue：纯值状态机]
    Playback --> Media[SystemMediaController：状态/命令/发布策略]
    Media --> Transport[SystemMediaTransport：真实系统或测试替代]
```

`Core/Models` 不依赖 SwiftUI 或 AppKit；数据库适配放在 `Core/Library` 的扩展中。View 不直接操作 SQL、枚举文件或注册远程命令。

AppModel 与 LibraryScanner 共用 AudioFileReader 的校验/标签实现；单文件入口跳过图片提取，扫描读取图片后交给 ArtworkCache。LibraryController 维护连接、授权、扫描状态和已加载的 tracks；AppModel 合并库内歌曲与临时打开歌曲，并按路径去重。ContentView 将 tracks 快照交给窗口内的 LibraryViewModel，后者仅负责查询/分组/导航，不另建扫描、数据库或授权状态。

应用级状态由 LiquidmusicApp 持有 AppModel，唯一主窗口 Window(id: main) 和 MenuBarExtra 注入同一个 PlaybackController。M6 将原 WindowGroup 收敛为唯一主窗口，打开/恢复沿用相同窗口和浏览状态。系统媒体在真实 App 生命周期中幂等注册，Preview 显式注入未连接系统媒体的实例。

建议目录（“计划”表示还未创建对应 Swift 文件）：

```text
Liquidmusic/
  App/
    LiquidmusicApp.swift         场景和生命周期入口
    ContentView.swift            主窗口组合；不承载索引业务
    AppModel.swift               已实现：共享依赖、单文件导入和错误聚合
    WindowLifecycle.swift       已实现：运行隔离、委托桥、窗口恢复与菜单栏组合
  Features/
    Sidebar/SidebarView.swift
    Library/
      LibraryController.swift   已实现：连接、保存/恢复授权、操作状态
      LibraryFoldersView.swift  已实现：文件夹管理、错误与重新授权
      LibraryViewModel.swift    已实现：窗口浏览状态与后台缓存查询
      LibraryView.swift         已实现：状态、内容与维度详情切换
      SongsTable.swift          已实现：原生表格、排序与播放操作
      AlbumsView.swift          已实现：专辑网格
      ArtistsView.swift         已实现：艺术家列表
      ImportProgressView.swift  已实现：扫描进度与导入问题报告
      ScanReviewView.swift      已实现：覆盖/清理前审阅确认
    Player/
      ArtworkView.swift         封面与声波指示
      PlayerBar.swift           播放条、传输控制、大封面
      PlaybackProgressView.swift  已实现：进度编辑与旧滑块回调隔离
      QueueView.swift           队列与 MiniPlayerView
  Core/
    Models/Track.swift          Track、枚举、SPXData
    Models/LibraryQuery.swift   查询索引、比较器、维度标识和结果值类型
    Models/PlaybackScrubState.swift  可测试的拖动/键盘进度编辑状态
    Models/LibraryFolder.swift  LibraryFolder、ImportIssue、授权状态值类型
    Models/LibraryScan.swift    文件指纹、元数据结果、进度、报告和扫描方案
    Playback/
      AudioFileReader.swift     已实现：单文件异步校验/基础标签与临时授权
      PlaybackQueue.swift       已实现：UUID 队列、随机轮次、优先项和访问历史
      PlaybackController.swift  AVPlayer 与可观察状态
      SystemMediaController.swift
      SystemMediaTransport.swift  系统媒体边界、命令与快照值类型
    Library/
      LibraryStore.swift        已实现：GRDB、v1_library 与 v2_fileFingerprint 迁移
      FolderAccessController.swift  已实现：准备/提交/丢弃授权与租约生命周期
      LibraryScanner.swift      已实现：准备方案、去重、校验与提交
      ArtworkCache.swift        已实现：ImageIO 缩略图与有界数据缓存
Tests/                          独立 XCTest target，89 项测试与合成素材/旧数据库快照
LiquidmusicUITests/              独立 macOS XCUITest target，4 项实际 App 合成事件回归
Scripts/verify-ui.sh             构建 App + 本地 ad-hoc UI runner，按构建路径启动隔离 App
```

## 3. 并发与生命周期

- `@MainActor @Observable` 管理 UI 可观察状态、AVPlayer 控制和 AppKit 选择器。
- 扫描、数据库、图像缩略图处理用 actor 隔离，不能在主线程递归枚举或逐个解码封面。
- 先用有限并发（初版串行后台读取也可），禁止为整个音乐库一次性创建无限任务。
- `Track`、扫描进度、导入问题等为 Sendable 值类型；不要跨 actor 传递可变 NSImage 或 AVPlayerItem。
- 扫描任务可取消；换文件夹或新扫描不得让旧任务的结果覆盖新任务。使用任务 ID / generation 校验。
- 播放器按应用生命周期保持唯一，观察者/通知/媒体命令必须有明确清理路径。若后续增加协议，应有实际测试或替换需求，避免空壳抽象。

## 4. 文件访问与持久化

### 用户文件夹授权

`NSOpenPanel` 选择目录 → 创建待提交的 security scope 租约 → 校验可打开根目录 → 创建只读 `.withSecurityScope` 书签 → 持久化 → 提交长期租约 → 自动开始新文件夹扫描。启动恢复只加载已有索引，不自动重新扫描。

LibraryController 只在真实 App start 时打开存储。Preview 不调用 start，Tests 使用显式注入的内存/临时库；共享 scheme 的 TestAction 设置 LIQUIDMUSIC_TESTING=1 且 shouldUseLaunchSchemeArgsEnv=NO。M6 发现并修复了此前继承 Launch 环境导致变量不生效的问题，AppRuntime 另识别标准 XCTest 与 Preview 环境；真实 App 组合在隔离模式下不创建真实库、不启动媒体、不插入菜单栏或连接主窗口桥。

重新启动时恢复书签，处理过期书签；无法恢复时提示重新授权。只保存字符串路径不够。用户授权的根目录访问需要覆盖扫描和之后的播放生命周期，不能扫描结束立即停止访问。每次成功 start 都要有对应 stop，避免重复启动泄漏。核对 App Sandbox 和 app-scoped bookmark entitlement。

文件夹取消选择不是错误。首次启动可以显示引导页，不要求自动弹出侵入式选择器。后续支持添加多个文件夹，避免覆盖现有资料库。

### SQLite

存储目录使用系统 Application Support 下的 Liquidmusic 子目录（沙盒下自然解析到容器），不要写进仓库。通过 GRDB 迁移创建以下概念表，最终列名可随实现统一：

| 表 | 核心字段 | 约束/用途 |
|---|---|---|
| libraryFolder | id, bookmarkData, displayName, lastScanAt | 持久化授权来源 |
| track | id, folderID, path, title, artist, album, albumArtist, duration, discNumber, trackNumber, artworkPath, modifiedAt, fileSize | id 主键，规范化文件路径唯一，folderID 可索引 |
| importIssue | id, folderID, filePath, reason, occurredAt | 记录不支持、损坏、权限和元数据失败 |

LibraryStore 首次插入曲目时生成 UUID；后续按标准化且解析符号链接的路径去重并保留 UUID。单文件临时播放仍以路径为 ID，只有入库后才获得稳定 ID。文件移动先视作旧文件丢失和新文件加入，不实现跨路径移动识别。重复目录选择保留原文件夹 ID；重新授权不能占用另一条已有文件夹记录的位置。

数据库初始化失败向用户暴露，不切换空内存库；迁移不启用自动清库。GRDB 经 SPM 固定为 7.11.1，Package.resolved 随工程维护。默认保存 `Liquidmusic/Library.sqlite` 和同级 `Artwork/`；内存库不创建磁盘目录。

`upsertTracks` 是基础存储接口，测试用于准备索引。真实扫描使用 `applyScan`，同时校验数据库基线、确认状态、外键和有效时长；以事务应用新增/更新/删除、问题记录和完成时间。重叠目录由路径最具体的已注册根目录拥有，与扫描先后顺序无关。M3 的 v2 迁移仅新增可空 fileSize 列；旧索引保留，首次重扫读取一次以补齐指纹。

恢复时刷新过期书签；无法恢复的记录保留并标记“需要重新授权”。书签准备、写库、提交授权分开执行，数据库失败会丢弃新租约，已有播放所依赖的租约保持有效。根目录租约覆盖应用生命周期，扫描完成不能调用 release/shutdown。用户索引清理仅通过确认后的扫描方案执行，不提供任意批量删除或音频文件删除入口。

### 索引流程

1. 恢复访问权限，检查路径存在。
2. 后台递归枚举允许扩展名；跳过隐藏文件、包、目录符号链接，防止循环。
3. 发布“正在查找文件”状态；枚举完成后发布总数，再显示确定进度。
4. 比较文件修改时间与大小，对未变化文件复用索引；封面缓存丢失时重新提取。AVURLAsset 异步读取时长、可播放性和 metadata。
5. 标签缺失时标题回退文件名，艺术家/专辑用本地化占位，albumArtist 回退 artist。无效时长不进入正常可播放记录。
6. 单文件失败加入方案的问题列表并继续；序列读取，约每 100ms 更新进度。读取期间不修改现有索引，取消可直接丢弃方案。
7. 完整枚举且未取消时才计算失踪索引。纯新增方案自动保存；包含更新/移除的方案先展示路径与字段变化，用户确认后才提交。枚举不完整时绝不清理旧索引。
8. 提交前再校验目录访问、文件指纹、失踪文件是否重现和数据库基线；不匹配则要求重新扫描，避免陈旧方案覆盖后续修改。
9. 以单个事务写入当前根目录的整批变更，完成后刷新 tracks 和报告。每个根目录独立提交；取消后续目录不撤销之前已经完成的导入。

### 封面

metadata 图片通过 ImageIO 下采样为最长边 512 的 JPEG，写入 Application Support/Artwork。缓存按 SHA-256 + 尺寸版本命名，只新增，不覆盖旧文件；相同图片复用已有文件。原图数据超过 20MB 或超大像素面积会跳过并报告，音频仍可入库。ArtworkView 通过独立 actor 按需读取小图，NSCache 最多 160 项/32MB，NSImage 只在 UI 侧创建。取消扫描可能留下未引用的缓存文件，暂不自动删除。

ScanReviewView 的 List 行使用显式 ZStack 容器稳定行结构，规避本机 Xcode Preview 的自定义不透明列表行崩溃；浅/深色预览均已验证。不要仅为去掉容器而回退该结构，除非重新验证预览和真实窗口。

## 5. 浏览行为（M4 已实现）

搜索实时匹配标题、艺术家和专辑，大小写/变音符号不敏感；中文直接做子串匹配，暂不做拼音检索。LibraryQueryWorker actor 缓存规范化后的字段，120ms debounce 合并连续输入；筛选、排序、分组均在后台执行。任务取消与 generation 校验共同拒绝迟到结果。View body 不执行全库过滤。

歌曲 `Table` 与排序菜单共享 TrackSort 比较器，提供标题、艺术家、专辑、时长的升/降序，时长按秒排序。相等值按标题和稳定 ID 排序，支持 Table 多比较器顺序。专辑使用结构化 AlbumIdentity(album, albumArtist) 分组，既区分同名专辑，也避免标签中分隔符碰撞；艺术家按 track.artist 分组。分组数量基于搜索匹配歌曲，点入维度保留搜索与排序，返回恢复分类；切换侧边栏入口清除维度。

双击歌曲以**当前可见、已排序列表**创建播放队列。悬停显示行内播放按钮；当前曲目显示可暂停的声波；右键提供“播放”和“下一首播放”。播放列表入口仅显示固定“所有音乐”，不显示不能用的新增/编辑控件。

LibraryViewModel.play 接收选中 ID，在已展示的 result.tracks 中查找并传递同一快照给播放器；过时 ID 无操作。多选“下一首播放”保留可见顺序，空队列从所选歌曲的首项开始。该入口复用 M5 的纯队列状态机。

每个窗口独立保存 section/query/scope/sort，共享应用播放器和源数据。Sidebar 的歌曲与所有音乐使用不同 tag。LibraryView 区分首次导入、读取/导入中、读取失败、空文件夹、搜索无结果和分类已失效；后台刷新期间保留现有结果并显示进度。Preview 同步注入 SPXData 查询快照，不打开真实库；初始化配置完成前不触发 Observation didSet 查询，防止空查询覆盖预览结果。

## 6. 播放语义（M5 已实现）

| 操作/模式 | 约定 |
|---|---|
| 顺序自然结束 | 播完末尾停止，保留当前曲目，不自动回第一首 |
| 列表循环 | 末尾回第一首 |
| 单曲循环 | 自然结束重播；手动下一首仍前进，末尾停止 |
| 随机 | 当前一轮候选耗尽前不重复；下一轮重新洗牌，避免立即重复（只有一首除外） |
| 上一首 | 进度超过 3 秒回到曲首；否则回播放历史/上一首 |
| 下一首播放 | 插到当前条目后，多个插入按最新的优先；随机模式下也优先处理 |
| 单曲循环 + 插队 | 自然结束仍重复当前曲；手动下一首才消费插队 |
| 空队列插队 | 直接开始播放该曲 |
| 手动选曲 | 替换队列并从选中歌曲开始，清空旧随机历史 |
| 同一歌曲多次出现 | 用 QueueEntry UUID 区分，不能用 Track.id 作为条目唯一键 |
| 解码/文件访问失败 | 暂停并显示可操作错误，允许跳过或重新授权；不要无限自动跳过重试 |

PlaybackQueue 的候选、优先项和历史全部使用 QueueEntry UUID，下标映射仅用于访问原列表。相同 Track 可有多个独立条目，随机不重复的单位也是条目；显式重复加入歌曲仍会各播放一次。replace 重建条目与历史但保留模式；找不到指定起点时从第一项开始，空列表保持空。

随机源为可注入 seed 的值类型。初始轮把当前项视作已播；后续每轮包含全部条目，只调整首项以避免紧接上一轮末曲。插队不重建本轮候选，消费或跳转优先项时同时移除其候选/优先身份。线性尾部跳过本轮已经消费的插入项，避免从另一个优先项跳回它时重复播放；列表循环的新轮恢复完整列表。

上一首优先使用真实访问历史，随机且无历史时不按物理下标伪造上一首。回退后的下一首沿前进分支重走，再恢复待播安排；新插队、手动跳转或切换模式清除该分支。模式切换保留已播历史与待插队项，重新进入随机时开启以当前曲为起点的新轮；重复设置相同模式不重洗。已播历史保留最近 200 次访问。

QueueView 从纯队列快照显示当前、接下来和历史；upcomingEntries 在副本中模拟本轮手动下一首，不推进真实随机源或无限展开循环。单曲循环显示手动切换顺序并提示自动重复。访问行使用位置区分同一条目的多次出现，跳转仍使用条目 UUID。List 的自定义行保留显式 ZStack，已验证可避开本机 Preview 的原生列表崩溃。

PlaybackScrubState 只保存拖动期间的临时位置，释放后返回 seek 目标；无编辑手势的写入立即触发键盘/辅助功能 seek。PlaybackProgressView 绑定当前条目 ID，切歌重建 Slider 并拒绝旧闭包回调。M1 的 seekID/loadGeneration 继续保护 AVPlayer completion 和旧 item 通知；结束处理额外忽略 failed/ended 状态。循环、跳转与回退有真实 AVPlayer 静音集成测试，真实鼠标/键盘滑块手势和听音仍需人工验证。

第一阶段尚未持久化音量/模式或整个队列，启动不自动播放；这些偏好可后续单独添加。

## 7. 系统集成（M6 已实现，端到端人工验收待补）

SystemMediaController 从同一播放器生成 NowPlayingSnapshot 和命令可用性，SystemMediaTransport 负责真实 MediaPlayer API 或测试记录。play/pause/toggle/next/previous/seek 同步到主线程检查并执行后返回状态；空内容返回 noSuchContent，失败/无效 seek 返回 commandFailed。播放与暂停命令幂等，前后切换按队列可行动性启用。注册一次，shutdown 只移除本实例 token、禁用命令并清空信息；迟到回调不能操作已终止的控制器。

Now Playing 包含标题/艺术家/专辑/封面/时长/进度/速率。静态字典仅标签或曲目变化时重建，封面对象按图片身份复用。状态/定位/封面完成立即发布，播放中最多每 5 秒定期校准，依赖系统按速率外推进度（本机 SDK MPNowPlayingInfoCenter.h 明确不建议频繁更新）。封面通过 ArtworkCache actor 异步读取；取消、路径检查和 shutdown 状态拒绝迟到结果，同一封面路径可跨条目复用。

MenuBarExtra 使用 window 样式的 MiniPlayerView，复用主播放器，显示曲目、状态、基础控制、恢复主窗口和真正退出。按钮回调注入，Preview 的恢复/退出均为空操作。主窗口关闭由 WindowLifecycleBridge 安装的代理转为 miniaturize；代理尊重原委托否决并转发其他可选方法，拆卸时只在仍拥有 delegate 时恢复原值。窗口配置后下一次主线程调度再核对原委托，避免覆盖 SwiftUI 的初始设置。全屏先退出后最小化，恢复操作取消待最小化。

WindowLifecycleController 只弱持有主窗口；Dock reopen 与菜单栏均恢复同一窗口，找不到窗口时允许 SwiftUI 默认重开/openWindow(main)。App delegate 的 shouldTerminate 标记退出状态并返回 terminateNow，允许正常终止，AppModel 的原有 willTerminate 清理保持不变。关闭/最小化不调用播放器 shutdown。真实 NSHostingController + AppKit performClose/恢复已有自动测试；实际 Dock/菜单栏点击、Command-Q、媒体键和控制中心显示仍待人工验收，不能由测试替代传输层或编译推断成功。

## 8. 参考

- [Apple：glassEffect(_:in:)](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:))
- [GRDB 官方仓库](https://github.com/groue/GRDB.swift)
- [Apple：Security-scoped bookmark entitlement](https://developer.apple.com/documentation/professional-video-applications/enabling-security-scoped-bookmark-and-url-access)
- [Apple：ImageIO 缩略图 API](https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:))
- [Apple：远程命令注册与移除](https://developer.apple.com/documentation/mediaplayer/mpremotecommand/addtarget(handler:))
- [Apple：windowShouldClose](https://developer.apple.com/documentation/appkit/nswindowdelegate/windowshouldclose(_:))

实现时优先以本机 SDK 声明和实际编译为准，文档中的候选类型名不是可直接复制的完整实现。
