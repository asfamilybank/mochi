# 图标改用 SF Symbols，ghost 是唯一保留自绘的例外

[design-language.md](../design-language.md) 从一开始就定了"图标全部手绘线性 SVG，参照 SF Symbols 的几何风格（统一描边粗细、圆角端点、24px 网格）"，[ADR-0011](0011-normal-mode-toolbar-safari-alignment.md) 把"手绘图标"列进了明确不推翻的核心决定。这份 ADR 推翻其中的"全部"——改为：**凡 SF Symbols 里有的，一律用系统符号；只有系统里没有的（ghost）才自绘，且自绘的那一个必须满足系统符号的度量契约**。

推翻的理由不是审美偏好，而是这套手绘图标在真机上实测出的一组缺陷，它们都源于"照着 SF Symbols 的风格自己画"这个做法本身，而不是某一次画错：

- **刷新图标的箭头画成了一个 L 形直角**，而且弧身的缺口跟它不在同一处，整个图标视觉上断成两截。
- **本该实心的圆点全部渲染成甜甜圈**：`moreHorizontal` 的三个点、ghost 的双眼、warning 感叹号的点。根因是渲染器只 stroke 不 fill，而这些子路径的直径（2–3.2pt）小于描边宽度（1.75pt），描边把圆环内孔挤到只剩 0.25–1.45pt。
- **warning 的感叹号点压在三角形底边上**，重叠 0.25pt。
- **整套图标坐在 24×24 的正方形画布上、`alignmentRect` 也是 24×24**，而真实 SF Symbols 的画布高度随字号、宽度随字形、`alignmentRect` 是文字的 cap height——所以手绘图标跟系统符号并排时尺寸和基线永远对不齐。托盘图标更直接：24×24 塞进 22pt 的菜单栏，本身就超高。

同一批实测还推翻了一条相关的实现假设：`DesignTokens.addressFieldGlyph(hasLoadedPage:)`（lock/search 双态前导图标）从写出来起就没有任何产品消费者，地址栏实际显示的一直是 `NSSearchField` 自带的放大镜，且恒定是放大镜。这次顺带接上了线。

## 决定

- **`DesignTokens.Symbol` 是符号名的唯一来源**，列出 `chevron.left` / `chevron.right` / `arrow.clockwise` / `ellipsis` / `exclamationmark.triangle`，加上 `AddressFieldGlyph` 的 `lock` / `magnifyingglass`。不在使用点写字符串字面量——打错一个字的症状是图标静默消失，集中列出才能用一条测试遍历验证全部名字在部署 SDK 里解析得到。
- **`ToolbarStyle.symbolImage` 对解析失败 `preconditionFailure`**，不静默降级成空白按钮。符号名是编译期常量，解析不到意味着写错了，应当立刻暴露。
- **ghost 保留自绘，但几何以外的一切都对齐系统符号**，契约固化在 `SymbolMetrics`，四条规则全部由实测系统符号得出而非假设：
  - 画布高度 = `pointSize + 3`（**下面「后续」一节把它限定为只在 11–18pt 成立**）；
  - `alignmentRect` 高度 = 同字号系统文字的 cap height，**量化到半点**（系统符号在 13/15/17pt 上落在 9.0 / 10.5 / 12.0，对应 SF Pro cap height 9.16 / 10.57 / 11.98——取整到整数会把 15pt 算成 11.0，让 ghost 偏离邻居半个点）；
  - 宽度按字形自身的墨迹宽高比，不是正方形（系统符号 `chevron.left` 是 10×14、`ellipsis` 14×5、`exclamationmark.triangle` 17×15）；
  - 描边粗细随字号线性缩放（`.regular` 实测 13pt≈1.5、15pt=1.75、17pt≈2.0），墨迹四周留约 1pt。
