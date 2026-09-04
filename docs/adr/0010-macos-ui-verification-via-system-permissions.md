# macOS UI 验证：用户手动授予系统权限 + 只读检查，不建应用内调试通道

Claude 验证 Mochi 的 UI 改动时，长期只能靠 `swift build && swift run` 编译通过 + 进程存活兜底，视觉细节必须用户亲自运行查看才能反馈——这个缺口曾直接导致一次回归漏检：`a4880b1`（统一 Normal Mode toolbar 为原生 `NSToolbar` + Smart Address Field）引入了布局错误和地址栏缺失，而实现时就已经预见"沙盒内验证不了，交给真机验证"，但仍然提交了。

决定：用户手动在系统设置里，一次性给 **Claude.app**（桌面客户端本体，不是某个终端 App）授予「屏幕录制」+「辅助功能」两项权限（Claude 不能代为操作系统设置）。授权后，Claude 通过 macOS 自带命令行工具——`screencapture -l<windowID>` 按窗口截图、`osascript` + System Events 查询无障碍树（UI 元素的 role/frame/是否存在）——对真实运行中的 Mochi 窗口做只读检查，零新增代码和依赖，具体命令见 [docs/agents/macos-ui-verification.md](../agents/macos-ui-verification.md)。

明确否决了两个备选方案：给 Mochi 加 DEBUG-only 的应用内调试 socket 通道（系统权限已经够用，不值得为此增加项目复杂度）；引入 XCUITest（项目故意用纯 SPM、不建 `.xcodeproj`，见 [ADR-0007](0007-native-per-platform-no-shared-code.md) 同一系脉络的工具链取舍，XCUITest 需要的测试 host/scheme 管理与此冲突）。

## Consequences

- 这套能力只覆盖布局错误、UI 元素缺失这类结构/尺寸问题的只读检查；不做模拟点击/拖拽等交互自动化，也不做真实录屏（`screencapture -V`）。需要看动态时序时改用连续截图序列（约每 0.3 秒一张，5~10 张）；真需要看视频效果，Claude 应直接告知用户由其人工验证，不要用截图序列勉强凑合判断。
- Liquid Glass 效果（`NSGlassEffectView` 等）继续坚持 [ADR-0008](0008-macos-26-liquid-glass-baseline.md) 的原生 API 路线，不自建近似实现；但截图/离屏渲染出的毛玻璃效果仍可能因真实合成时机与肉眼所见存在细微差异，这类效果的最终视觉验收始终以用户实机确认为准，不能仅凭截图判定通过。
- 权限授予对象是 Claude.app 整个客户端，且必须在授权后完全退出重启一次才会对运行中的进程生效；一旦撤销、或客户端更新/重装后权限被系统重置，后续验证会静默退化回"无法截图"，排错步骤见操作手册。
