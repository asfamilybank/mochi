## Agent skills

### gh CLI 注意事项

`gh issue create` 不支持 `--json`（只有 `gh issue view`/`gh issue list` 等只读命令支持）——批量建 issue 时从返回的 URL 里 `basename` 取 issue number，需要数据库 id（比如挂 `blocked_by` 依赖）时再用 `gh api repos/<owner>/<repo>/issues/<n> --jq .id` 单独取。

`gh issue view <n> --comments` 只输出评论列表、不含 issue 正文——评论数为 0 时输出为空（exit 0，不是命令坏了，别重试）。要读正文/摘要用 `gh issue view <n> --json title,body,comments --jq '...'`。

批量建互相引用的 issue（body 里既要插值 issue 号又要保留 markdown 反引号）时，`--body` 的 heredoc 必须用 `<<'EOF'`（quoted）+ 占位符（如 `__T1__`）+ 创建后 `${body//__T1__/#$t1}` 替换——不加引号的 `<<EOF` 会把反引号当命令替换执行。

同一个坑在 `gh issue comment --body "..."` 上也成立：双引号里的 markdown 反引号仍是命令替换，症状是 `accepts 1 arg(s), received 2`（替换结果带空格被拆成两个参数）——长 body 一律先写文件再 `--body-file`。

`gh api graphql`/`gh api repos/<owner>/<repo>/...` 这类裸 API 调用不会像 `gh issue view` 那样自动从当前 clone 推断仓库——先 `gh repo view --json owner,name -q '.owner.login + "/" + .name'` 拿准确的 owner/repo，不要凭记忆/猜测拼。

由于 push 只能手动执行（见上文"线上资源只读"），本地常年积累多个未 push 的 commit——`/code-review` 默认的 `git diff @{upstream}...HEAD` 可能因此膨胀到几千甚至上万行、混进早前 session 的历史工作。审查"这次任务做的改动"时改用 `git diff HEAD`（或显式限定本次改的文件），不要把整个未 push 的分支历史当审查范围。

`git diff HEAD` 默认不包含本次新建的 untracked 文件——喂给 `/code-review` 之类的审查流程前先 `git add -N <file>`（intent-to-add，不会真正暂存内容）让新文件以整份新增的形式出现在 diff 里，否则新文件的实现会被完全漏审。

### Issue tracker

Issues live in this repo's GitHub Issues (uses the `gh` CLI). See `docs/agents/issue-tracker.md`.

#### 自动执行豁免（/mattpocock-skills:to-spec、to-tickets、implement 专用）

按全局 CLAUDE.md「线上资源豁免」机制，以下 gh 子命令豁免为可自动执行（同时已在 `.claude/settings.json` 的 `permissions.allow` 里写死），仅限使用 `/mattpocock-skills:to-spec`、`/mattpocock-skills:to-tickets`、`/mattpocock-skills:implement` 这三个 skill 发布/维护 issue tracker 内容时使用：

- `gh issue create`（含 `--title`/`--body`/`--label`/`--parent`/`--blocked-by` 等参数）
- `gh issue edit`（含 `--add-label`/`--add-sub-issue`/`--add-blocked-by` 等参数）
- `gh issue comment`

**例外说明**：这三条命令的 `--title`/`--body`/`--label` 内容每次调用天然不同，没法像 deploy 脚本那样枚举出固定不变的完整命令字符串——因此这里破例用前缀匹配（`Bash(gh issue create:*)` 等），而不是全局规则默认要求的精确完整字符串。这是针对"参数天然可变"这一类命令的刻意例外，不代表放宽其它豁免条目的枚举要求。

**`gh api ... /dependencies/blocked_by`（建 GitHub 原生 issue 依赖关系）也豁免为可自动执行**，但实现方式跟上面三条不一样：这条命令的可变部分（issue 号）卡在路径中间，不是像 `--title`/`--body` 那样跟在固定子命令后面的参数，用简单前缀+`:*`只能做到"放行这个仓库 `issues/` 下任意子路径的 POST"（比如 `/labels`、`/lock` 等其它没打算豁免的端点），比"只豁免 blocked_by 这一条"宽。因此改用 `.claude/settings.json` 里的一条 `PreToolUse` hook（正则精确匹配 `^gh api --method POST repos/asfamilybank/mochi/issues/[0-9]+/dependencies/blocked_by`，命中才输出 `permissionDecision: allow`，不命中则不干预、走正常权限流程），而不是 `permissions.allow` 里的前缀条目——只对这一条命令生效，不会放宽到同一路径下的其它 `gh api` 调用。

