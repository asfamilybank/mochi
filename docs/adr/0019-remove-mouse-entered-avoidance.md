# 砍掉鼠标移入避让

[ADR-0012](0012-ghost-mode-as-pure-invisibility.md) 把"鼠标移入即隐藏"从 Ghost Mode 的状态组成里拆出来，做成一个可关闭、默认开启的偏好（鼠标移入窗口区域时 alpha 归 0，移出即恢复）。现在把这个偏好整个砍掉：Ghost Mode 下鼠标位置不再影响窗口可见性。

理由：功能设计不合理。

## Consequences

- Ghost Mode 的有效不透明度只剩两个输入：Hidden → 0，否则为配置的目标透明度；Normal Mode 恒为 1.0。ADR-0012 可见性分工表里"鼠标移入避让"那一行作废，其余三行不变——想让窗口完全看不见，用 Hidden（老板键）。
- `PlatformOps.onMouseInsideChanged` 及 AppKit 侧那块铺满 contentView 的 `NSTrackingArea` 一并删除——它唯一的消费者就是避让。
- 设置面板「窗口」页去掉"鼠标移入时避让"开关；`WidgetConfig.isMouseAvoidanceEnabled` 删除。旧 `config.toml` 里遗留的 `mouse_avoidance_enabled` 键解析时直接忽略，下一次写回配置时自然消失，不需要迁移。
