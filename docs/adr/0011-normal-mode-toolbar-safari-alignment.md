# Normal Mode 工具栏结构与响应式收纳向 Safari 对齐

[ADR-0009](0009-unified-native-toolbar-chrome.md) 定下了"原生 `NSToolbar` + 系统 Liquid Glass"这个技术路线，但具体到按钮怎么分组、地址栏怎么伸缩、窗口变窄时怎么办，当时留了空白（`normalModeToolbarButtonDiameter` 那行注释自己承认是"实现时的估算值，没真的量过"）。这次用 [macos-ui-verification.md](../agents/macos-ui-verification.md) 的只读截图 + 无障碍树方法实测了一遍真实 Safari 窗口，把这些空白填上，同时顺手修一个跟 ADR-0009 决定矛盾的实现 bug。这份 ADR 只细化/修正 ADR-0009 的具体实现细节，不推翻它的核心决定（原生 `NSToolbar`、系统渲染材质、手绘图标）。

## 决定

- **标题文字残留（bug fix）**：`AppKitWidgetWindowHandle` 从未设置 `NSWindow.titleVisibility`，导致 Empty Page/未导航态兜底的 `window.title = "Mochi"` 被 `NSToolbar` 原样画在 traffic lights 右边，跟 ADR-0009"标题文字不再可视化渲染"的决定矛盾。改为显式设 `titleVisibility = .hidden`。
- **后退/前进合并成一个原生 `NSSegmentedControl`**：不是自绘 container view。图标继续用现有手绘 SVG 图标集（`DesignIcon`）分别作为两个 segment 的 image——`NSSegmentedControl` 支持任意自定义 `NSImage`，跟"全部手绘线性图标"的既定语言不冲突。
- **刷新按钮撤掉，移进地址栏尾部**：跟 Safari 一样，刷新不再是独立的 `NSToolbarItem`，改成 Smart Address Field 尾部内嵌的图标。**范围明确排除**"加载中切换成停止按钮、点击可中止导航"——Mochi 目前完全没有 `stopLoading` 路径，这次只做位置迁移，不顺带加中止导航这个新能力，避免视觉对齐任务膨胀成功能开发。Empty Page（未导航）态下这个内嵌图标隐藏，跟这个状态"不含独立 URL 输入框"的既有精神一致。
- **地址栏改成弹性伸缩，不再无脑撑满剩余空间**：现状是撑满后退/前进和右侧按钮之间的全部空间；改成 Safari 式的有 min/max 宽度的弹性伸缩。具体 min/max 数值这份 ADR 不锁死，留给实现时对着真机测量。
- **Pin 和设置各自独立注册为普通 `NSToolbarItem`，不打包、不共享背景胶囊**：曾经考虑过把两者打包成一个 `NSToolbarItemGroup`（讨论过程见下）,最终否决——Pin 有自己的强调色染色玻璃激活态，`NSToolbarItemGroup` 的原生 selected 态视觉会跟它冲突；而且视觉上两者本来就不是"分段互斥选择"的关系，各自独立更清楚。
- **接入原生 `NSToolbarItem.visibilityPriority` 做响应式收纳**：这是 AppKit 自带能力，不是要写自定义响应式布局代码。优先级从高到低：**地址栏（含内嵌刷新）= 后退/前进分段控件 > Pin > 设置**。窗口变窄到放不下时，"设置"先被系统自动收进"更多工具栏项"溢出菜单，Pin 独自撑到更窄才跟着收纳。选"设置先收纳"是因为 Mochi 的产品定位是"可钉住的悬浮网页小窗"——Pin/置顶是高频核心交互，设置是低频应用级配置入口，优先保住前者更符合这个 app 存在的意义。
- **窗口最小宽度：不照抄 Safari 实测到的 574pt**——那个数字是为了在此宽度下还塞得下 Safari 自己"sidebar 切换+后退前进+地址栏"这一整组更大的按钮集合。Mochi 收纳到只剩"分段控件+地址栏"时的核心集合小得多，应该按自己的最小可用宽度反推一个更小的数字，具体数值留给实现时测量。
- **工具栏最左侧沿用 Safari 现有的 leading 分组间距节奏，只去掉"显示边栏"按钮本身**（Mochi 没有 sidebar 概念）——不额外发明一段留白去模拟一个不存在的功能位。
- **明确排除在这次范围外**：Ghost Mode 切换按钮继续维持代码里现状"尚未实现"，不借这次改动顺便补上。

## Considered Options

**后退/前进的容器类型**：讨论过自绘一个共享背景的 container view（延续现有 `toolbarButton()` 手绘按钮体系），最终选了原生 `NSSegmentedControl`——用户明确要求"跟 Safari 一样"，且分段控件本身就是 Safari 这个具体交互（`AXSegment` subrole）的原生实现方式。