不在此豁免范围内、仍需人工执行的：`gh issue close`（按下方「关闭 issue」一节，靠 commit message 自动关闭，不要手动跑）、`gh issue delete`、任何 `gh pr *`、`gh api` 对 `.../dependencies/blocked_by` 以外的其它端点，以及其它未列出的 `gh` 子命令。

多个独立 agent 会话按 `ready-for-agent` 标签认领实现，仓库状态可能在长会话过程中被别的 session 改变——依赖"仓库现在有没有代码/某个文件在不在"做判断前，重新 `git log`/`git ls-files` 查一遍，不要用会话早期的结论。

Issue 的 comments 里可能留有前序 session 的"本地实现进度"/"有意延后"说明（对应改动可能还在本地未 push，`gh issue list` 仍显示 open）——领任务前 `gh issue view <n> --comments` 把评论一起读，别只看 AC checklist 和 open/closed 状态判断"这活儿做完没"。

GitHub 原生 `blocked_by` 依赖（`issue-tracker.md` 写在"Wayfinding operations"节下）不止 `/wayfinder` 能用，`/to-tickets` 这类有依赖关系的拆票也该建。

多 session 并发时 `CLAUDE.md` 自身也可能被别的 session 同时改动（比如学习记录更新）——commit 前 `git status` 看到 `CLAUDE.md` 有非本次任务的改动，按文件名精确 `git add`，不要用 `-A`/`.` 把它一起带上。`git reset`/`git commit --amend` 之类改写历史的操作（哪怕只是改 commit message）也可能顺带清空其他文件上尚未提交的改动——修改已推送的 commit 前先确认工作区没有别的 session 留下的草稿。这类操作前还要先 `git fetch` 核对 `@{upstream}`：用户会在轮次之间自己 push，不能因为"push 由用户手动执行"就假定 HEAD 还没推送（本仓库真实踩过：amend 了一个已在 origin/main 上的 commit）。需要撤销这类改写时用 `git reset --soft origin/main`，别用 `--hard`。

重新设计一个已经 CLOSED 的 issue 所描述的（已上线）行为时，新开一个 issue 引用旧的，不要重开/改写旧 issue 的验收标准——旧记录保留作历史存档。

commit message 里用 `Closes #<n>` 关闭多个 issue 时，逗号列表（`Closes #13, #14, #15`）只会关闭紧跟关键字的第一个，其余只是被关联（cross-reference）不会关闭——每个号码前都要重复关键字：`Closes #13`、`Closes #14`、`Closes #15` 各自一行（或都用 `Closes` 而不是省略后续的关键字）。

顶层 spec issue（几十条 user stories 那种）即使仍是 OPEN，也可能已经被拆解成一串子 issue（如 #1→#2-22、#18→#19-22）——`/implement` 前先 `gh issue list` 看有没有已存在的子任务，别把整份 spec 当一个可执行单元直接实现。

反过来，子 issue（如 #19-22）仍显示 OPEN 不代表没人做——可能有 session 直接照着父 issue（如 #18）的合并版规格一次实现完，commit message 只写了 `Closes #18`，没有引用子票号。领子票前先看父 issue 是否已 CLOSED，若是，逐条核对子票 AC 是否已被父票的实现覆盖，不要假设 OPEN=待办。

拆出来的子 issue 可能只在 body 里用 "## Parent #29" / "## Blocked by #35" 记归属和依赖，并没有建 GitHub 原生 parent/sub-issue 或 `blocked_by` 关系（#29→#35/#39/#40/#41/#43 就是这样）——`gh api graphql` 查 `parent`/`subIssues` 返回全空不等于没拆，得读 body 里的这两节。

### Triage labels

