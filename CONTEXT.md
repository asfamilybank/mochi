# 桌面 Web Widget 应用

一个基于 Swift + AppKit/SwiftUI + WKWebView 的 macOS 原生桌面应用（v1 仅支持 macOS，不做跨平台；未来若开发 Windows 版本，是同一仓库下完全独立的代码，只共享这份领域文档，见 [ADR-0007](docs/adr/0007-native-per-platform-no-shared-code.md)），把单个网页渲染成可自由摆放、可隐藏、可置顶的桌面浮窗，专为"焦点停留在其他应用时，仍可通过全局热键控制这个网页（尤其是视频播放）"这个场景设计。

## Language

**Widget**:
应用的核心浮窗单元，配置与运行时窗口实例一一绑定；v1 只加载一个固定 URL，不支持多标签页，也不支持同时开出多个独立的 Widget 窗口（见 [ADR-0002](docs/adr/0002-widget-config-instance-unified.md)）。Widget 可以被关闭（Normal Mode 下的关闭按钮或 `⌘W`）——关闭是真关闭：窗口与网页上下文一起销毁、页面停止运行，但应用本身仍在托盘运行。从托盘或 Dock 图标重新打开 Widget 等同于**一次全新启动**：重新解析启动内容、重新加载页面、回到 Normal Mode；只有窗口几何（位置/尺寸/缩放）沿用持久化的值。
_Avoid_: 浮窗（仅口语化描述，正式术语统一用 Widget）

**Normal Mode（普通模式）**:
Widget 的默认状态，定位是**一个普通的 macOS 窗口**——普通窗口层级（不置顶）、可获得焦点、网页内容完全不透明可正常交互、不做鼠标穿透；原生标题栏与工具栏合并为同一行的原生 `NSToolbar`（地址栏与其他工具）常驻显示（见 [ADR-0009](docs/adr/0009-unified-native-toolbar-chrome.md)，结构与响应式收纳细节见 [ADR-0011](docs/adr/0011-normal-mode-toolbar-safari-alignment.md)）。凡是原生窗口已经提供的能力（拖动、缩放、最小化、关闭）Mochi 不再另造一套（见 [ADR-0012](docs/adr/0012-ghost-mode-as-pure-invisibility.md)）。
_Avoid_: 自绘工具栏（ADR-0004 的旧表述，已被 ADR-0009 的原生 `NSToolbar` 方案取代）

**Smart Address Field（智能地址栏）**:
Normal Mode 工具栏里的地址栏，按页面状态自动切换显示内容：加载完成且未交互时显示页面标题；鼠标悬停或点击时显示 URL（点击后可编辑）；页面加载中，无论是否有交互都恒定显示 URL。空页面（未导航）状态不受这套切换影响，固定显示占位提示文字，直到用户真正导航一次（见 [ADR-0009](docs/adr/0009-unified-native-toolbar-chrome.md)）。尾部内嵌一个刷新图标（取代原来独立的工具栏刷新按钮），Empty Page 态下隐藏；不含"加载中变停止按钮"这个中止导航能力（见 [ADR-0011](docs/adr/0011-normal-mode-toolbar-safari-alignment.md)）。
_Avoid_: 地址栏始终可编辑（design-language.md 里的旧表述，已被这套双态切换取代，不再是唯一行为）

**Loading Progress Bar（加载进度条）**:
Normal Mode 工具栏下方一条随页面真实加载进度填充的细线，加载完成后淡出消失，不加载时不占用界面空间。
_Avoid_: 无

**Ghost Mode（幽灵模式）**:
Widget 的隐身状态，由全局热键整体切换开关。它是一个**不可拆的、永不获得焦点的纯隐身状态**——任何需要用户交互的东西都不属于它（见 [ADR-0012](docs/adr/0012-ghost-mode-as-pure-invisibility.md)，绑定性原则的出处是 [ADR-0006](docs/adr/0006-ghost-mode-is-a-bundled-state.md)）。以下五件事绑定发生，没有中间态：
- 原生窗口装饰和工具栏一起隐藏，只留纯网页内容；
- 透明度降到设定的目标值；
- 开启鼠标穿透；
- **始终置顶**（置顶不再是独立开关，只在隐身场景下才有意义）；
- **永不获得焦点**——进入/停留在 Ghost Mode 期间窗口不成为 key window；只有退出 Ghost Mode 时才激活应用。

