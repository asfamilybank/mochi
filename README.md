# Mochi

Mochi 把一个网页变成桌面上的浮窗，你在别的应用里工作时，也能用热键控制它，尤其适合边工作边看视频。

<!-- 📷 images/hero.png — 普通模式窗口，打开一个中性网页，工具栏完整（窗口 ID 截图） -->

## 适合的场景

- **边工作边看视频或直播**：把视频放在屏幕角落，让它浮在最上层、半透明，点击会穿过它落到下面的应用上。
- **需要时一键藏起来**：有人走过来时按一下热键，窗口立刻消失，再按一下就回来。
- **不切换应用就能暂停、快进**：你在别的应用里打字时，也能用按键暂停、后退、前进视频。

## 系统要求

- macOS 26 或更高版本。
- 只支持 Apple 芯片的 Mac。

## 安装

1. 从 [Releases](https://github.com/asfamilybank/mochi/releases) 下载最新的 `Mochi-x.y.z.dmg`。
2. 双击挂载，把 `Mochi.app` 拖进旁边的「应用程序」快捷方式。
3. 第一次打开会被系统拦下，提示无法验证开发者或是否含有恶意软件。**这是预期内的**，不是下载坏了——Mochi 目前只做 ad-hoc 签名，没有 Apple Developer ID 证书与公证。按下面任一种方式放行一次，之后每次打开都不会再问。

**放行方式一：系统设置**

被拦下之后，打开「系统设置 → 隐私与安全性」，向下滚到「安全性」一节，那里会出现一行「已阻止使用 Mochi」，点它右边的 **「仍要打开」**，再在弹窗里确认。这行提示只在被拦下后的一小时内出现；错过了就再双击一次 `Mochi.app` 把它重新触发出来。

**放行方式二：终端**

直接去掉下载时被打上的隔离标记：

```bash
xattr -dr com.apple.quarantine /Applications/Mochi.app
```

> 网上流传的「右键 →『打开』」那条老办法在 macOS 15 之后已经被移除，照着做只会白折腾。

## 开始使用

装好之后，打开[用户手册](docs/guide/README.md)，从那里找到你要看的那一页。

## 用户手册

[用户手册](docs/guide/README.md)按用途分成四类：

- [教程](docs/guide/README.md#教程)：带你从头走一遍核心用法。
- [操作指南](docs/guide/README.md#操作指南)：教你完成某件具体的事，遇到问题时也从这里查故障排除。
- [参考](docs/guide/README.md#参考)：设置、快捷键、菜单、两种模式的对照，供随时查阅。
- [原理说明](docs/guide/README.md#原理说明)：讲清楚 Mochi 为什么这样设计。

## 反馈问题

遇到问题或者有建议，请到 [GitHub Issues](https://github.com/asfamilybank/mochi/issues) 提交。

## 常见问题

**幽灵模式里，视频控制的组合键（如 ⌥P）没反应**

视频控制里不带 ⌃ 或 ⌘ 的组合键（如 ⌥P、⇧F5）要靠「辅助功能」权限才能在其他应用里听到按键（系统把这类按键当成打字，只放行给受辅助功能信任的应用）；默认的轻按、连按两次，以及带 ⌃ 或 ⌘ 的组合键都不需要任何权限。缺这项权限时，设置的「幽灵模式」面板顶部和托盘菜单里会给出提示。

Mochi 只做 ad-hoc 签名，系统按每一版的签名记账，所以每次升级之后，「系统设置 → 隐私与安全性 → 辅助功能」里 Mochi 的开关**看着还开着，实际已经失效**。在列表里选中 Mochi，点下方的「−」把它移除，再点「+」把 `/Applications/Mochi.app` 重新添加进来并打开开关，不用重新打开 Mochi，马上就会生效。

**在系统设置里打开了摄像头、麦克风或下载文件夹权限，Mochi 里还是用不了**

这几项权限只要被拒过一次，之后在「系统设置 → 隐私与安全性」里再打开，系统会提示需要退出并重新打开 Mochi，请照做：选「以后」的话，Mochi 重新打开之前仍然拿不到这项权限，设置里的提示也不会消失。辅助功能不受影响，打开就生效。

## 卸载

把 `/Applications/Mochi.app` 移到废纸篓即可。如果想连数据一起清掉，再删除 `~/Library/Application Support/Mochi`（配置文件 `config.toml`）和 `~/Library/Caches/com.daidalma.mochi`、`~/Library/WebKit/com.daidalma.mochi`、`~/Library/HTTPStorages/com.daidalma.mochi.binarycookies`（网站缓存与登录态）。

授予过的系统权限（辅助功能、摄像头、麦克风、下载文件夹）由系统按应用身份保管，**不会随卸载或删除数据而消失**，重新安装后仍然在。要彻底清除，在终端执行：

```bash
tccutil reset All com.daidalma.mochi
```

或者到「系统设置 → 隐私与安全性」的对应页面里把 Mochi 逐项移除。

---

想参与开发，请看 [CONTRIBUTING.md](CONTRIBUTING.md)。
