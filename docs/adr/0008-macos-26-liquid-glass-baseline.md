# 最低支持 macOS 26（Tahoe），全面采用 Liquid Glass 作为视觉语言

早期的领域文档和 ADR 都没有写死一个最低系统版本。设计阶段（见 [design/mochi/](../../design/mochi/) 的视觉稿）明确要"充分使用 Mac 的设计"，具体落到 macOS 26 Tahoe 引入的 Liquid Glass 材质系统（`NSGlassEffectView` / SwiftUI `.glassEffect()`）。这里补上这个此前一直隐含、从未明确拍板的前提。

选择直接把最低版本定在 macOS 26+，而不是用 `NSVisualEffectView` vibrancy 拼一套近似效果向后兼容旧系统，原因有两个：一是 [ADR-0001](0001-accept-native-webview-transparency-limits.md) 已经确立"仅通过官网/GitHub Release 分发、不走 App Store"这个前提，不存在"必须覆盖尽量多用户"的商店审核压力；二是这个应用的核心场景（全局热键 + Ghost Mode + 按键转发控制网页播放）本身就面向愿意折腾、愿意升级到最新系统的用户群体，为旧系统维护一套视觉降级分支的成本收益不划算。

## Consequences

- 部署目标（deployment target）锁定 macOS 26.0+，Xcode 项目设置和 `Info.plist` 需要反映这个下限；无法在更旧的 macOS 上运行，这是刻意的取舍，不是遗留问题。
- Normal Mode 的自绘工具栏、Ghost Mode 的召唤浮层、系统托盘图标等所有原生 UI 组件统一走 Liquid Glass 材质（背景模糊 + 饱和度提升 + 内嵌高光边 + 按系统强调色染色），不需要额外维护一套 vibrancy 兼容分支。
- App 图标需要遵循 Tahoe 的 Icon Composer 分层格式（Default / Dark / Clear / Tinted 四种系统外观）；具体先做哪几层、图标创意方向记在 [docs/design-language.md](../design-language.md)。
- 后续如果产品方向变化、确实需要覆盖 macOS 26 以下的用户，这是一个需要重新开一条 ADR 明确讨论取舍的决定，不应该被静默放宽。
