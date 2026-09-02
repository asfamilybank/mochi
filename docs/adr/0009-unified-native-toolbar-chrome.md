# Normal Mode 标题栏与工具栏合并为同一行，改用原生 NSToolbar + 系统 Liquid Glass 材质

[ADR-0004](0004-native-chrome-plus-custom-toolbar.md) 定下的是"原生标题栏 + 下方独立自绘工具栏，两者各占一行、不重叠"这套两行式布局，目的是避免重新实现原生拖动物理和按钮交互。现在推翻这一具体做法，改成 Safari 式的单行布局——traffic lights（关闭/最小化/最大化）与工具栏内容（后退/前进/刷新/地址栏/Pin/Ghost Mode/设置）显示在同一水平行，参照见 [docs/design-language.md](../design-language.md)"窗口与工具栏"一节。

技术上从纯自绘 `NSView` 迁移到原生 `NSToolbar`：设 `titlebarAppearsTransparent = true`，`toolbarStyle = .unifiedCompact`，原有工具栏内容改造成 `NSToolbarItem`。选择原生 `NSToolbar`，而不是继续手写 view（配合 `fullSizeContentView` 手动读取 `standardWindowButton` frame 对齐 traffic lights、手动把 `mouseDown` 转发给 `window.performDrag(with:)` 实现拖动），是因为前者让 AppKit 原生负责"跟 traffic lights 同排、窗口拖动、焦点环"这些边缘情况——这跟 ADR-0004 当初"不重造原生交互逻辑"的顾虑是同一条原则，只是换了个实现载体。

材质上，这一整行的 Liquid Glass 交给系统原生渲染：macOS 26 上标准 AppKit 控件（`NSToolbar`、`NSSearchField`、`NSButton`）默认渲染就是真 Liquid Glass，不需要额外调用 API。地址栏改用标准 `NSSearchField`，工具栏按钮改用标准无边框 `NSButton`（承载自绘图标），都不再手动包一层 `NSGlassEffectView`。`NSGlassEffectView` 只保留给两处真正脱离原生 chrome、悬浮在网页内容区上方的自绘内容——Ghost Mode 召唤浮层、空页面抽象构图 panel，这两处不受这次改动影响。

## Consequences

- ADR-0004"两行不重叠"的结论作废，其"不重造原生拖动/按钮交互"的核心原则延续到新方案，只是载体从"保留原生标题栏 + 独立自绘工具栏"换成了"原生 NSToolbar unified chrome"。
- `DesignTokens.Layout` 里原来描述"整个工具栏是一个独立胶囊"的常量（`toolbarCapsuleHeight`、`toolbarCapsuleCornerRadius`、`toolbarOuterPadding*` 等）语义作废；工具栏行高改为跟随 `.unifiedCompact` 系统实际渲染结果，不再写死像素值。`toolbarButtonDiameter`（现 30pt）预期要跟着收紧，具体数值待实现时实测。此前从未被任何代码消费的 `titlebarHeight: 38` 常量同样作废。
- 居中显示的 "Mochi" 标题文字不再可视化渲染，但 `NSWindow.title` 属性改为动态跟随当前页面标题（供 Mission Control/Cmd-Tab 使用），不再写死 "Mochi"。
- 这次改动只覆盖 Normal Mode；Ghost Mode 纯净态、Ghost Mode 召唤工具栏不受影响。
