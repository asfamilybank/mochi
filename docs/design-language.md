# Mochi 设计语言

这份文档记录 Mochi 的视觉设计决定：材质、色彩、图标、窗口/工具栏的具体构成。行为层面的验收标准不在这里重复——那些记在 GitHub issue 里（见每节末尾的引用），这里只记"长什么样、为什么长这样"。

前提：最低支持 macOS 26（Tahoe），全面使用真 Liquid Glass 材质 API，不做旧系统的 vibrancy 降级方案，见 [ADR-0008](adr/0008-macos-26-liquid-glass-baseline.md)。

## 材质与色彩

- **玻璃材质**：Liquid Glass——`backdrop-filter: blur() saturate(180%)` 的模糊 + 饱和度提升，内嵌 1px 高光边（浅色顶部白色高光，深色顶部低透明度白色高光），外加轻微投影。用在空页面的抽象构图 panel 上。
- **强调色**：跟随系统 accentColor（`NSColor.controlAccentColor` / SwiftUI `Color.accentColor`），不写死一个品牌色——用户在系统设置里选的强调色应该能同步影响加载进度条的填充色。工具栏眼下没有任何控件带激活态染色（Pin 已随 ADR-0012 移除，Ghost Mode 切换按钮见下方"没有激活态可显示"）。视觉稿里用一个可调色板模拟这几个 macOS 系统强调色选项，默认 **Orange `#FF9500`**：
  - Orange `#FF9500`（默认）
  - Blue `#007AFF`
  - Purple `#AF52DE`
  - Pink `#FF375F`
  - Red `#FF3B30`
  - Green `#34C759`
  - Graphite `#8E8E93`
- **字体**：系统字体栈，不引入自定义品牌字体——`-apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", system-ui, sans-serif`。
- **图标**：优先用 SF Symbols 系统符号（`chevron.left`/`chevron.right`、`arrow.clockwise`、`lock`、`magnifyingglass`、`exclamationmark.triangle`）；只有系统里没有的字形才自绘，目前唯一一个是 ghost 吉祥物（`GhostGlyph`），且它必须满足 `SymbolMetrics` 记录的系统符号度量契约（画布随字号、`alignmentRect` 取 cap height、描边随字号缩放），否则跟旁边的系统符号对不齐。不用 emoji、不用文字符号。见 [ADR-0013](adr/0013-sf-symbols-for-every-glyph-but-the-ghost.md)——这条推翻了原先"全部手绘线性 SVG"的规定。
- **圆角**：窗口内容区、工具栏胶囊、按钮统一用大圆角（现代 macOS 应用的惯例），Ghost Mode 无边框窗口的内容区也保留圆角。
- **阴影**：跟随透明度渐隐——Normal Mode（完全不透明）阴影正常显示；Ghost Mode 下阴影强度和内容不透明度绑在一起变化，透明度越低阴影越淡，避免一个几乎看不见的窗口还拖着一圈明显的阴影。

## 窗口与工具栏

**Normal Mode**：原生标题栏与工具栏合并为同一行——traffic lights（关闭/最小化/最大化）与工具栏按钮、地址栏显示在同一水平高度，标题文字完全不可视化渲染（`NSWindow.titleVisibility = .hidden`）。技术上通过原生 `NSToolbar`（`titlebarAppearsTransparent` + `.unified` 样式，整行实测 52pt；`.unifiedCompact` 会把整行钉死在 40pt，见 ADR-0011 的实测记录）实现，这一整行的 Liquid Glass 材质由系统原生渲染（macOS 26 上标准 AppKit 控件默认即真 Liquid Glass），不额外包自定义玻璃层；`NSGlassEffectView` 只保留给空页面抽象构图 panel 这一处脱离原生 chrome 的自绘内容。整体观感直接对标 Safari 的 unified toolbar，见 [ADR-0009](adr/0009-unified-native-toolbar-chrome.md)（取代 [ADR-0004](adr/0004-native-chrome-plus-custom-toolbar.md) 的两行式布局）具体结构与响应式收纳细节见 [ADR-0011](adr/0011-normal-mode-toolbar-safari-alignment.md)。

工具栏下方新增一条加载进度条：绑定 `WKWebView.estimatedProgress` 真实加载进度，2pt 高、系统强调色，从左到右填充，加载完成后短暂淡出消失，不加载时不占用界面空间（不是常驻灰色轨道）。