Default vocabulary, label strings equal to their names. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout — `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

新决定推翻已有 ADR 时不重写旧文件：旧 ADR 顶部加一行"已被 ADR-NNNN 取代"的引用说明保留作历史记录，新决定另开一个顺序编号的新 ADR。

### macOS app (`macos/`)

- Swift Package Manager 项目，不是 `.xcodeproj`——`open macos/Package.swift` 直接在 Xcode 里当项目打开。本机没有 xcodegen/tuist，这是刻意选择而非临时凑合。
- 构建/测试：`cd macos && swift build` / `swift test`。cwd 有时会在会话中途（尤其是穿插了 Skill/Agent 调用之后）跳回仓库根目录，报 `Could not find Package.swift in this directory or any of its parent directories` 时先 `cd macos` 重试，不是构建配置坏了。
- 运行时配置文件：`~/Library/Application Support/Mochi/config.toml`。
- ADR-0008 的 macOS 26 baseline 落到 `Package.swift` 需要 `swift-tools-version:6.2`+ 才能写 `.macOS(.v26)`；同时要加 `swiftLanguageModes: [.v5]`（在 `Package(...)` 参数列表里排在 `targets:` 之后，顺序反了编译器报错），否则默认转成 Swift 6 严格并发检查，`MochiCore` 里直接调 AppKit/WebKit 的同步方法会全部报 actor-isolation 错误。
- `NSGlassEffectView`/`NSGlassEffectContainerView`（真 Liquid Glass 材质）已经在本机 SDK 里（`AppKit.framework/Headers/NSGlassEffectView.h`），ADR-0008 不是画饼，可以直接用。
- Bash 工具沙盒默认没有屏幕录制/辅助功能权限：`screencapture` 会报 "could not create image from display"，`osascript` 操作 System Events 会报"不允许辅助访问"。这两项权限可以由用户一次性手动授予 Claude.app 解除（Claude 不能代为操作系统设置），授予后布局错误、UI 元素缺失类问题可以用截图 + 读无障碍树只读验证，不必再让用户亲自跑起来查看——具体命令和能力边界见 [docs/agents/macos-ui-verification.md](docs/agents/macos-ui-verification.md)（[ADR-0010](docs/adr/0010-macos-ui-verification-via-system-permissions.md)）。仍然没有这两项权限时（比如换了台机器），才退回"编译通过 + 进程不崩溃"兜底 + 请用户自己看。
- 没有屏幕录制/辅助功能权限时（包括会话中途被系统撤销）别直接退回"编译通过 + 进程不崩溃"兜底，还有两条不依赖 TCC 的路测真实布局：① 在 app 里加一段环境变量开关的临时探针，`setFrame` 逐点扫窗口宽度并把几何打到 stdout；② 写个独立的 `swift xxx.swift` harness 复刻同一套控件与约束，先用真实阈值（工具栏行高、收纳临界宽度等）校准可信度，再批量试变体——比反复重建整个 app 快一个量级。探针提交前记得删干净。
- Mochi 启动时 `config.toml` 解析失败会走 `presentAlert` 的模态 `NSAlert` 卡住主线程，表现为"进程活着但 AX 查不到窗口、`screencapture -l` 也失败"——别误判成权限没生效。另外 app 退出时会整份重写 `config.toml`（手工 `>>` 追加 TOML 段容易造出重复 section 触发上面这个坑），探针类实验前先备份、跑完还原；用户手上开着 Mochi 时不要再起第二个实例，两者共享同一份配置文件。
- 「辅助功能」和「自动化」（Automation）是两个独立的 TCC 权限类别——只开「辅助功能」，`osascript` 操作 System Events 依然会报"不允许辅助访问"，还要在「自动化」里单独把 Claude 对 System Events 的授权打开；改动任一权限后都要完全退出重启一次 Claude.app（`⌘Q`）才生效，不会热更新。
- 验证 Mochi 窗口只能用 `screencapture -l<windowID>` 按窗口 ID 截图（窗口 ID 用 `CGWindowListCopyWindowInfo` 查，System Events 的 `id of window` 属性不支持）——**禁止用全屏 `-x` 或区域 `-R`**，这两种会把屏幕上恰好可见的其他窗口一起拍进去，曾真实发生过误拍到用户私人聊天内容的事故。
- 验证"进程不崩溃"没有 `timeout` 命令（macOS 默认没有 GNU coreutils）：用 `(swift run Mochi > log 2>&1 &); sleep 12; PID=$(pgrep -x Mochi); [ -n "$PID" ] && kill $PID`。`$!` 是 `swift run` 自己的 pid，Mochi 崩了它照样活着，只有 `pgrep -x Mochi` 才是真在验证；首次运行含编译时间，`sleep 3` 会在 build 还没结束时误判。`kill`（SIGTERM）不走 `applicationWillTerminate`，所以这种冒烟测试不会重写 `config.toml`。
- `NSGlassEffectView` 等新 API 的属性面（`contentView`/`cornerRadius`/`tintColor`/`style`）文档没写全，不确定时直接读 SDK header（`AppKit.framework/Versions/C/Headers/NSGlassEffectView.h`），别猜。
- Liquid Glass 激活态染色、加载进度条填充色这类如果用 `CALayer.backgroundColor`/`borderColor` 实现，那是 `CGColor` 快照，不会像 `NSColor` 属性（`contentTintColor`/`tintColor`）一样自动响应系统强调色/外观切换——要手动监听 `NSColor.systemColorsDidChangeNotification` + `effectiveAppearance` 变化重新赋值。
- Swift Testing 的 `#expect(a == b)` 混合比较裸 `Double` 和裸 `CGFloat`（如 `CGRect.minY`/`.maxX`）时可能误报失败——即使 `print(a == b)` 打出 `true`、`.build` 全清也复现。比较前把 CGFloat 一侧显式转 `Double(...)`；碰到"打印值明明相等却报 failed"，先怀疑这个，别急着查产物逻辑。
- 表驱动测试用 Swift Testing 的 `@Test(arguments: [(a: Bool, b: Double?), ...])` + 单个 tuple 形参（不是多形参笛卡尔积），跑起来报 "with N test cases"；期望值声明成 `Double?` 就能用 `nil` 表达"这一格根本不该产生任何调用"，比断言"调用了但值没变"更准。
- 改 `DefaultHotkeys` 的成员会连带编译失败 `EmptyPageView.swift`——空页面的"默认热键速览"徽章直接引用它。徽章只放在 Normal Mode 下真的有效的热键：空页面是 Normal Mode 内容，而 Hidden 是 Ghost-Mode-only，放上去等于在唯一会看到它的界面上宣传一个必然 no-op。
- 实现窗口拖拽吸附/磁性对齐一律用 `NSWindow.constrainFrameRect(_:to:)`（子类重写），别用 `windowDidMove` 回调里 `setFrameOrigin` 纠正——后者和 AppKit 自己的拖拽循环抢着决定坐标，慢速拖动会有肉眼可见的抖动；前者是 AppKit 拖拽时自己会调用的钩子，同一步里只有一个权威在决定坐标。
- `FakePlatformOps` 里追踪调用用的带 label 元组数组（如 `[(pinned: Bool, windowID: Int)]`）不满足 `Equatable`，测试里不能直接 `#expect(arr == [...])`——按字段 `.map(\.field)` 分别比较。
- `PlatformOps` 里像 `onSettingsRequested`/`onNavigationFinished`/`onWindowWillClose` 这类没有真实业务消费者的裸回调，仓库里全部没写单元测试（只测有消费者的，如 `onPageTitleChanged`→`AddressBarController`）——新增回调默认不必为 `FakePlatformOps` 补 round-trip 测试，除非 issue AC 明确要求"验证回调传递"，这时才直接对 `FakePlatformOps` 写最小验证（注册 handler + `simulateXxx` + 断言），不必为此新造一个业务消费类型。
- `AppKitPlatformOps.swift` 的 Normal Mode toolbar 自 #18 起已是 ADR-0009 的原生 `NSToolbar` 实现（#24 起样式为 `.unified`，见下条），不再是 ADR-0004 的自绘两行式；但 `NSToolbar.isVisible` 切换是否会引发窗口尺寸变化沙盒内验证不了，改动前别假设已经生效，交给真机验证。
- `NSToolbar` 里**相邻的一串 `item.view` 自绘视图项会被 AppKit 一步整块收进溢出菜单**——想让其中一个先于另一个收纳（靠 `visibilityPriority` 排序），至少要把先收的那个做成标准 `image` + `target/action` 的 `NSToolbarItem`。代价：标准 item 没有 `contentTintColor`、也不吃固定按钮尺寸，图标会按 AppKit 自己的控件色/度量渲染而不是 `DesignTokens`（ADR-0011 实测）。
- `NSWindow.toolbarStyle = .unifiedCompact` 把整行高度锁在 40pt，工具栏项再怎么加高都顶不动——要 Safari 那种 52pt 的整行观感必须用 `.unified`（ADR-0011 实测）。
- `NSToolbarItem` 的 `maxSize` 会被宿主视图的**水平 intrinsic 宽度**压掉：`NSTextField`/`NSSearchField` 只有真的持有文字时才报出 intrinsic 宽度，`NSToolbarItem` 一读到就把 `maxSize` 收成 fitting size。典型症状是"空态能在 min/max 之间弹性伸缩、第一次有内容之后永久卡在最小宽度"。要让宽度只由自己的 min/max 约束 + 工具栏剩余空间决定，就重写 `intrinsicContentSize` 把水平方向返回 `NSView.noIntrinsicMetric`（高度照传 `super`）。
- `NSTextField` 换成 `NSSearchField` 时容易漏迁移原有的 `heightAnchor` 约束（新控件退化成默认高度，和其他工具栏按钮对不齐）；`NSSearchField` 自带的清除按钮（"×"）会绕开自定义 delegate 直接清空 `stringValue`——字段内容是程序算出来的而非自由文本查询时，要 `(field.cell as? NSSearchFieldCell)?.cancelButtonCell = nil` 禁用它。
- `WKWebView.load(_:)` 调用后 `.url` 不会同步更新（滞后一个 KVO tick）——导航发起瞬间要立刻展示目标地址（如智能地址栏）不能读 `webView.url`，得在调用 `.load()` 时同步写一份本地变量。
- 跨导航持有派生状态（如页面标题/host）的 controller，每次真实导航要整体重置旧状态，不能只更新其中一个字段——否则会在新页面还没上报标题前，短暂展示上一个页面的残留信息。
- 新增会写 `WidgetConfig` 的功能（如设置面板）时，构造函数接收 `currentConfig: () -> WidgetConfig` + `persist: (@escaping (WidgetConfig) -> WidgetConfig) -> Void` 这对 transform 闭包，直接传入 `AppDelegate` 已有的 `persist(_:)` 函数本体——不要让新类缓存自己的配置快照，否则会在多个写入源之间产生"用旧快照覆盖新状态"的竞态。
- `GlobalHotkeyRegistry` 没有 unregister 能力：设置面板对热键映射表/内置脚本开关的增删改只能做到"立即持久化到配置文件"，运行中的 `Orchestrator`/`HotkeyForwarder`/脚本注入不会热更新，需要重启 Mochi 才生效——别假设这类编辑是实时生效的。
- 同一窗口内容区要在 `WKWebView` 和原生 SwiftUI 内容（`NSHostingView`）之间切换显示时，把两者都放进一个共享的 `NSView` 容器、各自用 Auto Layout 四边 pin 满容器、用 `isHidden` 切换可见性——容器本身的 sizing 行为和裸 `webView` 一致，外层 `NSStackView` 布局不用跟着改。
- 实现一个 ticket 前先搜一下 spec 里提到的新字段名/新类型（如 `grep -rn <name>`）——早前 session 实现相邻 ticket 时可能已经顺手把这个 ticket 的部分数据层/设置面板 UI 打好了（例如 #13 的 commit 里已经带了 #16 的 `startupTarget` 字段和设置面板三态选择器），不能假设从零开始。

### 关闭 issue

commit message 里写 `Closes #<n>`，push 后让 GitHub 自动关闭——不要手动跑 `gh issue close`。

一个 commit 要关闭多个 issue 时，`Closes #13, #14, #15` 这种逗号列表只会关闭紧跟关键字的第一个，其余只是被关联（cross-reference）不会关闭——每个号码前都要重复关键字：`Closes #13`、`Closes #14`、`Closes #15` 各自一行（或都用 `Closes` 而不是省略后续的关键字）。
