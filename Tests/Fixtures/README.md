# 测试素材

这些文件由本机已有的 FFmpeg 生成，不含用户音乐或第三方作品：

- `tone.wav` / `tone.aiff` / `tone.flac`：约 0.4 秒、44.1 kHz 的 440 Hz 合成音。
- `cover.jpg`：1600×900 的合成纯色图，验证 ImageIO 下采样。
- `tagged.mp3`：合成音加嵌入封面，ID3v2.3 标签为 Fixture Song / Fixture Artist / Fixture Album / Fixture Collection，曲号 3/8、碟号 2/2。
- `tagged.m4a`：同一合成音转为 AAC，保留基础标签和曲号/碟号，验证 iTunes 标签。
- `v1.sqlite`：人工构造的 M2 数据库快照，含一条虚拟歌曲，验证新增文件指纹列时保留旧数据。它不包含真实路径或书签。

素材已纳入独立 XCTest bundle，运行测试不依赖 FFmpeg。测试将素材复制到本用例的临时目录，再进行扫描，不遍历真实音乐文件夹。播放器测试默认静音。
