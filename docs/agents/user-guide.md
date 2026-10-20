# 维护用户手册

用户手册在 [`docs/guide/`](../guide/README.md)，首页是仓库的 [README.md](../../README.md)。手册写给普通 macOS 用户，界面名称、默认热键、设置项都按源码里的界面文案逐字书写，所以界面一改，手册就可能过时。这份文档写给接手维护手册的 agent：改了什么要同步哪几页、怎么写、截图怎么截。

## 改了什么，要同步哪几页

先用 `git grep` 按**旧的**文案、按键或设置名搜一遍，搜到的页面全部要改：

```bash
git grep -n "旧的界面文案" -- docs/guide/ README.md
```

搜索之外，下面这些改动还有固定要查的页面和截图：

| 改动 | 要查的页面 | 要重截的图 |
|---|---|---|
| 菜单栏菜单项、菜单快捷键（`MainMenuBuilder`） | `reference/menus.md`、`reference/shortcuts.md` 的「菜单快捷键」一节 | 无 |
| 托盘菜单项（`TrayMenu`） | `reference/menus.md` 的「托盘菜单」一节、`tutorials/first-steps.md` | `tray-menu.png` |
| 默认全局热键（`DefaultHotkeys`，现为 ⌥G / ⌥H） | 旧组合（如 `⌥G`）大半个手册都搜得到，以 grep 结果为准。另外：`reference/shortcuts.md` 是总表；`how-to/troubleshooting.md` 的标题里有 ⌥G / ⌥H，改标题要同步别处链过来的锚点；`how-to/global-hotkeys.md` 写着默认组合在其他应用里打不出的字符（`©` / `˙`） | `settings-ghost-mode.png`、`first-steps-empty-page.png`、`tray-menu.png` |
| 视频控制的默认按键或步长 | 以 grep 旧按键（如 `右 ⌥`）的结果为准。`reference/shortcuts.md` 是总表，`how-to/video-control.md` 和 `tutorials/first-steps.md` 按步骤写着默认按键，`reference/settings.md` 写着默认值 | `settings-ghost-mode.png`、`settings-video-control.png`、`first-steps-empty-page.png` |
| 设置项增删、改名、改可选项或默认值 | `reference/settings.md` 的对应条目，以及条目「相关页面」里链到的操作指南 | 该面板的 `settings-*.png` |
| 设置项的生效时机 | `reference/settings.md` 的对应条目，**以及页面开头列举的例外**（现在是「启动时」、自动播放、脚本、HTTP 警告） | 无 |
| 设置面板的布局（分组、顺序、控件） | `reference/settings.md` 的分节顺序 | 该面板的 `settings-*.png`；幽灵模式面板还要重裁 `settings-video-control.png`、`settings-hotkey-forwarding.png` |
| 幽灵模式下对网页请求的处理（对话框、摄像头、下载、登录小窗） | `reference/modes.md`、`how-to/ghost-mode.md`、`explanation/ghost-mode-design.md`，以及对应的操作指南 | 无 |
| 数据存放路径、系统权限的申请时机 | `reference/data-and-permissions.md`、`how-to/uninstall.md`、`how-to/troubleshooting.md` | 无 |
| 新功能 | 按下面的写作约定新写一页或补进现有页面，在手册首页加链接；引入新术语时补进 `reference/glossary.md` | 按需 |
| 发版 | 手册首页的「本手册对照 Mochi x.y 编写」（用 `git tag` 查最新版本），以及这一版改动波及的页面 | 按上面各行 |
| 移动或改名 `docs/guide/` | 「帮助 › Mochi 帮助」打开的网址写死在 `AppInfo.helpURL`，指向 main 分支上的 `docs/guide` | 无 |

改完之后：

- 手册正文里 `「」` 括起来的 Mochi 界面名称，逐个在 `macos/Sources` 里 grep 一遍，一字不差才算对。系统界面的名称（系统设置、访达、文本编辑等）不在核对范围内。
- 用一次性脚本检查 `docs/guide/`、README、CONTRIBUTING 里的相对链接、锚点和图片路径都存在。脚本放系统临时目录，不提交。页面标题会被别的页面按锚点链接，改标题时尤其要跑。

## 写作约定

- 读者是普通 macOS 用户。正文不出现 ADR 编号、类名、实现细节和配置文件的字段名；配置文件只在 `reference/data-and-permissions.md` 和 `how-to/uninstall.md` 里以路径的形式出现。
- 手册按 Diátaxis 分四类：`tutorials/`、`how-to/`、`reference/`、`explanation/`。文件名用英文短横线，页面标题用中文。
- 安装和放行步骤只写在 README 的「安装」一节，手册里需要时链接过去。
- 第二人称「你」。按键写符号，每页第一次出现时补全称，例如「⌥（Option）」「右 ⌥（右侧的 Option 键）」。
- 界面元素用「」括起来，写全路径，例如「设置 › 幽灵模式 › 视频控制」，路径分隔符用 `›`。
- 有两个「辅助功能」，要写清是哪一个：「设置 › 高级 › 辅助功能」管字体大小，「系统设置 › 隐私与安全性 › 辅助功能」是系统权限。
- 只有手册首页标版本，各页正文不标。
- 「见…」引出链接，不用「参见…」。
- 操作指南页末尾的「遇到问题」链到故障排除的对应条目；故障排除每条按「症状 → 原因 → 怎么做」写。

