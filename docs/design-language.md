# Mochi 设计语言

这份文档记录 Mochi 的视觉设计决定：材质、色彩、图标、窗口/工具栏的具体构成。行为层面的验收标准不在这里重复——那些记在 GitHub issue 里（见每节末尾的引用），这里只记"长什么样、为什么长这样"。

前提：最低支持 macOS 26（Tahoe），全面使用真 Liquid Glass 材质 API，不做旧系统的 vibrancy 降级方案，见 [ADR-0008](adr/0008-macos-26-liquid-glass-baseline.md)。

视觉稿画布（可实时调浅色/深色、强调色、Ghost Mode 透明度）：[Mochi Liquid Glass](https://claude.ai/code/artifact/4b6c13a6-4cc3-4fb0-bebf-af8391d28a7f)。画布的 Design Components 源文件在 [design/mochi/](../design/mochi/)，改视觉稿直接改那几个 `.dc.html`，不要手改发布出去的那份。

## 材质与色彩

- **玻璃材质**：Liquid Glass——`backdrop-filter: blur() saturate(180%)` 的模糊 + 饱和度提升，内嵌 1px 高光边（浅色顶部白色高光，深色顶部低透明度白色高光），外加轻微投影。用在空页面的抽象构图 panel 上。
- **强调色**：跟随系统 accentColor（`NSColor.controlAccentColor` / SwiftUI `Color.accentColor`），不写死一个品牌色——用户在系统设置里选的强调色应该能同步影响 Pin/Ghost Mode 切换按钮的激活态染色。视觉稿里用一个可调色板模拟这几个 macOS 系统强调色选项，默认 **Orange `#FF9500`**：
  - Orange `#FF9500`（默认）
  - Blue `#007AFF`
  - Purple `#AF52DE`
  - Pink `#FF375F`
  - Red `#FF3B30`
  - Green `#34C759`
  - Graphite `#8E8E93`
- **字体**：系统字体栈，不引入自定义品牌字体——`-apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", system-ui, sans-serif`。
- **图标**：全部手绘线性 SVG，参照 SF Symbols 的几何风格（统一描边粗细、圆角端点、24px 网格），不用 emoji、不用文字符号（比如"更多"按钮是三个绘制的圆点，不是打三个句点字符）。
- **圆角**：窗口内容区、工具栏胶囊、按钮统一用大圆角（现代 macOS 应用的惯例），Ghost Mode 无边框窗口的内容区也保留圆角。
- **阴影**：跟随透明度渐隐——Normal Mode（完全不透明）阴影正常显示；Ghost Mode 下阴影强度和内容不透明度绑在一起变化，透明度越低阴影越淡，避免一个几乎看不见的窗口还拖着一圈明显的阴影。

## 窗口与工具栏

**Normal Mode**：原生标题栏与工具栏合并为同一行——traffic lights（关闭/最小化/最大化）与工具栏按钮、地址栏显示在同一水平高度，标题文字完全不可视化渲染（`NSWindow.titleVisibility = .hidden`）。技术上通过原生 `NSToolbar`（`titlebarAppearsTransparent` + `.unified` 样式，整行实测 52pt；`.unifiedCompact` 会把整行钉死在 40pt，见 ADR-0011 的实测记录）实现，这一整行的 Liquid Glass 材质由系统原生渲染（macOS 26 上标准 AppKit 控件默认即真 Liquid Glass），不额外包自定义玻璃层；`NSGlassEffectView` 只保留给空页面抽象构图 panel 这一处脱离原生 chrome 的自绘内容。整体观感直接对标 Safari 的 unified toolbar，见 [ADR-0009](adr/0009-unified-native-toolbar-chrome.md)（取代 [ADR-0004](adr/0004-native-chrome-plus-custom-toolbar.md) 的两行式布局）具体结构与响应式收纳细节见 [ADR-0011](adr/0011-normal-mode-toolbar-safari-alignment.md)。

工具栏下方新增一条加载进度条：绑定 `WKWebView.estimatedProgress` 真实加载进度，2pt 高、系统强调色，从左到右填充，加载完成后短暂淡出消失，不加载时不占用界面空间（不是常驻灰色轨道）。

工具栏按钮清单（从左到右，[ADR-0011](adr/0011-normal-mode-toolbar-safari-alignment.md)）：
1. 后退/前进——合并成一个原生 `NSSegmentedControl`（不是两个独立按钮），图标沿用现有手绘 SVG 图标集
2. 地址栏——**智能双态**：标准 `NSSearchField`（不额外包自绘玻璃层，视觉上比周围行更"实"是系统原生效果）。页面加载完成且未交互时显示页面标题；鼠标悬停或点击时显示 URL（点击后可编辑，失焦或移出且非加载中则退回标题）；加载中无论是否有交互都恒定显示 URL。标题取不到时兜底显示域名，再取不到就留空。手动导航会覆盖持久化的"上次访问 URL"。空页面（未导航）状态不受这套切换影响，固定显示占位提示文字，直到用户真正导航一次。宽度改为 Safari 式的弹性伸缩（有 min/max，不再无脑撑满剩余空间）；尾部内嵌刷新图标（替代原来独立的刷新按钮，不做"加载中变停止按钮"这个中止导航能力），Empty Page 态下隐藏
3. Pin 置顶切换（激活态：强调色染色玻璃背景 + 强调色描边 + 强调色图标，仿 macOS 选中态的染色玻璃效果）
4. Ghost Mode 切换（尚未实现，见 ADR-0011 的范围排除说明）
5. 设置（"更多"入口，⋯）

Pin 和设置各自独立、不共享背景胶囊。窗口变窄放不下时，接入原生 `NSToolbarItem.visibilityPriority` 自动收纳进"更多工具栏项"溢出菜单，优先级从高到低：地址栏 = 后退/前进分段控件 > Pin > 设置；窗口自身也有一个比 Safari 更小的最小宽度（440pt，按"只剩分段控件 + 地址栏最小宽度"反推）。设置先收、Pin 后收：为此设置项做成标准 `NSToolbarItem`（`image` + `action`），Pin 因为要保留强调色染色玻璃激活态仍是自绘视图——AppKit 会把相邻的一串自绘视图项一步全部收走，两个都自绘时逐个收纳做不到。实测"只剩 Pin"这一段只有约 4pt 宽（484–481pt），这是原生机制的上限，原因见 [ADR-0011](adr/0011-normal-mode-toolbar-safari-alignment.md) 的实测记录。地址栏宽度实测区间 200–320pt。

窗口标题（`NSWindow.title`，供 Mission Control/Cmd-Tab 使用）动态跟随页面标题，取不到时兜底域名，再取不到兜底 `"Mochi"`（这一级不能为空）——这是 `NSWindow.title` 这个供 Mission Control/Cmd-Tab 读取的元数据本身的兜底值，跟上面"标题文字不可视化渲染"是两回事，互不影响。

见 [issue #4](https://github.com/asfamilybank/mochi/issues/4)。

**Ghost Mode 纯净态**：完全无边框、无原生装饰、无工具栏，只剩网页内容，按目标透明度渐隐；鼠标移入窗口区域整个窗口直接消失。见 [issue #8](https://github.com/asfamilybank/mochi/issues/8)。

**空页面**（对标 Chrome 新标签页，见 [issue #16](https://github.com/asfamilybank/mochi/issues/16)）：完整的 Normal Mode 窗口（标题栏 + 全套工具栏），地址栏在空态下显示占位提示文字 + 放大镜图标（而不是锁形图标）。内容区是一个不依赖 App 图标的抽象 Liquid Glass 构图（两片半透明圆角面板叠加、轻微旋转错位），下方是一个视觉弱化（低透明度、小字号）的默认热键速览，不含独立的 URL 输入框——导航统一走工具栏自带的地址栏。

## App 图标 / 托盘图标

**App 图标方向**：圆润的麻糬（Mochi）造型为主体，米白/暖白色，光泽玻璃质感的高光和阴影（呼应 Liquid Glass 语言本身）；麻糬表面嵌一个小的圆角"窗口"切面，半透明暖橙玻璃面板，窗口里画出简化的标题栏三个圆点 + 内容区块，暗示"悬浮网页窗口"这个产品语义。窗口是点缀细节，麻糬造型占主导，不喧宾夺主。

**托盘图标（菜单栏图标）**：App 图标的扁平化单色版本——同一个麻糬轮廓，纯黑色实心填充，窗口部分改用负空间挖空（不是另画一块彩色面板，因为要保持纯单色）。遵循 macOS 菜单栏 template image 惯例：导出时必须带真实 alpha 透明通道（不是白色背景），这样系统才能按菜单栏深浅色自动反色。托盘图标常驻显示，不区分 Normal/Ghost Mode，见 [issue #9](https://github.com/asfamilybank/mochi/issues/9)。

**生产方式**：两个图标都是先用图片生成模型（GPT）出一版静态底稿，再看是否需要精修。GPT 出的是单张扁平图，只能当 macOS 26 Icon Composer 分层格式（Default / Dark / Clear / Tinted 四种外观）里 Default 这一层的素材来源，不是能直接拖进 Xcode 用的最终交付物——先做 Default + Dark 两层，Clear/Tinted 等基础图层定稿后再补。

用过的生成 prompt（存档，供复现或迭代用）：

<details>
<summary>App 图标 prompt</summary>

```
A macOS app icon for "Mochi", a lightweight desktop web-widget app. Square 1:1 composition, 1024×1024, centered, generous inner padding so nothing touches the edges (will be placed inside a rounded-square macOS icon mask). Style: matches Apple's own macOS 26 "Liquid Glass" system app icon language — soft frosted-glass material, a gentle specular highlight streak across the top, subtle top-down directional lighting, soft ambient occlusion shadow underneath, smooth glossy sheen, no hard outlines, no drop shadow outside the icon canvas.

Subject: a single, plump, rounded mochi (Japanese rice cake) rendered in a soft neutral off-white / warm cream color, with a smooth pillowy silhouette (no face, no eyes, no character — just the pure rounded food shape, like a soft dumpling/marshmallow form). Set into the mochi's surface is one small rounded-rectangle "window" inset — like a tiny floating screen embedded in the mochi's body — rendered as a translucent, softly glowing warm-orange (#FF9500) glass panel, as if a miniature web window is glowing gently from inside the mochi. The window should read as a clear secondary detail, roughly 25-30% of the mochi's width, not competing with the mochi's silhouette as the dominant shape.

Background: plain flat single soft neutral color (very light warm gray), no scene, no text, no wordmark, no extra props.

Mood: minimal, calm, tactile, premium, playful but restrained — comparable in polish to Apple's own Photos, Notes, or Freeform app icons, not a cartoon mascot, not a sticker, not flat clipart.
```

</summary>
</details>

<details>
<summary>托盘图标 prompt</summary>

```
A macOS menu-bar (status bar) template icon, ultra-simplified, single flat black silhouette/glyph on a fully transparent background (no gradients, no shading, no color, solid black fill only, so it can be used as a system "template image" that macOS automatically re-tints for light/dark menu bars). Square canvas 1024×1024, but the glyph itself should occupy only the center ~60-70% of the frame with even padding on all sides — similar visual weight to Apple's own Wi-Fi, Bluetooth, or Control Center menu-bar glyphs.

Subject: an extremely reduced, flattened version of the app icon's motif — a simple rounded mochi silhouette (soft rounded-rectangle/blob shape, pure flat fill, no gradient) with one small rounded rectangle cut out of its body as a subtractive negative-space notch representing a tiny window (not a separate colored panel — this must stay pure monochrome). No face, no highlights, no drop shadow, no color. Think of it as a compact pictogram, legible and unambiguous even at 18×18 px.

Style reference: SF Symbols glyph style — geometric, even stroke weight, optically balanced, flat vector silhouette only.
```

</summary>
</details>

## 有意不在这份文档里锁死的东西

- **具体像素级数值**（圆角半径、间距、字号）——这些已经在 [design/mochi/](../design/mochi/) 的视觉稿里画成了实际数值，实现时直接量取稿子上的值，不在这里重复抄一遍数字，避免两处不同步。
- **默认热键的具体按键组合**——[issue #1](https://github.com/asfamilybank/mochi/issues/1) 的 Further Notes 里已经写明这是故意不锁死的实现细节。
