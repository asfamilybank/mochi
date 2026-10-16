# 卸载 Mochi

卸载分三步，后两步可以按需要选做：删除应用、删除数据、清除系统权限。

## 第一步：删除应用

1. 退出 Mochi：选择菜单栏的「Mochi › 退出 Mochi」，或者按 ⌘Q（Command + Q）。处于幽灵模式时，点菜单栏里的 Mochi 图标，在托盘菜单里选择「退出」。
2. 把 `/Applications/Mochi.app` 移到废纸篓。

只做这一步的话，你的设置、历史记录、书签和登录状态都还留在电脑上，以后重新安装会原样回来。

## 第二步：删除数据（可选）

想连数据一起清掉，再删除下面这几个位置：

| 位置 | 装的是什么 |
|---|---|
| `~/Library/Application Support/Mochi` | 设置（配置文件 `config.toml`）、历史记录和书签 |
| `~/Library/Caches/com.daidalma.mochi` | 网站缓存：缓存的网页文件和图片 |
| `~/Library/WebKit/com.daidalma.mochi` | 网站存在本机的其他数据，一部分网站的登录态也在这里 |
| `~/Library/HTTPStorages/com.daidalma.mochi.binarycookies` | 网站的 Cookie，也就是大多数网站的登录态 |
| `~/Library/Preferences/com.daidalma.mochi.plist` | 几个跟系统权限有关的小标记，比如 Mochi 是否已经自动请求过一次辅助功能权限 |

删之前想一想要不要留着设置：热键、映射、自定义脚本和样式表都存在 `config.toml` 里，删掉就没了。想留着的话，先把这个文件复制到别处。每个位置的详细说明见 [Mochi 存放的数据与系统权限](../reference/data-and-permissions.md)。

`~/Library` 在访达里默认是隐藏的。在访达里选择「前往 › 前往文件夹…」，或者按 ⇧⌘G（Shift + Command + G），粘贴上面的路径，按回车就能打开。

`com.daidalma.mochi.plist` 这一项不要直接拖进废纸篓：系统会把这个文件的内容暂存在内存里，直接删文件，之后可能又被写回来。改为在终端执行下面这条命令，它通过系统删除这些标记：

```bash
defaults delete com.daidalma.mochi
```

执行后如果提示 `Domain (com.daidalma.mochi) not found.`，说明本来就没有这些标记，不用再管。

请在 Mochi 退出之后再删：Mochi 退出时会把设置重新写回 `config.toml`，开着的时候删，退出时它又会出现。

## 第三步：清除系统权限（可选）

你授予过的系统权限（辅助功能、摄像头、麦克风、文件和文件夹）由系统按应用身份保管，**不会随卸载或删除数据而消失**，重新安装后仍然在。要彻底清除，在终端执行：

```bash
tccutil reset All com.daidalma.mochi
```

或者到「系统设置 › 隐私与安全性」的对应页面里把 Mochi 逐项移除。
