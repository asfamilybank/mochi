## Agent skills

### gh CLI 注意事项

`gh issue create` 不支持 `--json`（只有 `gh issue view`/`gh issue list` 等只读命令支持）——批量建 issue 时从返回的 URL 里 `basename` 取 issue number，需要数据库 id（比如挂 `blocked_by` 依赖）时再用 `gh api repos/<owner>/<repo>/issues/<n> --jq .id` 单独取。

`gh issue view <n> --comments` 只输出评论列表、不含 issue 正文——评论数为 0 时输出为空（exit 0，不是命令坏了，别重试）。要读正文/摘要用 `gh issue view <n> --json title,body,comments --jq '...'`。

### Issue tracker

Issues live in this repo's GitHub Issues (uses the `gh` CLI). See `docs/agents/issue-tracker.md`.

多个独立 agent 会话按 `ready-for-agent` 标签认领实现，仓库状态可能在长会话过程中被别的 session 改变——依赖"仓库现在有没有代码/某个文件在不在"做判断前，重新 `git log`/`git ls-files` 查一遍，不要用会话早期的结论。

Issue 的 comments 里可能留有前序 session 的"本地实现进度"/"有意延后"说明（对应改动可能还在本地未 push，`gh issue list` 仍显示 open）——领任务前 `gh issue view <n> --comments` 把评论一起读，别只看 AC checklist 和 open/closed 状态判断"这活儿做完没"。

### Triage labels

Default vocabulary, label strings equal to their names. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout — `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

### macOS app (`macos/`)

- Swift Package Manager 项目，不是 `.xcodeproj`——`open macos/Package.swift` 直接在 Xcode 里当项目打开。本机没有 xcodegen/tuist，这是刻意选择而非临时凑合。
- 构建/测试：`cd macos && swift build` / `swift test`。
- 运行时配置文件：`~/Library/Application Support/Mochi/config.toml`。
- ADR-0008 的 macOS 26 baseline 落到 `Package.swift` 需要 `swift-tools-version:6.2`+ 才能写 `.macOS(.v26)`；同时要加 `swiftLanguageModes: [.v5]`（在 `Package(...)` 参数列表里排在 `targets:` 之后，顺序反了编译器报错），否则默认转成 Swift 6 严格并发检查，`MochiCore` 里直接调 AppKit/WebKit 的同步方法会全部报 actor-isolation 错误。
- `NSGlassEffectView`/`NSGlassEffectContainerView`（真 Liquid Glass 材质）已经在本机 SDK 里（`AppKit.framework/Headers/NSGlassEffectView.h`），ADR-0008 不是画饼，可以直接用。
- Bash 工具沙盒没有屏幕录制/辅助功能权限：截不了原生窗口的图，`osascript` 操作 System Events 会报"不允许辅助访问"。UI 改动只能靠 `swift build && swift run` 编译通过 + 进程不崩溃兜底验证，视觉细节要请用户自己跑起来看。
- 验证"进程不崩溃"没有 `timeout` 命令（macOS 默认没有 GNU coreutils）：用 `swift run Mochi > log 2>&1 & PID=$!; sleep 3; kill -0 $PID && kill $PID`。
- `NSGlassEffectView` 等新 API 的属性面（`contentView`/`cornerRadius`/`tintColor`/`style`）文档没写全，不确定时直接读 SDK header（`AppKit.framework/Versions/C/Headers/NSGlassEffectView.h`），别猜。
- Liquid Glass 激活态（Pin/Ghost Mode 等）如果用 `CALayer.backgroundColor`/`borderColor` 实现染色，那是 `CGColor` 快照，不会像 `NSColor` 属性（`contentTintColor`/`tintColor`）一样自动响应系统强调色/外观切换——要手动监听 `NSColor.systemColorsDidChangeNotification` + `effectiveAppearance` 变化重新赋值。
- Swift Testing 的 `#expect(a == b)` 混合比较裸 `Double` 和裸 `CGFloat`（如 `CGRect.minY`/`.maxX`）时可能误报失败——即使 `print(a == b)` 打出 `true`、`.build` 全清也复现。比较前把 CGFloat 一侧显式转 `Double(...)`；碰到"打印值明明相等却报 failed"，先怀疑这个，别急着查产物逻辑。
- 实现窗口拖拽吸附/磁性对齐一律用 `NSWindow.constrainFrameRect(_:to:)`（子类重写），别用 `windowDidMove` 回调里 `setFrameOrigin` 纠正——后者和 AppKit 自己的拖拽循环抢着决定坐标，慢速拖动会有肉眼可见的抖动；前者是 AppKit 拖拽时自己会调用的钩子，同一步里只有一个权威在决定坐标。
- `FakePlatformOps` 里追踪调用用的带 label 元组数组（如 `[(pinned: Bool, windowID: Int)]`）不满足 `Equatable`，测试里不能直接 `#expect(arr == [...])`——按字段 `.map(\.field)` 分别比较。

### 视觉设计（design/）

`/design` 画布的 Design Components 工作文件在 `design/<name>/`（如 `design/mochi/`），改视觉稿改 `.dc.html` 源文件后重新 seed，不要手改发布出去的那份 `.html`。蒸馏后的规格记在 `docs/design-language.md`。

### 关闭 issue

commit message 里写 `Closes #<n>`，push 后让 GitHub 自动关闭——不要手动跑 `gh issue close`。
