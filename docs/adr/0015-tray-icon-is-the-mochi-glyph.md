# 托盘图标改为 MochiGlyph，ghost 退回界面用途

[ADR-0013](0013-sf-symbols-for-every-glyph-but-the-ghost.md) 定下「凡 SF Symbols 里有的一律用系统符号，只有系统里没有的（ghost）才自绘」，并把托盘图标钉在 15pt 的 `GhostGlyph` 上。但那是个临时替代——`AppKitPlatformOps.swift` 里的注释写明了这一点，而 [design-language.md](../design-language.md) 从一开始定的托盘图标就是「app 图标的扁平化单色版本：麻糬轮廓 + 窗口做负空间挖空」。这份 ADR 兑现后者：**新增 `MochiGlyph` 并让托盘用它，`GhostGlyph` 退回空页面等界面用途**。

## 决定

- **`MochiGlyph` 用 CGPath 代码绘制，不用位图/PDF 资源**。托盘图标是纯单色 template，形状简单（圆润轮廓 + 一个圆角矩形挖空），用路径描述比用位图更精确。
- **复用 `SymbolMetrics` 的度量契约**，与 `GhostGlyph` 同一套规则：画布高度 = `pointSize + 3`、`alignmentRect` 取同字号 cap height 并量化到半点、宽度按字形墨迹宽高比、描边随字号线性缩放。托盘沿用 15pt（画布 18×18，装进 22pt 菜单栏）。
- **窗口部分用 even-odd 填充规则挖空**，不另画一块颜色不同的面板——template image 必须保持纯单色，系统才能按菜单栏深浅自动反色。
- **`GhostGlyph` 保留**，继续服务空页面等界面场景。ADR-0013 里「ghost 是唯一自绘例外」这句话的**范围**因此收窄：它说的是「界面图标集里 SF Symbols 之外的唯一例外」，而品牌标识（app / 托盘图标）本来就不在那个图标集的讨论范围内。

## Considered Options

**从 Icon Composer 导出 PDF template，走 SPM `resources:` + `Bundle.module`**：这是本轮设计讨论里最初的推荐，理由是「托盘图标应与 app 图标同源」。否决，因为 ADR-0013 花大力气建立的 `SymbolMetrics` 度量契约**只对代码绘制生效**——换成位图资源等于把它丢掉，又退回「24×24 塞进 22pt 菜单栏」那类对不齐的问题。代码绘制还顺带消掉了「资源 bundle 有没有被正确拷进 `.app`」这个只在打包产物上才会暴露的失败模式。

**托盘永久保留 `GhostGlyph`，反过来改掉 design-language.md 的麻糬方案**：否决。Dock 图标和托盘图标是同一个品牌标识的两种形态，用两个不同的吉祥物（麻糬 vs ghost）是纯粹的不一致。

**走 SF Symbols.app 导出自定义符号模板 + Asset Catalog**：ADR-0013 当初以「纯 SPM、没有 Asset Catalog」为由否决过，而 [ADR-0014](0014-packaging-and-distribution.md) 引入 `.xcodeproj` 之后这个理由已经消失。本次仍不采用，但换了理由：它需要一次 SF Symbols.app 里的人工设计流程，而托盘图标不需要多字重插值——那正是自定义符号模板相对 `SymbolMetrics` 的唯一实质优势。

## Consequences

- 托盘图标与 Dock 图标从此是**两份独立产物**：一份是代码里的 CGPath，一份是图像生成模型出的位图。app 图标底稿定稿后，需要人工核对两者的麻糬轮廓是不是同一个形状——这个核对没有自动化手段。
- 同一套路径顺带用于生成打包链路的**占位 app 图标**（正式底稿到位前），所以 `MochiGlyph` 不是只服务托盘的一次性代码。
- 沙盒内验证不了的部分同 ADR-0013：菜单栏 status item 不作为可按 window ID 截图的 CGWindow 暴露，所以只能验证到「画布 18×18 装得进 22pt 菜单栏」这一层几何，实际观感要真机看一眼。
- design-language.md 的托盘图标一节需要补上「实现为 CGPath 而非导出位图」这句，其生成 prompt 作为形状参考存档保留。
