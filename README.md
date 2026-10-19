# Liquidmusic

对标 Apple Music 的原生 macOS 本地音乐播放器。第一阶段只播放本地文件，不接入账号或流媒体。

## 当前进度

已实现 M0–M7 的框架、本地索引与浏览、播放/队列、系统集成和体验收尾代码。最低 macOS 26，Swift 6 + SwiftUI；第一阶段仍有人工待验项，详见 [验收记录](docs/VALIDATION.md)。

- App 级共享播放器，唯一主窗口和菜单栏共用状态，Preview 使用独立模拟数据。
- 工具栏、侧边栏与 Command-O 打开单个音频文件；异步校验可播放性、时长与基础标签。
- 读取进度、取消和错误提示；失败保留旧曲目，快速重选不被旧任务覆盖。
- 播放/暂停、进度、音量、播放结束重播；临时文件访问和观察者有配对清理。
- 顺序、列表循环、单曲循环、随机模式；随机按队列条目每轮不重复，插队不重洗剩余候选。
- 队列分为当前歌曲、接下来与播放历史；重复歌曲按独立条目跳转，回退后可沿实际历史前进。
- 进度拖动保留临时位置、释放后 seek，支持键盘写入；切歌时拒绝旧滑块回调。
- 原生侧边栏、歌曲 Table、底部 Liquid Glass 播放条、大封面与队列面板；900 点以下窗口的队列通过按钮弹出，跨布局阈值自动收起。
- 最小 640×520 窗口；窄内容区使用紧凑 List，播放条改用两行，音量通过按钮弹出滑块。
- Command-F 聚焦资料库搜索，Escape 清除搜索；播放控件提供辅助功能标签和值，遵循减少动态效果、减少透明度和增加对比度设置。
- 标题/艺术家/专辑实时搜索与四种升降序排序；后台缓存查询，支持中文子串及大小写/变音符号不敏感匹配。
- 专辑网格、艺术家列表及返回详情；固定“所有音乐”。悬停行内播放、双击按当前可见顺序播放，右键提供“下一首播放”。
- MenuBarExtra 迷你控制器：当前曲目、播放控制、恢复主窗口和退出。主窗口关窗转为最小化，Dock 重开和菜单栏恢复同一窗口。
- Now Playing 的标签/封面/速率/进度更新；按状态启用媒体命令并返回正确结果，封面异步加载，普通进度每 5 秒校准。
- GRDB 7.11.1 / SQLite：迁移、稳定 UUID、路径去重、事务写入和导入问题记录。
- “音乐文件夹”管理入口：只读书签保存/恢复、过期刷新、授权失败与重新授权；写库失败保留旧授权。
- 添加文件夹后自动扫描；递归发现 m4a/mp3/flac/wav/aiff/aif，跳过隐藏文件、包和符号链接，重叠目录按最具体根目录归属。
- 读取标题、艺术家、专辑、专辑艺术家、曲号/碟号及嵌入封面；ImageIO 生成最长边 512 像素的缩略图并缓存。
- 导入进度、取消、问题报告和跨启动索引恢复。重扫使用文件指纹复用未变化数据；覆盖旧索引或清理失踪索引前显示具体清单并等待确认。

物理媒体键、控制中心、Dock 点击和 Command-Q 的端到端人工验收尚待补齐。FLAC 按 AVFoundation 实际能力接受或跳过并记录，不保证所有编码变体可播放。

## 运行与验证

用 Xcode 打开 `Liquidmusic.xcodeproj`，选择 `Liquidmusic` scheme。其他开发者按自己的签名环境配置 Development Team。

```sh
xcodebuild -project Liquidmusic.xcodeproj \
  -scheme Liquidmusic -configuration Debug \
  -derivedDataPath /tmp/Liquidmusic-build \
  CODE_SIGNING_ALLOWED=NO build
```

```sh
xcodebuild -project Liquidmusic.xcodeproj \
  -scheme Liquidmusic -configuration Release \
  -derivedDataPath /tmp/Liquidmusic-build \
  CODE_SIGNING_ALLOWED=NO build
```

```sh
xcodebuild -project Liquidmusic.xcodeproj \
  -scheme Liquidmusic -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/Liquidmusic-build \
  CODE_SIGNING_ALLOWED=NO test
```

Intel Mac 将测试 destination 的 arch 改为 `x86_64`。首次解析 GRDB 需下载上游仓库；版本已锁定在 Package.resolved。测试使用临时目录和合成音频素材，播放器静音，不扫描用户音乐文件夹。共享 scheme 的 TestAction 必须使用自己的环境（shouldUseLaunchSchemeArgsEnv=NO）；M6 修复了此前隔离变量被运行环境覆盖的问题，并通过 AppRuntime 识别 XCTest/Preview。媒体测试使用替代传输层，不触碰真实系统控制中心。运行测试不需要安装 FFmpeg。

独立桌面 UI 回归（需要 macOS 图形会话；运行期间勿操作被测窗口）：

```sh
bash Scripts/verify-ui.sh
```

默认沿用 `/tmp/Liquidmusic-build`，可通过 `LIQUIDMUSIC_DERIVED_DATA` 指定构建目录。脚本先构建 App，再运行自动生成的 LiquidmusicUITests scheme，本地 ad-hoc 签名 UI runner；不使用开发者证书。四项 XCUITest 通过，覆盖搜索快捷键、侧边栏隐藏/恢复、窄窗口音量弹窗的 Escape、队列开关与宽窄拖动。测试 App 按构建路径启动并显式启用隔离，不连接真实库、媒体键或菜单栏，不播放音频。这些自动操作不能代替听音、VoiceOver、Dock/媒体键及签名沙盒人工验收。

验证环境：Xcode 27.1 / Swift 6.4，macOS 27.0.1。Debug/Release 构建与 89 项测试通过，Release 包含 arm64/x86_64；测试包括真实 AVPlayer 静音播放、媒体路由/发布节流/迟到封面、AppKit 程序化关窗最小化与恢复，以及千首合成索引/队列规模检查。主窗口宽窄、浅深色、增加对比度、空库与千首 Table 预览已检查；不是实际滚动或交互验收。计时见验收记录。真实签名沙盒、VoiceOver/键盘手势、实际听音与系统级交互仍需人工验收。

## 开发文档

- [交接文档](docs/HANDOFF.md)：真实状态、验证记录、已知问题与接手提示词。
- [验收记录](docs/VALIDATION.md)：M7 构建/预览/规模测量与待人工验证清单。
- [架构约定](docs/ARCHITECTURE.md)：模块、并发、授权、数据和播放语义。
- [实施路线](docs/ROADMAP.md)：里程碑范围与验收条件。
- [AGENTS.md](AGENTS.md)：后续代理的工作约束。

下一项：**M7 剩余人工验收**；暂不进入第二阶段。