- **ghost 的轮廓与眼睛拆成两条路径**：轮廓 stroke，眼睛 fill。单条全 stroke 的路径画不出这个尺寸的实心点，这是上面"甜甜圈"缺陷的直接修正，也是为什么 `GhostGlyph` 暴露 `outlinePath` 和 `eyesPath` 而不是一个 `path`。
- **ghost 的裙摆改为向下凸的经典幽灵轮廓**，替换原先向上凹的密集锯齿——后者在 13pt 工具栏尺寸下糊成一条毛边。
- **托盘图标钉在 15pt**（画布 18×18），不沿用工具栏的字号。status item 按图像自身尺寸绘制在 22pt 菜单栏里，原先的 24×24 超高且零内边距。
- **地址栏前导 lock/search 图标接上 `DesignTokens.addressFieldGlyph`**，通过 `NSSearchFieldCell.searchButtonCell.image`。`AddressFieldGlyph.accessibilityLabel` 刻意不说"安全连接"——这个图标跟踪的是"有没有加载页面"，不是"是否走了 TLS"，在 http 页面上声称安全是错的。
- **`NSSearchField` 的 stock 按钮改为在 `AddressField.layout()` 里维持，不在构造时设一次**。实测根因：给 `cancelButtonCell` 赋 nil **本身**就会让 AppKit 在下一次 toolbar layout 时装回一个新 cell，所以构造时设的 nil 被冲掉，导致一个活的清除按钮（灰底 ✕）一直画在内嵌刷新图标上面——两者都在字段尾端。两处赋值都加了守卫（清除按钮判非 nil、前导图标比对 accessibility description），因为"赋值即触发重建"，无条件重写会在每次 resize 上反复自激。
- **工具栏 stock item 的图标按 AppKit 自己的控件色渲染，不再视为缺陷**。ADR-0011 把这一点记为"标准 item 拿不到 `contentTintColor`"的代价；换成系统符号之后，这恰恰是正确行为——原生工具栏就是这个渲染路径，包括窗口非活跃时的变淡。

## Considered Options

**第三方图标库（Lucide / Feather / Phosphor / Font Awesome）**：否决。它们是字体或 SVG 包，不吃 `NSImageSymbolConfiguration`、不匹配系统字重度量、不跟随系统更新——等于把"自己画一套再手动对齐系统"的问题换个来源重犯一遍。

**ghost 走 SF Symbols.app 导出自定义符号模板 + Asset Catalog**：这是 Apple 对自定义符号的正规路子，能让 ghost 跟系统符号共享完整 API（多字重插值、scale 变体）。本次未采用，因为它需要一次 SF Symbols.app 里的人工设计流程，并且 macOS target 目前是纯 SPM executable、没有 Asset Catalog，要另加 `.process("Resources")` 与 bundle 资源加载。`SymbolMetrics` 是同一目标的代码侧近似：它复现了度量契约，但不提供字重插值。真要做多字重时再走这条路。

**地址栏换成 `NSTextField` + 完全自绘前导/尾部图标**：能彻底摆脱 `NSSearchField` 自带的 search/cancel 按钮，不必再跟 AppKit 的 cell 重建赛跑。否决，因为要推翻 ADR-0011 选定的控件类型，还得自己复刻圆角外观与文本内缩逻辑；`layout()` 维持这条路改动小得多，且实测有效。代价是前导图标和清除按钮都得靠那个钩子维持，`searchButtonCell` 将来若也被 AppKit 换掉，同一个钩子就是修复点。

## Consequences

- `DesignIcon` 枚举（8 个 case）和 `DesignIcons.swift` 整体删除，文件改名 `GhostGlyph.swift`；`DesignIconsTests.swift` → `GhostGlyphTests.swift`。`ErrorPageView` 里随之失去用途的 `IconShape`（CGPath → SwiftUI `Shape` 适配器）也一并删除，错误页改用 `Image(systemName:)`。
- `DesignTokens.Layout.iconStrokeWidth`（1.75）语义收窄：它现在只是 ghost 在 `SymbolMetrics.referencePointSize`（15pt）下的描边宽度，不再是一整套图标的统一描边——别在其他字号下直接用这个裸值。
- design-language.md 第 19 行"图标全部手绘线性 SVG"和第 30 行"图标沿用现有手绘 SVG 图标集"已被本 ADR 推翻，需要改写；第 79 行那段 app/tray icon 的生成 prompt 不受影响（那是应用图标素材，跟界面图标集是两件事）。
- 仍未解决、不在本次范围内：**应用本身没有任何 app icon 资源**（无 `.icns`、无 Asset Catalog，`Package.swift` 无 resources），Dock 图标是系统默认白纸。design-language.md 已写好生成方式，缺的是素材与打包，需要单独一轮。
- 沙盒内验证不了的：菜单栏托盘图标的真实观感。status item 不作为可按 window ID 截图的 CGWindow 暴露，所以这次只验证到"画布 18×18 装得进 22pt 菜单栏"这一层几何，实际是否够清晰要真机看一眼。

## 后续：`alignmentRect` 的半点是契约宽度，不是权宜之计（[#55](https://github.com/asfamilybank/mochi/issues/55)）

