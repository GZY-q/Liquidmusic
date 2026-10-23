# 专辑封面扩展交接（AW）

日期：2026-10-20。**AW1–AW3 代码已实现：稳定选图、专辑展示/回退、单文件嵌入封面与非阻断提示已接通。** AW3 完成时 Debug、完整 115 项逻辑/集成与 4 项桌面 UI 通过。后续 M7 已扩展到 6 项 UI，并修复进度键盘焦点；最新 Debug/Release、重试与人工待验边界以 HANDOFF/VALIDATION 为准，M7 人工验收仍未完成。

## 1. 范围与已有能力

本次按第一阶段本地音乐范围规划：让已有嵌入封面在专辑浏览中稳定显示，并补齐单文件入口。不是从零搭建图片缓存。

| 位置 | 当前行为 | 后续工作 |
|---|---|---|
| `Core/Playback/AudioFileReader.swift` | 普通 read 无图；真实 App 显式注入 ArtworkAudioFileReader，复用 readMetadata/原缓存 | AW3 已接单文件入口 |
| `Core/Library/ArtworkCache.swift` | 512 像素 JPEG、内容哈希、只新增、有界内存缓存 | 复用；图片损坏/文件缺失回退测试 |
| `Core/Library/LibraryScanner.swift` | 扫描写缓存路径，已有索引更新必须审阅 | 保持 prepare/commit，不另写扫描器 |
| `Core/Models/LibraryQuery.swift` | AW1 已增加独立的完整专辑候选列表；代表曲仍是过滤/排序后第一首 | AW2 已接候选 |
| `Features/Library/AlbumsView.swift` | AW2 已消费完整候选，不依赖代表曲是否有图 | 保留稳定选择规则 |
| `Features/Library/LibraryView.swift` | AW2 非空专辑详情新增紧凑 AlbumHeaderView | 空态/原导航保留 |
| `Features/Player/ArtworkView.swift` | AW2 支持完整路径数组、回退与旧单曲调用 | ArtworkLoadingState 管理取消与代次 |
| `Core/Playback/SystemMediaController.swift` | 已异步加载当前曲目封面，已有迟到结果防护 | AW3 新路径/清空与原迟到回归通过，真实控制中心待验 |

本批不规划联网搜图、账号、手动替换/移除封面、修改音频标签、同目录 cover.jpg/folder.jpg 自动发现、原图/多尺寸缓存或缓存清理。它们需要另立任务，尤其同目录图片涉及单文件授权边界和独立指纹，不可顺手加进扫描器。图标素材 `Design/IconComposer/` 与专辑封面无关，不能拿来充当用户封面。

## 2. 已搭好的契约与依赖方向

新增 `Liquidmusic/Core/Models/AlbumArtwork.swift`：

- `AlbumArtworkCandidate(trackID:cachePath:)`：Sendable/Hashable 纯值；路径存在不等于图片有效。
- `AlbumArtworkSelecting.candidates(for:tracks:) throws`：纯选择契约；AlbumArtworkSelector 已实现并由 LibraryQueryIndex 初始化时调用。throws 用于响应取消，空候选是合法结果。

AW1 实际结果字段为 `LibraryAlbum.artworkCandidates` 与 `LibraryQueryResult.albumArtworkCandidates`。后者只在专辑 scope 且至少有一首匹配歌曲时提供完整候选；搜索无结果、专辑已失效和其他 scope 为空。LibraryAlbum 旧构造调用可省略候选，默认空数组。已有 worker 只在源 tracks 变化时重建索引，因此搜索/排序复用候选；没有新增 UI 调度或 I/O。

不放 `fatalError`、返回空列表的假实现或不可用按钮。文件自动进入 App 的同步编译目录；不需要修改 pbxproj、依赖、数据库迁移或权限。

数据流（已实现）：

```text
全量 Track 快照 → LibraryQueryIndex 按 AlbumIdentity 分组
               → AlbumArtworkSelector（纯值候选顺序，每次源变更预计算）
               → LibraryQueryResult / LibraryAlbum（纯值候选）
               → ArtworkView 的可取消加载任务
               → ArtworkCache actor → Data → MainActor NSImage → SwiftUI

单文件选择 → 既有 AppModel 导入任务与授权
           → 带封面的 AudioFileReading 适配器（AW3）
           → AudioFileReader.readMetadata + ArtworkCache.store → Track
           → 既有播放器 / 队列 / 菜单栏 / 系统媒体
```

只引入这一处纯选择协议。图像读取可用与 SystemMediaController 相同形状的 `@Sendable (String) async -> Data?` 注入闭包，测试返回内存图片，不再增加通用图片仓库或第二个全局缓存。

## 3. 确定的选图与展示规则

