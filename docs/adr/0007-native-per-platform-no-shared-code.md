# 放弃跨平台抽象层：macOS 用 Swift 原生开发，未来 Windows（如果做）是独立代码

最初方案是 Rust + Wry/tao 跨平台抽象层，同时面向 Windows 和 macOS。重新评估后决定放弃跨平台代码共享：v1 只做 macOS，直接用 Swift + AppKit/SwiftUI + WKWebView 原生开发，不再用 Rust，也不再维护一层跨平台窗口/WebView 抽象。

未来如果真的启动 Windows 版本，会是同一个仓库下完全独立的第二套代码（大概率是不同的语言/框架，具体技术栈到时候单独评估），两套实现之间不共享代码——只共享 `CONTEXT.md` 和 `docs/adr/` 这类领域文档：无论用什么技术栈实现，"Widget 是什么""Ghost Mode 该怎么表现"这类判断只有一份权威定义，两边都要对齐它。

这个决定的理由：跨平台抽象层（无论是 Wry/tao 还是自建）的价值在于"一份代码两边跑"，但调研过程中发现这份价值伴随着实打实的成本（Windows WebView2 与 macOS WKWebView 在透明度、按键注入等能力上差异巨大，抽象层经常只是把差异藏起来而不是真正抹平），而且未来 Windows 版本本来就打算独立开发——既然不打算共享代码，也就没有必要为了"跨平台"这个不存在的目标继续付维护抽象层的成本。

## Consequences

- 仓库目录结构预留：Swift 项目放在 `macos/` 子目录下，`CONTEXT.md`/`docs/adr/` 留在仓库根目录，为将来可能出现的 `windows/` 子目录（独立代码）腾出对称的位置。
- 之前基于 Rust + `PlatformOps` trait 设计的测试接缝需要在 Swift 语境下重新表达（对应为一个 Swift protocol），语义不变，只是语言变了。
- [ADR-0001](0001-accept-native-webview-transparency-limits.md)（透明度）、[ADR-0003](0003-hotkey-forwarding-platform-split.md)（热键传递）里原本涉及 Windows/跨平台的内容已经拆掉，只保留 macOS 的结论；这两条 ADR 不再对 Windows 做任何承诺。
