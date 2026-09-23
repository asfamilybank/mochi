# 地址栏改为「容器 + 三个并列子视图」，弹性上限放宽到 480

[ADR-0011](0011-normal-mode-toolbar-safari-alignment.md) 把刷新移进了地址栏尾部，并落定了地址栏弹性区间 `[200, 320]`。当时的实现是一个 `.roundedBezel` 的 `NSTextField` 自己当外框，站点图标和刷新按钮作为它的子视图塞进去，再靠 cell 左右缩进给它们让位。实际用下来和 Safari 有几处明显差别：鼠标停在整个外框上（包括两个图标）都是 I-beam 光标；没聚焦时也能拖选文字；文字永远左对齐，图标也没法跟着文字走。

这次读了 Safari 的无障碍树：地址栏那一整块是一个 492pt 宽的 `AXGroup`，里面的页面菜单、阅读列表、`AXTextField`（`WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD`）、翻译、刷新是**并列的兄弟节点**；文本框本身只有 31pt 高，还带着 `AXShowDefaultUI`/`AXShowAlternateUI` 两个操作，没聚焦时 `AXAlternateUIVisible = 1`。也就是说，同一个文本框有「显示」和「编辑」两套界面，而外框和图标都不属于它。这份 ADR 按这个结构重做 Mochi 的地址栏。

## 决定

- **结构**：工具栏项的视图是 `AddressBarView`，它画外框，站点图标、无边框的 `AddressField`、刷新按钮是它的三个并列子视图。子视图的位置由 `layout()` 手动算，算法在不依赖 AppKit 的 `AddressBarLayout` 里（有单元测试）。容器自己的宽度只由 min/max 约束和工具栏剩余空间决定，里面没有任何东西向 `NSToolbarItem` 报告水平 intrinsic 宽度（原因见 ADR-0011）。
- **显示与编辑两种状态**：
  - 没聚焦时文本框既不可编辑也**不可选中**，所以整个地址栏都是箭头光标。打开页面后，站点图标固定在左边，和右边的刷新按钮镜像对称（两者中心离各自边缘都是 14pt），标题在两者之间居中；空白页上放大镜和占位文字作为一组居中。
  - 点击外框任意位置（包括文字本身）进入编辑，并全选地址。编辑时图标停在最左边，文本框铺满中间，只有文字区域是 I-beam。
  - 两种状态之间用隐式动画滑动过去（0.25s，`DesignTokens.Motion.addressBarModeChange`），开了「减弱动态效果」时不做动画。
- **聚焦光环由容器自己画**，沿外框、画在外框四周那 3pt 留白里（`addressFieldFocusRingInset`），颜色用 `keyboardFocusIndicatorColor`，只在窗口是 key window 时显示。
- **弹性区间从 `[200, 320]` 改为 `[200, 480]`**，推翻 ADR-0011 的那一项数值。上限参照 Safari 地址栏那一组的 492pt；320 在宽窗口里也会把较长的标题截断。下限不变，所以 `normalModeWindowMinWidth` 440 不需要重测（实测 440 宽时地址栏仍在工具栏里）。
- **刷新按钮在编辑时隐藏**，补充 ADR-0011「空白页隐藏」那一条：正在输入的地址不是刷新要重新加载的那个页面，位置让给文字。另外补上了悬停效果、`toolTip`（「刷新页面」）和 identifier `com.mochi.addressBar.reload`。
- **空白页铺满到透明工具栏下面**，工具栏浮在它上面。两个原生页面（空白页、错误页）不再从 safe area 读工具栏高度，改为显式传入：空白页通过 `EmptyPageView.topInset` 让图案在工具栏下方的区域居中，错误页的顶边钉在工具栏下方。这个值和网页的 `obscuredContentInsets` 同一时刻更新，Ghost Mode 下都不变。

## Considered Options

**保留旧结构，只补 `isSelectable = false`**：能解决「没聚焦时的 I-beam」，但外框和图标仍在文本框范围内，编辑时悬停在图标上还是 I-beam；图标用约束钉在字段左边缘，文字一居中就和图标分开，做不到「图标跟着文字走」或「图标固定、文字居中」。否决。

**用系统光环，重写 `focusRingMaskBounds`/`drawFocusRingMask` 把形状扩到整个外框**：独立 harness 实测，AppKit 为一个视图画的光环会被裁在这个视图自己的范围内——覆盖整个外框的形状什么都画不出来，同一个形状缩到字段内部就能正常画。文本框现在比外框小得多，所以只能由容器画。否决。

**子视图继续用 Auto Layout，两种状态各一套约束来回切**：可行，但两套约束加上动画，布局就有两个来源。手动 `layout()` 配合 `allowsImplicitAnimation` 只有一个来源：动画时的每一帧、以及动画途中插进来的布局（比如标题刚到），算出来的都是同一套位置。harness 实测在真实 `NSToolbar` 里，手动设置的 frame 能正确插值，文字在中途没有被拉伸。

**空白页也钉在工具栏下方**（和错误页一样）：能修好 Ghost Mode 上移，但工具栏区域会露出窗口底色，和「空白页铺满、工具栏浮在上面」的要求矛盾。否决。

## Consequences

- 点击文字进入编辑时，光标不再落在点击的位置，而是全选地址。点下去的同时文字要滑走、还要从标题换成网址，原来那个点击位置已经没有意义。
- 光环颜色是手动取的 `keyboardFocusIndicatorColor`，不是系统自己画的，和其他系统输入框的光环是否完全一致需要肉眼对比。
- 没聚焦时文本框在无障碍树里报 `AXStaticText`（`NSTextField` 不可编辑时的固有行为，改动前打开页面后也是这样），编辑时才是 `AXTextField`。Safari 两种状态都是 `AXTextField`。
- 两件事没法在沙盒里自动验证，只能真机看：鼠标光标的形状（截图拍不到光标），以及悬停相关的效果（合成的鼠标事件不触发 tracking area——改动前的版本同样不触发，不是这次引入的问题）。
