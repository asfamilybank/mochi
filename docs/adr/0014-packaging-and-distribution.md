# 打包与分发：SPM 与 Xcode 项目并存，ad-hoc 签名的 dmg

在这份 ADR 之前，Mochi 只能靠 `swift run` 起一个裸进程：没有 bundle、没有 `Info.plist`、没有图标（Dock 上是系统默认白纸），版本号由 `AppInfo.swift` 手写。[ADR-0013](0013-sf-symbols-for-every-glyph-but-the-ghost.md) 在 Consequences 里把这件事明确列为「不在本次范围内、需要单独一轮」。这一份就是那一轮：把 Mochi 变成一个能下载、能双击运行的 `.app`，并定下发布流程。

## 决定

- **新增 `.xcodeproj`，但 `Package.swift` 保留为开发与测试的主入口**。App target 通过 local package reference 依赖 `MochiCore`，`Package.swift` 里的 `Mochi` executableTarget 不删——`swift build` / `swift test` / `swift run Mochi` 全部照旧可用。
- **App target 的源文件用 Xcode 16+ 的 file system synchronized group 挂载整个目录**，而不是逐个文件登记进 `project.pbxproj`。新增源文件跟以前一样只需 `git add`，pbxproj 写一次就不再动。
- **`project.pbxproj` 手写维护，不引入 xcodegen / tuist**。上一条把「加文件要改 pbxproj」这个最高频的维护动作消掉之后，声明式生成器带来的收益不再抵得上多一个构建期依赖（本机与 CI 都要装）。
- **`ci.yml` 里除 `swift build` + `swift test` 之外，额外跑一步 `xcodebuild build`**。双构建系统最大的风险是 `.xcodeproj` 悄悄腐烂而没人发现，直到发版当天才炸；这一步专门钉住它。
- **图标资产用 Icon Composer 的 `.icon`，不用传统 `.icns`**。macOS 26 只对 `.icon` 统一套新的图标形状遮罩与材质，`.icns` 会被原样绘制、观感上像个没跟上系统的老应用。代价是 Icon Composer 只有 GUI、没有 CLI，每次更换素材都需要一次人工操作——这也是选 `.xcodeproj` 的直接理由之一：`.icon` 官方只能经 Xcode 的 `actool` 编译进 `Assets.car`。
- **只做 Default 一层外观**，Dark / Clear / Tinted 交给 Icon Composer 自动派生。图像生成模型给出的是单张扁平图，物理上只有一层；分层精修留到素材迭代那一轮。这推翻了 design-language.md 原先「先做 Default + Dark 两层」的写法——那句话写的时候没考虑到单张扁平图这个约束。
- **版本号以 git tag 为唯一真源**，打包脚本从 tag 注入 `Info.plist` 的 `CFBundleShortVersionString`；`AppInfo.version` 改为读 `Bundle.main`，读不到（即 `swift run` 开发态）回退字面量 `"dev"`。刻意不回退到一个硬编码的版本号——那会把刚消灭掉的「两处版本号对不上」重新引进来，而在开发态显示 `dev` 比显示一个可能已过期的数字诚实。
- **只出 arm64，不做 universal**。macOS 26 Tahoe 是最后一个支持 Intel 的 macOS 版本，能跑到 Tahoe 的 Intel 机器只剩 2019–2020 那几台；universal 让 dmg 体积翻倍、CI 时间拉长，换来一个正在消失的受众。
- **分发 ad-hoc 签名的 dmg**，`package.sh` 里预留 Developer ID + `notarytool` 的条件分支但默认关闭。这是一个纯粹由预算决定的现状，不是技术选型：公证只接受 Developer ID 证书签名的产物，而 Developer ID 只能从每年 $99 的 Apple Developer Program 申领，没有面向个人开源作者的免费通道（Apple 的费用豁免只给非营利组织、认证教育机构与政府实体，且明确排除个人与个体户）。后果是用户首次打开会被 Gatekeeper 拦下，且 macOS 15 之后「右键 → 打开」这个老办法已经失效，必须走 系统设置 → 隐私与安全性 → 仍要打开（限首次被拦后一小时内），或 `xattr -dr com.apple.quarantine`。README 里那段说明因此是必需品而非补充材料。
- **dmg 保持极简**：`hdiutil` 把 `Mochi.app` 和一个 `/Applications` 符号链接塞进去，不做背景图、不摆图标坐标。后者需要 AppleScript 驱动 Finder 设置视图属性，而 CI runner 是 headless 的、既没有 GUI session 也没有自动化权限——这是打 dmg 最经典的坑。极简版在本地与 CI 上行为完全一致。
- **`package.sh` 是唯一真源，CI 只是调它**。`release.yml` 由 `v*` tag 触发，在 `macos-26` runner 上构建、打包、`gh release create --generate-notes`。本地随时能出一份和 release 完全一致的产物用于验证。注意 CI 上永远没有 Developer ID，所以 CI 产物恒为 ad-hoc 签名。

## Considered Options

**继续用纯 SPM，自己逆向 actool 的调用参数把 `.icon` 编进 `Assets.car`**：否决。`.icon` 的编译参数不是公开契约，Xcode 换个版本就可能变，而它恰好是这一轮的核心交付物。这条路推翻了 CLAUDE.md 里「SPM 项目而非 `.xcodeproj` 是刻意选择」的记录，该记录需同步修正。

**全量迁移到 `.xcodeproj`，废弃 `Package.swift`**：否决。CLAUDE.md 里那套 `(swift run Mochi &); sleep 12; pgrep -x Mochi` 冒烟测试、`swift test` 的全部测试流程、以及 [docs/agents/macos-ui-verification.md](../agents/macos-ui-verification.md) 的 UI 验证手法都建立在 SPM 之上；迁移还会把 TOMLKit 的依赖管理从 `Package.resolved` 搬进 Xcode GUI。代价是同一批源文件被两个构建系统引用——这正是上面那步 CI `xcodebuild` 存在的理由。

**引入 `swift-bundler` 之类第三方打包工具**：否决。收益只是省掉一个百行量级的 shell 脚本，代价是把交付链路押在一个不受控的第三方上。

**不发 release，只发源码让用户自己 build**：这条其实完全免费且体验正常——quarantine 标记是下载器打上去的，本地编出来的产物根本没有这个标记。否决是因为它把受众限制在装了 Xcode 的人。留作备选：如果 ad-hoc 的 Gatekeeper 门槛在实际使用中被证明劝退效果太强，退回这条路是合理的。

**发 Homebrew Cask 绕过 Gatekeeper**：这曾是开源项目最常见的迂回路，现已关闭——Homebrew 自 2026 年 9 月 1 日起停止支持通不过 Gatekeeper 检查的 cask，`--no-quarantine` 也在废弃中。

## Consequences

- 交付链路上有**两处只能由人完成**的步骤：跑图像生成模型出 app 图标底稿、开 Icon Composer GUI 导出 `.icon`。两者都没有 CLI，Agent 做不了。
- `AppInfo.swift` 原先的注释「等 packaging 出现后从权威来源派生」兑现，`name` 保留、`version` 改为读 bundle。
- `CFBundleIdentifier` 定为 `com.daidalma.mochi`。这个值发布后基本不可改——改了等于换一个应用，用户的配置路径与 TCC 授权全部重来。
- README 需要新增安装说明，且必须包含 Gatekeeper 绕过步骤。
- 本仓库既有的约束不变：`git push`（含 tag）仍然只能由人执行，Agent 不触发发布。
