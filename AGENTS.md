# Liquidmusic — 后续代理工作约定

默认使用简体中文；安装依赖时优先考虑中国大陆镜像；修改代码之前先读取相关文件；执行删除、覆盖或其他不可逆操作之前，必须先展示具体方案并等待确认。

## 开始前

- 先读 `docs/HANDOFF.md`，再读本次任务对应的 `docs/ROADMAP.md` 条目；架构以 `docs/ARCHITECTURE.md` 为准。
- 当前已实现 M1–M7 的代码，M7 人工验收尚未完结，具体状态以 HANDOFF/VALIDATION 为准。不要把“已有代码”或“编译通过”视为“已经完成人工运行验收”。
- 2026-10-17 曾收敛为规划与交接，用户在 2026-10-18 已明确继续开发。收到任务后执行对应里程碑，不要因读到路线图就自动实现所有待办。
- 默认一次完成一个里程碑。不要自行委派子代理；没有必要为了小任务更换架构、引入其他依赖。
- 先检查 `git status`，保留用户修改；未经要求不提交、推送或发布。

## 工程约束

- Swift 6 + SwiftUI，最低 macOS 26，原生 macOS App；MVVM 分层：App / Features / Core。
- 全局默认隔离为 nonisolated；UI 状态与播放器显式 `@MainActor`，I/O 与扫描用独立 actor，跨 actor 数据用 Sendable 值类型。
- 第一阶段音频使用 AVPlayer；AVAudioEngine 是后续扩展点，不要提前创建无效引擎或接入均衡器。
- 持久化指定 GRDB / SQLite，已通过 SPM 固定为 7.11.1；维护工程中的 Package.resolved，不无故升级依赖。
- 必须使用系统字体样式、语义颜色、原生布局与交互；禁止硬编码字号和 hex 颜色。尺寸、间距可使用布局常量。
- Liquid Glass 采用系统 API；侧边栏和工具栏优先使用系统提供的材质，不要层层叠加玻璃。
- 每个 Feature 提供 `#Preview`，使用 `SPXData` 或等效 mock；预览不得注册媒体键、打开选择器、创建真实数据库或自动播放。
- 代码注释用中文。模型与 SwiftUI 分离，业务逻辑可以单测。
- 不实现流媒体、账号、歌词、均衡器、频谱或播放列表编辑。
- 不遍历用户真实音乐文件夹做测试，不擅自移动/删除用户音频。使用临时测试文件与数据库。
- 保持共享 scheme 的 TestAction `shouldUseLaunchSchemeArgsEnv="NO"` 与 `LIQUIDMUSIC_TESTING=1`；AppRuntime 对 XCTest/Preview 禁用真实库、菜单栏、窗口挂钩与媒体注册。媒体测试注入 SystemMediaTransport，不注册真实媒体键。
- 桌面 UI 回归用 `bash Scripts/verify-ui.sh`；独立 LiquidmusicUITests target 按构建路径启动 App 并显式传隔离变量，避免误启其他 DerivedData 的同标识实例。UI runner 本地 ad-hoc 签名不等于真实签名沙盒验收；UI 合成事件不等于人工听音/硬件操作。
- 扫描变更必须走 LibraryScanner 的准备/提交流程；已有索引覆盖或清理依赖应用内审阅确认，不要绕过它直接对用户索引调用原始 upsert/delete。

## 验证与交接

- 每项任务完成后执行 README 中的 Debug 构建命令，检查退出码和编译错误，不仅检查日志最后一行。
- 队列、扫描、持久化等逻辑变更需要有针对性的测试；简单 UI/目录调整不用写镜像测试。
- 音频、媒体键、关窗行为不能只凭编译判断成功；未测试就明确标注未验证。
- 修改后更新 `docs/HANDOFF.md` 的当前状态、验证结果、遗留问题和下一项任务。
- 如果改动架构或验收标准，同时更新对应文档。不要留下与实现矛盾的“已完成”记录。
- Xcode 使用文件系统同步目录，放进 `Liquidmusic/` 的 Swift 文件自动参与 App 编译；测试文件放在单独 Tests 目录并配置测试 target，避免误编译进 App。