工具栏按钮清单（从左到右，[ADR-0011](adr/0011-normal-mode-toolbar-safari-alignment.md)）：
1. 后退/前进——合并成一个原生 `NSSegmentedControl`（不是两个独立按钮），图标用系统的 `chevron.left`/`chevron.right`（[ADR-0013](adr/0013-sf-symbols-for-every-glyph-but-the-ghost.md)）
2. 地址栏——**智能双态**：标准 `NSSearchField`（不额外包自绘玻璃层，视觉上比周围行更"实"是系统原生效果）。页面加载完成且未交互时显示页面标题；鼠标悬停或点击时显示 URL（点击后可编辑，失焦或移出且非加载中则退回标题）；加载中无论是否有交互都恒定显示 URL。标题取不到时兜底显示域名，再取不到就留空。手动导航会覆盖持久化的"上次访问 URL"。空页面（未导航）状态不受这套切换影响，固定显示占位提示文字，直到用户真正导航一次。宽度改为 Safari 式的弹性伸缩（有 min/max，不再无脑撑满剩余空间）；尾部内嵌刷新图标（替代原来独立的刷新按钮，不做"加载中变停止按钮"这个中止导航能力），Empty Page 态下隐藏；前导图标按"有没有加载页面"双态切换——已加载显示 `lock`、空页面显示 `magnifyingglass`（它跟踪的是有无页面，不是是否走 TLS，所以无障碍标签刻意不说"安全"）
3. Ghost Mode 切换——单向的"进入"按钮，不是开关：点击直接从 Normal Mode 进入 Ghost Mode，没有激活态可显示（Ghost Mode 会把整条工具栏一起隐藏，用户不可能看到这颗按钮处于"已激活"的样子）

布局：地址栏是工具栏的居中项（`NSToolbar.centeredItemIdentifiers`），始终落在窗口水平正中；后退/前进紧贴在它左侧（分段控件前面放一个 flexible space 吃掉交通灯与它之间的余量），Ghost Mode 靠右。窗口变窄到地址栏按最大宽度放不进正中时，AppKit 会放弃居中、把整行往左排——所以每次 resize 都按实测偏移把地址栏的最大宽度收窄到恰好能居中的值；窗口窄到约 576pt 以下，地址栏到了最小宽度仍放不下，就尽量靠近正中。

工具栏上没有设置按钮：设置面板从主菜单"设置…"（⌘,）和托盘菜单进入。原先的设置按钮是唯一会被收进溢出菜单的项，窗口一变窄就冒出一个只装着它的"»"。Ghost Mode 按钮同样不收纳：窗口窄到放不下它（实测 452pt 以下）时直接隐藏（`NSToolbarItem.isHidden`），此时只能用热键或托盘进入 Ghost Mode。

置顶按钮已随 [ADR-0012](adr/0012-ghost-mode-as-pure-invisibility.md) 移除——置顶内化成了 Ghost Mode 的固有属性，不再是工具栏上的一个开关。工具栏里没有任何项会被收进"更多工具栏项"溢出菜单：Ghost Mode 按钮放不下就隐藏，窗口最小宽度 392pt（比 Safari 的 574pt 小得多）保证后退/前进和最小宽度的地址栏始终放得下，是逐点扫窗口宽度实测出来的（地址栏在 390pt 被收走、392pt 仍在，没留余量）。窗口不设最小高度。Ghost Mode 按钮是标准 `NSToolbarItem`（`image` + `action`）而非自绘视图，图标按 AppKit 自己的控件色与度量渲染而不是 `DesignTokens`。地址栏宽度区间 200–480pt。

窗口标题（`NSWindow.title`，供 Mission Control/Cmd-Tab 使用）动态跟随页面标题，取不到时兜底域名，再取不到兜底 `"Mochi"`（这一级不能为空）——这是 `NSWindow.title` 这个供 Mission Control/Cmd-Tab 读取的元数据本身的兜底值，跟上面"标题文字不可视化渲染"是两回事，互不影响。

