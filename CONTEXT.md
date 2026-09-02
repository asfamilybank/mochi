# 桌面 Web Widget 应用

一个基于 Swift + AppKit/SwiftUI + WKWebView 的 macOS 原生桌面应用（v1 仅支持 macOS，不做跨平台；未来若开发 Windows 版本，是同一仓库下完全独立的代码，只共享这份领域文档，见 [ADR-0007](docs/adr/0007-native-per-platform-no-shared-code.md)），把单个网页渲染成可自由摆放、可隐藏、可置顶的桌面浮窗，专为"焦点停留在其他应用时，仍可通过全局热键控制这个网页（尤其是视频播放）"这个场景设计。

## Language

**Widget**:
应用的核心浮窗单元，配置与运行时窗口实例一一绑定；v1 只加载一个固定 URL，不支持多标签页，也不支持同时开出多个独立的 Widget 窗口（见 [ADR-0002](docs/adr/0002-widget-config-instance-unified.md)）。
_Avoid_: 浮窗（仅口语化描述，正式术语统一用 Widget）

**Normal Mode（普通模式）**:
Widget 的默认状态：原生 OS 窗口装饰（标题栏、关闭/最小化按钮、原生拖动手感）+ 自绘工具栏（地址栏与其他工具）常驻显示，网页内容完全不透明、可正常交互，不做鼠标穿透（见 [ADR-0004](docs/adr/0004-native-chrome-plus-custom-toolbar.md)）。

**Ghost Mode（幽灵模式）**:
Widget 的隐身状态，由默认热键整体切换开关，透明度、鼠标穿透、隐藏行为绑定在一起，不是若干独立开关的自由组合（见 [ADR-0006](docs/adr/0006-ghost-mode-is-a-bundled-state.md)）：
- 原生窗口装饰和自绘工具栏一起隐藏，只留纯网页内容；
- 透明度降到设定的目标值；
- 开启鼠标穿透——鼠标移入 Widget 所在区域时，整个窗口直接消失（内容不渲染），移出不会自动恢复，唯一退出方式是再次按热键关闭 Ghost Mode，或点击系统托盘图标（托盘图标常驻显示，不区分模式）；
- 有一个独立的次级热键，可以在不退出 Ghost Mode 的前提下临时"召唤"工具栏——召唤时工具栏以浮动叠加层的形式盖在网页内容上方（不改变窗口尺寸），并临时关闭穿透使其可交互；再次按热键收回、恢复穿透。
- 应用重启后一律先回到 Normal Mode，不自动恢复 Ghost Mode 状态。

**Mouse Passthrough（鼠标穿透）**:
Ghost Mode 内置的能力，不能独立于 Ghost Mode 单独开启：开启后窗口不接收鼠标事件、点击直接作用于下方应用。
_Avoid_: 无

**Pin（置顶）** / **Snap（吸附）**:
与 Ghost Mode 无关的常规窗口摆放功能，Normal Mode 和 Ghost Mode 下都可用。Snap 是拖拽时的磁性吸附：窗口边缘进入阈值距离会自动贴齐屏幕边缘/角落/其他 Widget，继续朝反方向拖动超过阈值即可脱离，不是强制锁死。保存的窗口位置所在显示器被移除时，自动收回主显示器内的安全默认位置。
_Avoid_: 磁吸（口语化说法，正式术语用 Snap/吸附）

**Script Injection（脚本注入）**:
向 Widget 的网页上下文注入 JavaScript 的统一底层机制，来源分两类：内置的、随应用更新的官方网站适配脚本，与用户自定义脚本。两者技术权限相同，仅在 UI 上区分来源标注。
_Avoid_: 插件、扩展（这两个词专指"安装浏览器扩展/Chrome 插件"这个已延后到 v2 的独立话题，见 [ADR-0005](docs/adr/0005-defer-browser-extension-support.md)）

**Hotkey Forwarding（热键传递）**:
Ghost Mode 下，把全局热键按用户配置的映射表转发成一次页面按键，用于控制标准网页播放器（播放/暂停/快进等），不需要为每个网站写专属脚本。通过 `CGEventPostToPid` 直接投递给目标进程实现（见 [ADR-0003](docs/adr/0003-hotkey-forwarding-platform-split.md)）。
