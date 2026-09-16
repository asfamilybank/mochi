# Mochi

一个基于 Swift + AppKit/SwiftUI + WKWebView 的 macOS 原生桌面应用，把单个网页渲染成可自由摆放、可隐藏、可置顶的桌面浮窗（Widget），专为"焦点停留在其他应用时，仍可通过全局热键控制这个网页（尤其是视频播放）"这个场景设计。

v1 仅支持 macOS；未来若开发 Windows 版本，是同一仓库下完全独立的代码，只共享领域文档。

## 文档

- [CONTEXT.md](CONTEXT.md) —— 领域术语与核心概念（Widget、Normal/Ghost Mode、Pin/Snap 等）
- [docs/adr/](docs/adr/) —— 架构决策记录
- [docs/agents/](docs/agents/) —— 面向 Agent 协作的流程文档（issue tracker、triage 标签等）

## 安装

需要 macOS 26 或更高版本，只提供 Apple Silicon（arm64）构建。

1. 从 [Releases](https://github.com/asfamilybank/mochi/releases) 下载最新的 `Mochi-x.y.z.dmg`。
2. 双击挂载，把 `Mochi.app` 拖进旁边的「应用程序」快捷方式。
3. 第一次打开会被系统拦下，提示无法验证开发者或是否含有恶意软件。**这是预期内的**，不是下载坏了——Mochi 目前只做 ad-hoc 签名，没有 Apple Developer ID 证书与公证（原因见 [ADR-0014](docs/adr/0014-packaging-and-distribution.md)）。按下面任一种方式放行一次，之后每次打开都不会再问。

**放行方式一：系统设置**

被拦下之后，打开「系统设置 → 隐私与安全性」，向下滚到「安全性」一节，那里会出现一行「已阻止使用 Mochi」，点它右边的 **「仍要打开」**，再在弹窗里确认。这行提示只在被拦下后的一小时内出现；错过了就再双击一次 `Mochi.app` 把它重新触发出来。

**放行方式二：终端**

直接去掉下载时被打上的隔离标记：

```bash
xattr -dr com.apple.quarantine /Applications/Mochi.app
```

> 网上流传的「右键 →『打开』」那条老办法在 macOS 15 之后已经被移除，照着做只会白折腾。

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

`swift run` 必须带上产品名——包里有两个可执行产品，另一个是图标生成器（`swift run MochiIconGen`），不写名字 SwiftPM 会报 `multiple executable products available`。

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