见 [issue #4](https://github.com/asfamilybank/mochi/issues/4)。

**Ghost Mode 纯净态**：完全无边框、无原生装饰、无工具栏，只剩网页内容，按目标透明度渐隐；始终置顶（浮在其他应用窗口之上），鼠标移入窗口区域时让开、移出即恢复。见 [issue #8](https://github.com/asfamilybank/mochi/issues/8)、[ADR-0012](adr/0012-ghost-mode-as-pure-invisibility.md)。

**空页面**（对标 Chrome 新标签页，见 [issue #16](https://github.com/asfamilybank/mochi/issues/16)）：完整的 Normal Mode 窗口（标题栏 + 全套工具栏），地址栏在空态下显示占位提示文字 + 放大镜图标（而不是锁形图标）。内容区是一个不依赖 App 图标的抽象 Liquid Glass 构图（两片半透明圆角面板叠加、轻微旋转错位），下方是一个视觉弱化（低透明度、小字号）的默认热键速览（切换幽灵模式 ⌥⌘G、隐藏窗口 ⌥⌘H、打开设置 ⌘,；动作名在左、按键在右，每个键一个键帽；隐藏那一行注明"幽灵模式下"，因为它在空页面所在的 Normal Mode 里不生效），不含独立的 URL 输入框——导航统一走工具栏自带的地址栏。

## App 图标 / 托盘图标

**App 图标方向**：圆润的麻糬（Mochi）造型为主体，米白/暖白色，光泽玻璃质感的高光和阴影（呼应 Liquid Glass 语言本身）；麻糬表面嵌一个小的圆角"窗口"切面，半透明暖橙玻璃面板，窗口里画出简化的标题栏三个圆点 + 内容区块，暗示"悬浮网页窗口"这个产品语义。窗口是点缀细节，麻糬造型占主导，不喧宾夺主。

**托盘图标（菜单栏图标）**：App 图标的扁平化单色版本——同一个麻糬轮廓，纯黑色实心填充，窗口部分改用负空间挖空（不是另画一块彩色面板，因为要保持纯单色）。**实现为 CGPath 代码绘制（`MochiGlyph`），不是导出的位图资源**——这样它才能复用 `SymbolMetrics` 的度量契约（画布随字号、`alignmentRect` 取 cap height、墨迹内缩），位图拿不到这些，见 [ADR-0015](adr/0015-tray-icon-is-the-mochi-glyph.md)。代码绘制天然满足 macOS 菜单栏 template image 惯例：背景是真实 alpha 透明而非白色，系统按菜单栏深浅色自动反色。托盘沿用 15pt（画布 18×18，装进 22pt 菜单栏），常驻显示，不区分 Normal/Ghost Mode，见 [issue #9](https://github.com/asfamilybank/mochi/issues/9)。

**生产方式**：两个图标走两条不同的路。托盘图标是代码画的（见上），下面那段 prompt 只作为形状参考存档，不是它的素材来源。App 图标先用图片生成模型（GPT）出一版静态底稿，再看是否需要精修。GPT 出的是单张扁平图，只能当 macOS 26 Icon Composer 分层格式（Default / Dark / Clear / Tinted 四种外观）里 Default 这一层的素材来源，不是能直接拖进 Xcode 用的最终交付物。

**只做 Default 一层**，Dark / Clear / Tinted 全部交给 Icon Composer 自动派生。原先这里写的是「先做 Default + Dark 两层」，那句话没考虑到单张扁平图物理上只有一层——真要手工分层得先有分层素材，那是素材迭代那一轮的事，不该卡住打包链路（[ADR-0014](adr/0014-packaging-and-distribution.md)）。

**正式底稿怎么替换进来**（出图和 Icon Composer 两步都没有 CLI，Agent 做不了，必须人工）：

1. 把上面那段 prompt 喂给图像生成模型，**并要求透明背景**。挑选标准是跟托盘剪影对得上：顶部圆拱、底部偏平（不是正圆、也不是圆角方块），窗口是居中的圆角矩形、约占身宽 30%，四周留白充足、不画外阴影——遮罩、背景和投影都由 Icon Composer 和系统施加，画进像素里会跟着进 Dark/Clear/Tinted 各种派生外观。参照物是 `swift run MochiIconGen` 生成的占位图 `macos/App/Icon/mochi-placeholder-1024.png`，它直接从 `MochiGlyph` 的路径渲染，轮廓就是托盘图标的轮廓。
2. 打开 `/Applications/Xcode.app/Contents/Applications/Icon Composer.app`，把 PNG 拖进图层列表，配好背景，**`File → Save As…` 存成 `macos/App/Mochi.icon`**。注意是 Save 而不是 `Export…`——`.icon` 就是 Icon Composer 的原生文档格式，`Export…` 导出的是位图。保存时它会把 PNG 复制进 `Mochi.icon/Assets/`，所以源图自动随文档入库，不必另存一份。

Xcode 工程那侧不需要任何改动：`Mochi.icon` 已经在 App target 的 Resources 阶段里、`ASSETCATALOG_COMPILER_APPICON_NAME` 已指向它，换素材只是换 `.icon` 里的图层。

**如果模型给不出透明背景**（早期几版就是画在一块实心底板上的），`macos/scripts/cutout-icon-background.swift` 可以把主体抠出来，但它的阈值是逐图实测的、换图必须重量——两张图实测下来参数完全不同。优先让模型直接出透明底，这个脚本是兜底。

占位图的存在只是为了让打包链路不被素材产出阻塞。它由 `MochiIconGen` 这个不随 app 分发的 target 从 `MochiGlyph` 渲染而来，麻糬轮廓将来跟着正式素材调整时，重跑一次就能拿到新的参照物——这是托盘图标与 app 图标轮廓一致性核对里唯一能机械化的部分，其余靠眼睛（[ADR-0015](adr/0015-tray-icon-is-the-mochi-glyph.md)）。

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

- **默认热键的具体按键组合**——[issue #1](https://github.com/asfamilybank/mochi/issues/1) 的 Further Notes 里已经写明这是故意不锁死的实现细节。
