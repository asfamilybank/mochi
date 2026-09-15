# Mochi

一个基于 Swift + AppKit/SwiftUI + WKWebView 的 macOS 原生桌面应用，把单个网页渲染成可自由摆放、可隐藏、可置顶的桌面浮窗（Widget），专为"焦点停留在其他应用时，仍可通过全局热键控制这个网页（尤其是视频播放）"这个场景设计。

v1 仅支持 macOS；未来若开发 Windows 版本，是同一仓库下完全独立的代码，只共享领域文档。

## 文档

- [CONTEXT.md](CONTEXT.md) —— 领域术语与核心概念（Widget、Normal/Ghost Mode、Pin/Snap 等）
- [docs/adr/](docs/adr/) —— 架构决策记录
- [docs/agents/](docs/agents/) —— 面向 Agent 协作的流程文档（issue tracker、triage 标签等）

## 开发

Swift 项目在 [macos/](macos/) 子目录下。日常开发与测试走 Swift Package Manager：

```bash
open macos/Package.swift
```

或用命令行构建、测试、运行：

```bash
cd macos
swift build
swift test
swift run Mochi
```

另有一个 `macos/Mochi.xcodeproj`，**只用于产出可分发的 `.app`**（见 [ADR-0014](docs/adr/0014-packaging-and-distribution.md)）。它的 App target 通过 local package reference 依赖 `MochiCore`，不重复编译源码：

```bash
xcodebuild -project macos/Mochi.xcodeproj -scheme Mochi -configuration Release build
```

## Issue 追踪

Issue 和需求 spec 都在本仓库的 GitHub Issues 里，见 [docs/agents/issue-tracker.md](docs/agents/issue-tracker.md)。