上面那条"`alignmentRect` 高度 = cap height 量化到半点"在 [#54](https://github.com/asfamilybank/mochi/issues/54) 接上 CI 后第一次被另一个 macOS 小版本检验，结果分叉：15pt 下真实 `arrow.clockwise` 的 `alignmentRect.height` 在 macOS 26.5.2（本地开发机）是 10.5、在 26.6.2（`macos-26` runner）是 11.0，13pt 与 17pt 两边一致。喂给 `SymbolMetrics` 的输入（`NSFont.systemFont(ofSize:).capHeight`）两边完全相同，所以分叉出在系统符号那一侧。

**结论：规则不动，把"半点"明确为契约宽度。** 依据：

- **这条规则不是对三个字号的巧合拟合。** 在 26.5.2 上把 8–26pt 全部 19 档扫一遍，`round(capHeight × 2) / 2` 与真实系统符号的 `alignmentRect.height` **每一档都精确相等**（差值只有 1e-15 量级的浮点残渣）。同一字号下六个不同符号（`arrow.clockwise`/`chevron.left`/`lock`/`magnifyingglass`/`ellipsis`/`exclamationmark.triangle`）报的也是同一个值，说明它是字体度量的派生量，不是逐符号的资源数据。复现用一段 `swiftc` 直编的脚本即可：

  ```swift
  import AppKit
  for pt in (8...26).map(Double.init) {
      let ours = (Double(NSFont.systemFont(ofSize: pt).capHeight) * 2).rounded() / 2
      let theirs = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)!
          .withSymbolConfiguration(.init(pointSize: pt, weight: .regular, scale: .medium))!
          .alignmentRect.height
      print(pt, ours, theirs)
  }
  ```

- **26.6 的三个已知值反推不出任何一条自洽的取整规则。** 26.6 上 13/15/17pt 分别是 9.0 / 11.0 / 12.0：四舍五入到半点会给出 15pt=10.5（对不上），向上取整会给出 13pt=9.5（也对不上）。
- **风险不对称。** 改 `forGlyph` 的算术去迁就 11.0，等于拿 26.5 上 19/19 的精确吻合去换一个分叉点；而视觉代价只有半点，且只发生在一个字号上，肉眼不可辨。

因此：

- `SymbolMetrics.forGlyph` 的量化方式保持 `round(capHeight × 2) / 2` 不变，`alignmentBoxIsTheCapHeightQuantisedToHalfPoints` 里钉住的 9.0 / 10.5 / 12.0 三个期望值也不变——它们钉的是**我们自己的算术**，输入 cap height 在两个版本上一致，所以跟 OS 无关。
- 跟**活的系统符号**对照的那条测试，半点 slack 从"临时措施"升级为**明示的契约**：ghost 承诺的是"与同字号系统符号相差不超过一个量化步长"，而不是"完全相等"。这条断言仍然抓得住真正值得抓的回归——字形按错误字体算尺寸，或整整差一个点。
- **对照断言的字号范围刻意保持 13/15/17 不变，没有跟着扫描一起扩到 8–26pt。** 那 19 档是本次的取证手段，不是契约面：26.6 上只有 3 档有实测值，把另外 16 档钉进 CI 等于拿没量过的字号当红灯来源，而 app 只画 13pt（工具栏）和 15pt（托盘）。
- 同一轮重测顺带修正了上面另一条规则的表述：**画布高度 = `pointSize + 3` 只在 11–18pt 成立**（10pt 的系统符号画布是 12 不是 13、20pt 是 24 不是 23，26.5.2 实测）。app 用到的两档都在区间内；将来要在区间外画自绘字形，得先把画布规则在那一档重测。这条同样只在 13/15/17 上有测试守着。

**仍未回答、刻意留着的**：#55 的决策点 1（"在 26.6 的机器上把真实 symbol 度量重新量一遍"）没有执行——本地是 26.5.2，手上没有 26.6 的机器。所以"15pt 是系统侧符号字体度量的一次孤立微调，而不是换了一套取整方式"目前**只是推断，不是实测结论**：它建立在 26.6 的三个数据点上，样本量不足以定性。真要落实，最便宜的路子是在 `ci.yml` 里临时加一步把上面那段脚本的 19 档输出打出来（runner 就是 26.6），拿到全档曲线再回头看这一节。在那之前，本节的决定不依赖这个推断成立——"不改算术"靠的是上面的风险不对称，而不是对 26.6 机制的猜测。

**另记一笔**：#55 正文说"15pt 正是工具栏和托盘都在用的字号"，与代码不符——`ToolbarStyle.GlyphSize` 里工具栏是 13pt、托盘是 15pt，15pt 那档画的是 `MochiGlyph` 而非 ghost。分叉字号对 ghost 的实际影响因此比 issue 描述的更小。