1. 专辑标识严格复用 `AlbumIdentity(album, albumArtist)`。不使用 `Track.albumKey` 的分隔符字符串，不改变现有分组大小写规则，也不按歌曲 artist 拆散合辑。
2. 每次源 Track 快照变更时，在后台索引内对完整专辑预计算候选；搜索、标题排序、艺术家 scope 不能重新用可见首曲选封面。专辑歌曲数量仍是当前搜索命中的数量，播放队列仍来自可见排序快照。
3. 只接受该 AlbumIdentity 的曲目。去掉 nil/空白路径，保留非空路径的原始字符串（路径本身可以含空格）。按正数 discNumber、正数 trackNumber、稳定 Track.id 升序；非正编号作为未知排在正编号后，不用随机数或本地化标题打破同值。相同 cachePath 只保留排序后的首项。
4. 图片可能被移走或损坏，展示层按候选顺序尝试，首张可解码图片胜出；全部失败显示现有语义色音符占位。每次新请求先清空旧图片；取消或代次不匹配的结果不能覆盖新专辑。不要在 View body 同步访问文件。
5. 专辑网格与专辑详情使用同一候选列表。详情无搜索结果时沿用现有空态，不强行显示过时专辑信息。页头在窄窗保持紧凑，不改变歌曲选择、返回和播放行为。
6. 歌曲行、队列、播放条、大封面、菜单栏及 Now Playing 继续显示**当前曲目自身**的嵌入封面；本批不把同专辑其他曲目的封面写入 Track。不同曲目自带不同图片时允许与专辑入口不同，避免错误关联与无意义索引覆盖。
7. 保留现有 512 像素缓存和尺寸/数据上限。缓存损坏可回退另一候选；本批不自动修复同哈希坏文件、不清理缓存。后续若要修复，另建审阅/版本方案，不能覆盖当前文件。

## 4. 分步实施卡（每次只做一项）

### AW1：纯选图与查询结果（已实现并验证）

最小阅读：本文件、`AlbumArtwork.swift`、`LibraryQuery.swift`、`LibraryViewModel.swift`、`Tests/LibraryQueryTests.swift`。

实施：

- 在同一模型文件实现 `AlbumArtworkSelector: AlbumArtworkSelecting`，不做 I/O。
- LibraryQueryIndex 初始化时先分组，缓存 `[AlbumIdentity: [AlbumArtworkCandidate]]`；避免每个专辑重扫全库产生平方复杂度。传给 selector 的 tracks 为该组完整成员。
- LibraryAlbum 新增 `artworkCandidates`，保留 representative 的现有含义与调用兼容；LibraryQueryResult 增加供专辑 scope 详情使用的候选字段（建议 `albumArtworkCandidates`）。只从同一次索引快照赋值，普通 scope 为空。
- 暂不接 UI，不改 Track、数据库或播放器。Preview 继续同步模拟查询，不读图、不建库。

验收测试放 `Tests/AlbumArtworkTests.swift`（独立测试目录）：首曲无图而后曲有图；多个封面的碟号/曲号/ID 顺序；编号未知；空白路径/重复路径；同名不同专辑艺术家与合辑；输入打乱后结果稳定；取消；搜索过滤掉有图曲目后专辑候选仍不变；四字段正反排序不改变候选；换源快照清掉旧候选；原歌曲数量和播放顺序保持。补 1000 首合成数据回归，不扫描真实音乐库。

完成标准：README Debug 构建、原查询与新选择测试通过；更新 HANDOFF，下一项写 AW2。这里不宣称封面 UI 已完成。

### AW2：专辑网格、详情和图片加载回退（已实现并验证）

依赖 AW1。阅读 ArtworkView、AlbumsView、LibraryView、LibraryQueryResult 的最终结构。

- ArtworkView 保留 `track:size:` 调用兼容，增加接受候选路径的入口；单曲调用转换为零或一个路径。内部加载逻辑共用，不复制图片视图。
- 提取可测的可取消加载状态（MainActor），或同等可注入实现。图片 I/O 留在现有 actor；每次任务按**完整候选路径数组**标识，不能只按首路径或 album title 标识。测试用受控异步 loader 验证迟到回调和第二候选成功。
- 网格读取 LibraryAlbum 候选；详情从查询结果读取同源候选，增加封面/专辑名/专辑艺术家页头。空态、窄窗、键盘返回保持可用，使用系统字体/语义色。
- 添加有图、无图、坏图回退、同名专辑、窄窗、浅深色 Preview。通过注入内存图/测试 bundle 资源展示封面，不能依赖真实 Application Support 或 `/preview/*.jpg` 文件；不生成或写入预览缓存。

验收：缺失首图/坏图会尝试下一张；慢请求 A 晚于 B 返回不能串图；取消/离开视图后不发布；排序/搜索不闪换封面；1000 首模拟索引滚动无同步磁盘读取；列表/队列单曲图入口不退化。跑 Debug、新加载测试与现有查询测试；Preview 记录与真实交互分别报告。改到窗口/队列布局时运行既有 UI 回归，不恢复 inspector。

### AW3：单文件导入封面贯通（已实现并验证）

