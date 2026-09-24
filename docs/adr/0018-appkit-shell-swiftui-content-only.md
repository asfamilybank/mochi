# 外层窗口与工具栏保持 AppKit，SwiftUI 只用于内容视图

曾考虑把外层（窗口 + 工具栏）整体改写为 SwiftUI、内部嵌 macOS 26 的 SwiftUI `WebView`。决定不改：外层继续是 `NSWindow` + `NSToolbar` + `WKWebView`，SwiftUI 只承担内容视图（设置面板、空页面、错误页）。这与 Safari 自身的分层一致——其 `BrowserWindow`/`BrowserToolbar`/`UnifiedField` 均为 AppKit，SwiftUI 只出现在补全列表条目这类局部。

## Considered Options

- **外层 SwiftUI + SwiftUI `WebView`/`WebPage`**：`WebPage` 在 macOS 26 SDK 里没有新窗口（`createWebViewWith`）、下载回调、自动播放、`pageZoom`、`obscuredContentInsets` 的对应物，也不能从已有 `WKWebView` 构造——其中缩放与内容垫在工具栏下是已上线功能，Popup Window（ADR-0017）直接做不了。
- **外层 SwiftUI + `NSViewRepresentable` 包 `WKWebView`**：WebKit 能力保得住，但 Ghost Mode（去 `.titled`、穿透、置顶、`alphaValue`）与 Snap（`constrainFrameRect`）仍得回到 `NSWindow`；SwiftUI `.toolbar` 拿不到 ADR-0011/0016 依赖的 `visibilityPriority`/`isHidden` 收纳、居中收窄与地址栏 field editor 控制。等于重写一遍现有实现、换不来新能力。
- **维持 AppKit 外层（选定）**。
