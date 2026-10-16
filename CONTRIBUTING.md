# 参与开发

## 项目结构

Mochi 是一个基于 Swift + AppKit/SwiftUI + WKWebView 的 macOS 原生桌面应用，把单个网页渲染成可自由摆放、可隐藏、可置顶的桌面浮窗（Widget），专为"焦点停留在其他应用时，仍可通过全局热键控制这个网页（尤其是视频播放）"这个场景设计。

Swift 项目在 [macos/](macos/) 子目录下。v1 仅支持 macOS；未来若开发 Windows 版本，是同一仓库下完全独立的代码，只共享领域文档。

## 开发

日常开发与测试走 Swift Package Manager：

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

`swift run` 必须带上产品名——包里有两个可执行产品，另一个是图标生成器（`swift run MochiIconGen`），不写名字 SwiftPM 会报 `multiple executable products available`。

## Xcode 工程

另有一个 `macos/Mochi.xcodeproj`，**只用于产出可分发的 `.app`**（见 [ADR-0014](docs/adr/0014-packaging-and-distribution.md)）。它的 App target 通过 local package reference 依赖 `MochiCore`，不重复编译源码：

```bash
xcodebuild -project macos/Mochi.xcodeproj -scheme Mochi -configuration Release build
```

## 打包与发布

`macos/scripts/package.sh` 是打包的唯一真源，本地和 CI 调的是同一个脚本：release 构建 → 注入版本号 → 签名 → 产出 dmg。

```bash
macos/scripts/package.sh
```

产物落在 `macos/dist/`。版本号只从 HEAD 上的 git tag 推导（`v0.1.0` → `0.1.0`），没有 tag 时不写入版本号，「关于 Mochi」会显示 `dev`；想在打 tag 之前预演一次正式产物，用 `MOCHI_VERSION=0.1.0 macos/scripts/package.sh`。

发布由推 tag 触发，[`.github/workflows/release.yml`](.github/workflows/release.yml) 会在 `macos-26` runner 上跑同一个脚本、创建 GitHub Release 并附上 dmg：

```bash
git push origin v0.1.0
```

## Issue 追踪

Issue 和需求 spec 都在本仓库的 GitHub Issues 里，见 [docs/agents/issue-tracker.md](docs/agents/issue-tracker.md)。

## 文档导航

- [CONTEXT.md](CONTEXT.md) —— 领域术语与核心概念（Widget、Normal/Ghost Mode、Pin/Snap 等）
- [docs/adr/](docs/adr/) —— 架构决策记录
- [docs/agents/](docs/agents/) —— 面向 Agent 协作的流程文档（issue tracker、triage 标签等）
- [docs/design-language.md](docs/design-language.md) —— 视觉设计决定：材质、色彩、图标、窗口与工具栏的构成
- [docs/guide/](docs/guide/README.md) —— 写给普通用户的用户手册

## 修改界面文案时同步更新手册

[用户手册](docs/guide/README.md)里的界面名称、默认热键和设置项，都按源码里的界面文案逐字书写。改了界面文案、默认热键或设置项（增删、改名、改默认值、改生效时机）之后，用 `git grep` 在 `docs/guide/` 里搜一遍旧的文字，把受影响的页面一起改掉：

```bash
git grep -n "旧的界面文案" -- docs/guide/ README.md
```

手册首页写着它对照的 Mochi 版本，每次发版时核对一遍。
