# 热键传递采用 macOS 原生按键注入（CGEventPostToPid）

调研发现 macOS 有 `CGEventPostToPid`，可以把合成按键事件直接投递给指定进程、不需要目标 App 处于前台/有焦点，也不会抢占用户当前焦点，效果等同真实按键（`isTrusted: true`）。既然 v1 只做 macOS 原生开发（见 [ADR-0007](0007-native-per-platform-no-shared-code.md)），热键传递直接采用这条原生路径，不需要考虑"JS 合成事件"这种跨平台兼容方案。

代价是需要用户在"系统设置 → 隐私与安全性 → 辅助功能"里手动授权一次（跟 Keyboard Maestro、BetterTouchTool 这类工具的权限模型一样）。

## Consequences

- 需要在首次使用热键传递功能时引导用户去系统设置里手动授权"辅助功能"，这是一次性的额外 onboarding 步骤。
- 需要持续关注 macOS 新版本（如 Tahoe 之后）对未签名/未公证进程发送合成事件的限制变化，正常签名 + 公证分发的情况下目前不受影响。
- 若未来启动独立的 Windows 代码（见 [ADR-0007](0007-native-per-platform-no-shared-code.md)），需要为它单独设计热键传递方案（大概率是 JS 合成事件，因为 Windows 没有等价的、不抢焦点的原生按键注入 API），不能直接复用这里的结论。