领域术语在手册里的叫法：

| 领域术语 | 手册用语 |
|---|---|
| Widget | 窗口 / Mochi 窗口 |
| Normal Mode | 普通模式 |
| Ghost Mode | 幽灵模式 |
| Hidden | 隐藏窗口；第一次出现时补一句「相当于老板键」 |
| Snap | 吸附屏幕边缘 |
| Mouse Passthrough | 鼠标穿透 / 点击会穿过窗口 |
| Video Control | 视频控制 |
| Hotkey Forwarding | 热键传递，其中的条目叫「映射」 |
| Trigger Key | 触发键：轻按 / 连按两次 / 组合键 |
| Popup Window | 登录小窗。这是手册自定的名字：界面上的「弹出式窗口」设置管的是网页未经点击自行弹出的窗口，跟登录小窗是两回事，不能混用 |
| Script Injection | 官方内置适配脚本 / 自定义脚本 / 自定义样式表 |
| Page Permission | 网页权限 |
| System Permission | 系统权限；具体写系统设置里的名字（辅助功能、摄像头、麦克风、文件和文件夹） |
| Website Data | 网站数据 |
| Address Suggestions | 地址栏建议 |

`reference/glossary.md` 只放右列和一句解释，不出现英文内部名。

## 截图清单

图片都在 `docs/guide/images/`。「窗口 ID」指用 `screencapture -l<windowID>` 截 Mochi 的那个窗口。

| 文件 | 内容 | 截法 | 用在 |
|---|---|---|---|
| `hero.png` | 普通模式窗口，打开一篇中性的测试网页，工具栏完整 | 窗口 ID | README |
| `first-steps-empty-page.png` | 空页面和热键速览 | 窗口 ID | `tutorials/first-steps.md` |
| `first-steps-address-bar.png` | 地址栏输入 `bilibili.com`，下方出现「打开 bilibili.com」建议 | 窗口 ID | `tutorials/first-steps.md` |
| `ghost-overlay.png` | 幽灵模式下半透明的 Mochi 窗口浮在「文本编辑」窗口上 | 两个窗口分别按窗口 ID 截，再合成，见下文 | `tutorials/first-steps.md`、`how-to/ghost-mode.md` |
| `tray-menu.png` | 展开的托盘菜单 | AX 打开菜单后按窗口 ID 截，见下文 | `tutorials/first-steps.md`、`reference/menus.md` |
| `open-pages-suggestions.png` | 地址栏输入 `wiki`，行内补全成 `wikipedia.org`，下拉列表里有书签和历史记录 | 窗口 ID | `how-to/open-pages.md` |
| `settings-general.png` | 「设置 › 通用」 | 窗口 ID | `reference/settings.md`、`how-to/open-pages.md` |
| `settings-ghost-mode.png` | 「设置 › 幽灵模式」整页，热键传递里有一条示例映射 | 窗口 ID | `reference/settings.md`、`how-to/ghost-mode.md` |
| `settings-video-control.png` | 「视频控制」分组 | 从 `settings-ghost-mode.png` 用 `sips -c` 裁出 | `how-to/video-control.md` |
| `settings-hotkey-forwarding.png` | 「热键传递」分组，一条示例映射：轻按右 ⌃ 发送 D | 从 `settings-ghost-mode.png` 用 `sips -c` 裁出 | `how-to/hotkey-forwarding.md` |
| `settings-websites.png` | 「设置 › 网站 › 通用」 | 窗口 ID | `reference/settings.md` |
| `settings-websites-camera.png` | 「设置 › 网站 › 摄像头」 | 窗口 ID | `how-to/camera-and-microphone.md` |
| `settings-privacy.png` | 「设置 › 隐私与安全性」 | 窗口 ID | `reference/settings.md` |
| `settings-scripts.png` | 「设置 › 脚本」 | 窗口 ID | `reference/settings.md`、`how-to/scripts.md` |
| `settings-advanced.png` | 「设置 › 高级」 | 窗口 ID | `reference/settings.md` |
| `camera-prompt.png` | 网页请求摄像头时 Mochi 的询问框 | 窗口 ID，用本地测试页触发 | `how-to/camera-and-microphone.md` |
| `history-window.png` | 历史记录窗口，测试数据 | 窗口 ID | `how-to/history.md` |
| `bookmarks-window.png` | 书签窗口，测试数据 | 窗口 ID | `how-to/bookmarks.md` |
| `bookmark-editor.png` | 按 ⌘D 后从地址栏弹出的书签编辑气泡 | 窗口 ID | `how-to/bookmarks.md` |
| `clear-browsing-data.png` | 「清除浏览数据」对话框 | 窗口 ID，**只打开、不点「清除」** | `how-to/clear-data.md` |
| `manage-websites.png` | 「管理网站和数据」，测试数据 | 窗口 ID | `how-to/clear-data.md` |