**Pin/设置的收纳粒度**：讨论过三种方案——(a) 打包成 `NSToolbarItemGroup` 一起显示/一起收纳，(b) 自己包一个 container view 共享一个 `visibilityPriority` 但视觉独立，(c) 完全独立的两个 `NSToolbarItem`、各自独立优先级、staggered 收纳。最终选 (c)，对齐实测到的 Safari 行为——Safari 右侧"共享/新建标签页/标签页概览"这三个语义独立的入口本来就是 staggered 收纳的（无障碍树读出来是三个互不关联的独立按钮），不是打包成一个整体。

## Consequences

- `DesignTokens.Layout.normalModeToolbarButtonDiameter`（现 22pt，注释自称"估算值"）、`toolbarButtonDiameter`（现 30pt）这些数字待实现时对着这份 ADR 记录的 Safari 实测参考值重新核实：Safari 整行工具栏高度 52pt（Mochi 现状 40pt）、地址栏高度 31pt（Mochi 现状 26pt）、后退/前进按钮 36×36 且有 8pt 垂直留白（Mochi 现状 44×40 零留白撑满整行）——这些是参考基准，不是锁死的最终像素值。
- `AppKitWidgetWindowHandle` 里 `ToolbarControls`（`backButton`/`forwardButton` 两个独立字段）和 `toolbarItemOrder`/`itemForItemIdentifier` 这套结构需要跟着改：后退前进从两个独立 identifier 合并成一个，刷新 identifier 撤掉。
- Empty Page 的"占位提示文字 + 放大镜图标"跟这次新增的"地址栏尾部内嵌刷新图标（Empty Page 态隐藏）"是两套独立开关，实现时不要互相干扰。

## 实现时的实测结果（#24–#28，2026-09-04）

按上面"留给实现时测量"的几处，落定的数值与两处偏离原计划的结论：

- **`toolbarStyle` 从 `.unifiedCompact` 改成 `.unified`**：这是 ADR-0009 明确写过的取值，但 `.unifiedCompact` 把整行钉死在 40pt，按钮/地址栏再怎么加高也顶不动；换成 `.unified` 后无障碍树实测整行正好 52pt，与本 ADR 记录的 Safari 参考值一致。视为对 ADR-0009 实现细节的修正，不影响"原生 `NSToolbar` + 系统材质"这个核心决定。
- **落定数值**：`normalModeToolbarButtonDiameter` 22 → 36（对齐 Safari 后退/前进的 36×36；手绘图标仍在自己的 24×24 网格上，`scaleProportionallyDown` 不放大）、`addressFieldHeight` 24 → 31、地址栏弹性区间 `[200, 320]`、窗口 `contentMinSize` 宽度 440。
- **440 这个最小宽度是反推出来的，不是拍的**：实测窗口宽度降到 428pt 时，地址栏本身会被 AppKit 扫进溢出菜单——这会直接违反"地址栏任何宽度下都不收纳"。440 是留了余量的下界。
- **地址栏必须屏蔽自己的水平 intrinsic 宽度**：`NSTextField` 一旦真的有文字就会报出内容宽度，`NSToolbarItem` 据此把 `maxSize` 压到 fitting size，结果是"空页面时能弹性伸缩、第一次导航后永久卡在最小宽度"。`AddressField` 重写 `intrinsicContentSize` 把水平方向返回 `noIntrinsicMetric` 后两种状态都正常。
- **Pin 与设置实测是同时收纳的，不是先后**：`visibilityPriority` 按本 ADR 的顺序设了（地址栏 = 分段控件 `.high` > Pin `.standard` > 设置 `.low`），但 AppKit 的溢出算法里，"只收起设置"腾出的宽度约等于它同时要新增的溢出按钮宽度，净收益≈0，所以系统直接一步把两个都收进去（实测阈值：481pt 两个都在，480pt 两个都进溢出菜单）。要做出 Safari 那种逐个收纳，只能自己写响应式布局代码——本 ADR 已明确排除。优先级顺序保留：一旦按钮尺寸/数量变化让这笔账划算，收纳顺序就是设置在前。
- **多出来的宽度靠一个 `.flexibleSpace` 吸收**：地址栏不再撑满剩余空间之后，多出来的宽度必须有去处，否则整行会挤在左边、设置按钮后面留一大块死白。在地址栏和 Pin 之间放一个弹性空白（不是 Safari 那样地址栏左右各一个——那会把地址栏推到窗口正中，跟"分段控件紧贴 traffic lights"的节奏冲突），Pin/设置就贴回窗口右缘。
- **无法在沙盒内验证、需真机确认的**：Liquid Glass 材质本身的观感（ADR-0010）、以及"窗口拖不到 440pt 以下"这条——`contentMinSize` 只约束交互式拖拽，程序化 `setFrame` 绕得过去，所以只能由用户实际拖一次确认。