退出方式是再次按热键，或点击系统托盘图标（托盘图标在应用运行期间常驻显示，不区分模式）。应用重启后一律先回到 Normal Mode，不自动恢复 Ghost Mode 状态。Ghost Mode 下没有刷新、没有缩放、没有工具栏——要操作就先退出隐身。
_Avoid_: 召唤工具栏（ADR-0006 的旧设计，已被 ADR-0012 砍掉；用户要操作工具栏应先退出 Ghost Mode）

**Hidden（隐藏 / 老板键）**:
Ghost Mode 内部的一个独立可见性维度，由一个仅在 Ghost Mode 生效的全局热键切换：窗口**完全看不见，但仍然存在、网页继续运行**（视频不会停）。这是它跟"关闭 Widget"的分界线——关闭是销毁并停止，Hidden 只是看不见。热键一直保持隐藏，直到再按一次热键取消，或退出 Ghost Mode。实现上必须用 `alphaValue = 0` 而非 `orderOut`，否则 WebKit 会因窗口被判定遮挡而节流渲染，破坏"页面继续跑"这条语义（见 [ADR-0012](docs/adr/0012-ghost-mode-as-pure-invisibility.md)）。
_Avoid_: 快速隐藏（旧名，当时是 Normal Mode 专用能力，已随 Normal Mode 回归普通窗口而移除）；收起（一个被否决的中间概念，⌘W 是真关闭，不是收起）

**Mouse-Entered Avoidance（鼠标移入避让）**:
一个可关闭的偏好（默认开启），只在 Ghost Mode 生效：鼠标移入 Widget 所在区域时窗口让开（不可见），**移出即恢复**。它是"避让"而非"隐藏"——存在的理由是穿透状态下 Widget 会挡视线，而不是要把它藏起来。与 Hidden 相互独立、各自记账：可见性 = 非 Hidden 且非（避让开启且鼠标在窗口上）。它属于"这个模式怎么表现"，不属于"这个模式是什么"，因此不算 Ghost Mode 绑定状态的组成部分（见 [ADR-0012](docs/adr/0012-ghost-mode-as-pure-invisibility.md)）。
_Avoid_: 鼠标移入即隐藏（ADR-0006 的旧表述，当时是恒开的、且移出不恢复）

**Mouse Passthrough（鼠标穿透）**:
Ghost Mode 内置的能力，不能独立于 Ghost Mode 单独开启：开启后窗口不接收鼠标事件、点击直接作用于下方应用。
_Avoid_: 无

**Snap（吸附）**:
Normal Mode 专属的拖拽磁性吸附，可在设置中关闭：窗口边缘进入阈值距离会自动贴齐屏幕边缘/角落，继续朝反方向拖动超过阈值即可脱离，不是强制锁死。吸附阈值不暴露为配置项。它不跟着置顶一起内化进 Ghost Mode——Snap 只在用户手动拖拽时起作用，而 Ghost Mode 下窗口穿透且经常不可见、根本拖不动（见 [ADR-0012](docs/adr/0012-ghost-mode-as-pure-invisibility.md)）。保存的窗口位置所在显示器被移除时，自动收回主显示器内的安全默认位置。
_Avoid_: 磁吸（口语化说法，正式术语用 Snap/吸附）；Pin（置顶）（不再是独立术语——置顶已内化为 Ghost Mode 的固有属性，见 ADR-0012）

**Script Injection（脚本注入）**:
向 Widget 的网页上下文注入 JavaScript 的统一底层机制，来源分两类：内置的、随应用更新的官方网站适配脚本，与用户自定义脚本。两者技术权限相同，仅在 UI 上区分来源标注。
_Avoid_: 插件、扩展（这两个词专指"安装浏览器扩展/Chrome 插件"这个已延后到 v2 的独立话题，见 [ADR-0005](docs/adr/0005-defer-browser-extension-support.md)）

**Hotkey Forwarding（热键传递）**:
Ghost Mode 下，把全局热键按用户配置的映射表转发成一次页面按键，用于控制标准网页播放器（播放/暂停/快进等），不需要为每个网站写专属脚本。通过 `CGEventPostToPid` 直接投递给目标进程实现（见 [ADR-0003](docs/adr/0003-hotkey-forwarding-platform-split.md)）。
