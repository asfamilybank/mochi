# macOS UI 验证操作手册

在 Claude.app 已被授予「屏幕录制」+「辅助功能」权限的前提下（见 [ADR-0010](../adr/0010-macos-ui-verification-via-system-permissions.md)），用这份 cookbook 里的命令验证 Mochi 真实运行窗口的布局与元素是否正确，不需要用户亲自运行查看。

> ⚠️ **禁止全屏/区域截图**：`screencapture -x`（全屏）或 `-R x,y,w,h`（区域）会把屏幕上恰好可见的其他窗口一起拍进去——包括聊天软件、浏览器里的私人内容。已经真实发生过一次：诊断权限时图省事用了全屏截图，意外拍到了用户正在使用的微信私聊内容。**全程只能用 `screencapture -l<windowID>` 按窗口 ID 截图**（见第 2 步），它只合成目标窗口自己的内容，不会带上被其他窗口遮挡/重叠的部分。

## 前置：确认权限生效

用一个 10×10 像素的角落区域测试，不截全屏：

```bash
screencapture -x -R0,0,10,10 /tmp/perm_check.png && echo OK && rm -f /tmp/perm_check.png
```

报错 `could not create image from display` 说明屏幕录制权限没生效，最常见原因是授权后还没有**完全退出重启一次 Claude.app**（`⌘Q`，不是关窗口）——权限对已经在跑的进程不会热生效。

## 1. 启动 Mochi 并找到窗口

```bash
cd macos && swift build && swift run Mochi > /tmp/mochi.log 2>&1 &
```

等待窗口出现后，查窗口的位置和大小（进程名固定是 `Mochi`，对应 `Package.swift` 里的 executable target 名）：

```bash
osascript -e 'tell application "System Events" to tell process "Mochi" to get {position, size} of window 1'
```

## 2. 按窗口截图

**只能用 `screencapture -l<windowID>` 按窗口 ID 截图，禁止用不限定范围的全屏 `screencapture -x` 或区域截图 `-R`**——这两种方式会把屏幕上恰好可见的其他窗口（包括聊天软件、浏览器等私人内容）一起拍进去；`-l<windowID>` 只合成该窗口自己的内容，不会带上被其他窗口遮挡/重叠的部分，是唯一安全的做法。

System Events 的 `id of window` 属性对 Mochi 这类窗口不可用（会报 -1728 错误），改用 `CGWindowListCopyWindowInfo` 按进程名查窗口 ID：

```bash
cat <<'EOF' > /tmp/winid.swift
import CoreGraphics
import Foundation

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}
for w in list {
    if let owner = w[kCGWindowOwnerName as String] as? String, owner == "Mochi" {
        let num = w[kCGWindowNumber as String] as? Int ?? -1
        print("windowID=\(num)")
    }
}
EOF
swift /tmp/winid.swift
```

然后用返回的 windowID 截图（路径用当次会话的 scratchpad 目录）：

```bash
screencapture -x -l<windowID> <scratchpad>/mochi_window.png
```

用 Read 工具直接查看这张 PNG。

## 3. 查无障碍树（判断元素是否缺失/尺寸异常）

`window 1` 顶层只有 `AXGroup`/`AXToolbar`/交通灯按钮这几个大类，工具栏按钮（后退/前进/刷新/地址栏等）是 `AXToolbar` 的子元素，要单独下钻查询：

```bash
osascript -e '
tell application "System Events"
  tell process "Mochi"
    set tb to toolbar 1 of window 1
    repeat with el in (every UI element of tb)
      log (role of el & " | " & description of el)
    end repeat
  end tell
end tell'
```

返回的每一项对应工具栏里一个可见元素——地址栏"缺失"就是列表里找不到 `AXTextField`/`AXSearchField` 这类角色的元素。

**已验证的真实案例**：这条命令跑在触发过回归的版本上，返回 `AXButton|后退`、`AXButton|前进`、`AXButton|刷新`、`AXPopUpButton|more toolbar items`——没有任何地址栏角色的元素，只有一个 `more toolbar items` 溢出按钮（对应截图里看到的 `»` 图标）。结合第 2 步的窗口截图可以判定：地址栏没有丢失数据/崩溃，而是 `NSToolbarItem` 的宽度约束没让它挤进可见区域，被系统自动收进了工具栏溢出菜单——不需要用户运行来发现。

## 4. 动态时序（拖拽吸附、动画）

不用真实录屏，改用连续截图：每 0.3 秒重复第 2 步一次，拍 5~10 张，按顺序对比。

## 能力边界，别自作主张扩展

- **不做模拟点击/拖拽**——这套流程只读，不操作真实窗口。需要交互验证时，请用户手动操作。
- **不装 ffmpeg 抽帧、不追求真录屏**——真需要看视频效果，直接告知用户，让其亲自验证，不要用截图序列勉强代替结论。
- **Liquid Glass 视觉细节不能仅凭截图判定通过**——截图/离屏渲染的毛玻璃效果可能与肉眼所见有细微差异，这类改动的最终验收以用户实机确认为准（[ADR-0010](../adr/0010-macos-ui-verification-via-system-permissions.md)）。

## 排错

| 现象 | 原因 |
|---|---|
| `screencapture` 报 `could not create image from display` | 最常见：授权后没有完全退出重启 Claude.app；其次是权限被系统重置——回 [ADR-0010](../adr/0010-macos-ui-verification-via-system-permissions.md) 重新走一遍授权步骤 |
| `osascript` 报"不允许辅助访问" | 辅助功能权限没生效，原因同上 |
| 查不到 `process "Mochi"` | Mochi 没有在跑，先执行第 1 步；或者进程名不是 `Mochi`（比如改了 executable target 名），先 `osascript -e 'tell application "System Events" to get name of every process'` 确认实际进程名 |