有意不截的：`settings-accessibility-hint.png`（「需要辅助功能权限」提示）。要截它得先撤掉辅助功能权限，已与用户确认省略。

## 怎么截

通用的截图、AX 操作做法见 [macos-ui-verification.md](macos-ui-verification.md) 和 CLAUDE.md 的「macOS app」一节。下面是截手册截图时额外要遵守的规则，都经过真机验证。

### 规则

- 只按窗口 ID 截图，禁止全屏 `-x` 和区域 `-R`。窗口 ID 截不到的效果（叠加、合成）也是先按窗口 ID 分别截，再自己合成。
- 用 `/Applications/Mochi.app` 的发布版，不用 `swift run` 的开发版：开发版的系统菜单项是英文，「关于」显示 `dev`。
- 只截浅色外观。开发机系统是深色时，用 `open -a /Applications/Mochi.app --args -NSRequiresAquaSystemAppearance YES` 启动；「文本编辑」等要一起入镜的其他应用也用同一个参数启动。
- 只用测试数据，不出现任何人真实的历史记录、书签、登录态，也不截视频画面本身。

### 准备和还原测试数据

1. `caffeinate -d -t 900` 防止中途锁屏；确认 `pgrep -x Mochi` 为空。
2. 把 `~/Library/Application Support/Mochi` 整个挪进备份目录（比如 `~/Library/Application Support/Mochi.claude-backup/`，别放 scratchpad）。涉及「管理网站和数据」的截图时，网站数据的三个位置也一起挪：`~/Library/Caches/com.daidalma.mochi`、`~/Library/WebKit/com.daidalma.mochi`、`~/Library/HTTPStorages/com.daidalma.mochi.binarycookies`。挪之前记下 `config.toml` 的 `shasum` 和 `sqlite3 History.db "select count(*), max(id), max(visited_at) from visits"` 的结果。
3. 网页用本机 `python3 -m http.server --bind 127.0.0.1` 提供的中性测试页，或者公开的中性页面（如维基百科）。测试用的书签和历史记录，可以在换好测试数据的 Mochi 里实际打开网页、添加书签产生，也可以按当前 schema 用 `sqlite3` 手写测试库。
4. 截完退出 Mochi，删掉测试数据，把备份挪回原位。再核对一遍 `config.toml` 的 `shasum` 和历史记录的查询结果，跟第 2 步记下的一致才算还原好。

### 子窗口会跟着主窗口一起截

地址栏下拉的建议面板和书签编辑气泡是主窗口的子窗口：对主窗口执行 `screencapture -l<主窗口 id>` 时，它们会一并截进去。`open-pages-suggestions.png`、`bookmark-editor.png` 都是这样直接截主窗口得到的，不用另外合成。

设置窗口上的 sheet（「清除浏览数据」「管理网站和数据」）也一样：截设置窗口就会带上它们，连同后面变暗的面板。`clear-browsing-data.png`、`manage-websites.png` 都是这样截的。

### 托盘菜单

- 用 AX 按下 `AXExtrasMenuBar` 里 Mochi 的状态项。菜单会作为 Mochi 自己的一个 layer 101 窗口出现，用 `CGWindowListCopyWindowInfo` 查到它的窗口 ID，再 `screencapture -l<id>`。
- 托盘菜单跟随系统菜单栏的外观，启动参数改不了它，所以开发机是深色时它就是深色的。这是预期结果。
- 截完按 Esc 收起菜单。

### 幽灵模式叠加图

按窗口 ID 分别截 Mochi（处于幽灵模式，截图里保留它 20% 的透明度）和「文本编辑」窗口，再用 CoreGraphics 按两个窗口在屏幕上的位置（`kCGWindowBounds`）把 Mochi 叠到「文本编辑」上合成一张。

### 摄像头询问框

- `127.0.0.1` 的 http 页面属于安全上下文，可以在测试页里调 `getUserMedia` 触发摄像头请求。
- Mochi 还没有摄像头系统权限时，网页一请求，先弹出的是 macOS 的授权框，不是 Mochi 的询问框。点这个授权框会改动用户的隐私设置，必须请用户自己点，agent 不能代点。

### 清除浏览数据

- 对话框只打开、不点「清除」。它默认勾着「历史记录」，误点会删掉数据。

### 地址栏

用 AX 给地址栏设值时，按描述「地址」定位输入框。只按角色找文本框，可能命中网页里的搜索框，比如维基百科首页的那个。
