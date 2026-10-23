# Liquidmusic · Coral Liquid v1

这是可编辑素材包，不是已导出的 .icon 文件。全部图层为 1024 × 1024；SVG 与 PNG 是同一图层的两种格式，二选一导入，勿重复叠放。

## 从下到上的图层顺序

0. Background：建议直接在 Composer 设置渐变 #FF5C71 → #DC124C；00 文件为备用满幅背景。
1. 01-liquid-wave-back：后层液面，独立组，建议从较弱玻璃效果开始。
2. 02-liquid-wave-front：前层液面，独立组，调整透明度与折射，避免压过音符。
3. 03-music-note：完整连续音符，独立组；启用玻璃效果与高光，可从乳白色开始调整。
4. 04-liquid-droplet-optional：可选水滴，可隐藏以获得更简洁的 Apple Music 式构图。

## 导入与调整

新建 Mac 图标，使用 1024 画布。将 01—04 SVG 拖入侧栏，保持相同画布位置与缩放；如导入时自动裁切或居中，请用同名全画布 PNG，并检查音符和波纹相对位置。波纹延伸到画布边缘是有意的，由 Composer 处理最终图标轮廓。

给音符和两层液面各建独立组，以便分别调节系统玻璃效果。高光、阴影、折射交给 Composer 动态生成，素材不预烘焙这些效果。深色模式可将背景设为深酒红，保留明亮音符；单色模式优先隐藏液面和水滴，检查音符辨识度。

Preview-flat-composition.png 仅用于检查构图，不是系统 Liquid Glass 渲染，也不要作为单层图标导入。AI 概念图若另附，仅作为材质方向参考，与矢量图层的几何不完全一致。

尚未在 Icon Composer 内实测导入、动态光照、深色或单色效果；请在最终导出前检查小尺寸和各外观。当前没有替换 Xcode 的 AppIcon，也没有改动运行代码。

## 设计来源与生成方式

参考用户提供的 Apple Music 黑色底板与镂空双音符，重新绘制连续音符轮廓；增加两层液面表达 Liquidmusic。正式交付图层用矢量路径构建，并导出透明 PNG；内置 imagegen 仅生成独立材质概念预览。

概念图提示词：Create a polished concept preview for Liquidmusic native macOS app icon inspired by Apple Music. Coral red to pink rounded square background, restrained translucent liquid wave across bottom half, large clean pearl white paired eighth musical note with rising crossbar centered, subtle clear glass bevel and refraction, minimal, no text, no sparkles. Main note occupies central 55 percent of canvas.

官方导入文档：https://developer.apple.com/documentation/Xcode/creating-your-app-icon-using-icon-composer