实际文件为 `Core/Playback/ArtworkAudioFileReader.swift`、`Core/Models/AudioFileReadResult.swift`、`Core/Library/LibraryPaths.swift` 与 `Features/Library/AudioImportNotice.swift`。AudioFileReading 增加带默认实现的 readResult，兼容已有读取器与测试替身。AppModel 使用本次结果中的 warnings，不读取共享可变警告状态；新选择/取消清空，可手动关闭。适配器无图片不解析目录，图片错误回退，取消传播；共享路径解析只在 I/O actor 调用，不为单文件开启数据库。库内同路径仍选持久化记录，新发现封面且旧记录无图时提示重扫审阅。

依赖 AW2。阅读 AppModel、AudioFileReader、AudioFileAccess、ArtworkCache、LibraryStore.artworkDirectory、LibraryController、AppRuntime、SystemMediaController 及相关测试。

- 优先添加小型 actor 适配器（建议 `ArtworkAudioFileReader`）实现现有 AudioFileReading，组合 AudioMetadataReading 与 ArtworkCache；避免修改所有测试替身的协议。调用一次 readMetadata，缓存成功后返回带 artworkPath 的 Track。
- 真实 App 组合层显式注入有缓存目录的适配器。复用 Application Support/Liquidmusic/Artwork 的定位逻辑，文件操作在 actor；不要为单文件临时播放打开数据库。不要把会访问真实目录的适配器放进 AppModel/Preview 默认参数。
- 旧 AudioFileReader.read 的无图路径可保留为测试/预览默认。测试注入临时 cache；缺图和坏图仍允许播放，图片警告走可见的非阻断提示而非把音频标记失败；取消必须继续抛出，不吞进图片失败回退。
- AppModel 现有导入任务持有 AudioFileAccess，直到读取/缓存完成后才交接给播放器；generation 和取消检查继续覆盖整个阶段。
- **已入库同路径例外**：AppModel 当前优先选择 library.tracks 中的持久化 Track。保持该规则，不以单文件打开绕过扫描审阅覆盖旧索引；若持久化记录没有封面，提示通过音乐文件夹重扫审阅补齐。新临时文件的封面应自然进入所有当前曲目展示与 Now Playing。
- 不为封面刷新重新创建 AVPlayer、替换队列或改变当前进度。临时曲目仍不入库；缓存残留沿用现有策略。

验收：临时 MP3/M4A 嵌入封面能产出路径；无图、坏图、缓存写失败均可播放并按需提示；取消/快速重选不串图或自动播放旧结果；库内同路径不静默覆盖；Now Playing 使用假 SystemMediaTransport 验证新路径、清空和迟到结果。所有实际 AVPlayer 用例静音。运行 Debug 和相关导入/扫描/媒体测试；收尾执行完整逻辑测试与必要 UI 回归。真实控制中心、听音、签名沙盒仍分开验收。

## 5. 验证边界与交接提示词

2026-10-20 AW3 验证：README Debug 构建、完整 115 项测试及 4 项桌面 UI 回归均退出码 0、0 失败。新增 ArtworkAudioFileReaderTests 十项覆盖临时 MP3/嵌入封面 M4A、无图不触碰缓存、坏图静音播放、目录/写入失败、取消及迟到数据、快速重选、旧曲与提示状态、库内同路径索引保护和替代系统媒体的封面/清空。M4A 由系统 AVAssetExportSession 在临时目录生成，不需要 FFmpeg。日志 `/tmp/liquidmusic-aw3-build.log`、`/tmp/liquidmusic-aw3-targeted-tests.log`、`/tmp/liquidmusic-aw3-tests.log`、`/tmp/liquidmusic-aw3-ui-tests.log`；derivedDataPath 使用 `/tmp/Liquidmusic-build`。提示条 400 点浅/深色 Preview 已目视检查。本轮未重跑 Release。

AW2 的 28 项相关测试与网格浅/深色、窄窗详情、坏图回退/占位预览为此前记录，其逻辑用例已纳入本轮完整套件。四项桌面 UI 仍只覆盖空库搜索/音量/队列，不代表真实单文件选择器、非空封面点击、千首持续滚动、VoiceOver、听音、真实沙盒或控制中心已验收。

交给下一个模型可直接复制：

> 阅读 AGENTS.md、docs/HANDOFF.md、docs/VALIDATION.md 与 ALBUM_ARTWORK。AW1–AW3 代码已完成，Debug、115 项逻辑/集成与 4 项桌面 UI 通过，不重复实现封面。继续 M7 剩余人工验收，优先用明确选择的独立测试音频检查单文件封面、专辑搜索/详情/返回、非阻断警告和库内同路径重扫审阅提示，再验实际听音、签名沙盒与系统媒体。使用临时或合成素材，不扫描个人音乐目录，不修改音频或绕过索引确认；无法实测就明确记录。只针对发现的问题修复并运行必要检查，不扩展联网封面、手工编辑或第二阶段，不提交/推送。
