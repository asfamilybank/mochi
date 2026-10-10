# 热键传递把按键直接交给 widget 的 web view

[ADR-0003](0003-hotkey-forwarding-platform-split.md) 选 `CGEventPostToPid` 的前提是"投递给本进程，不需要它在前台或有焦点"。实测这个前提在 Ghost Mode 下不成立：事件确实到了 Mochi 进程（`NSApp` 的 local monitor 看得到），但 AppKit 只把按键分发给**能成为 key** 的窗口——Ghost Mode 去掉 `.titled` 后窗口是无边框的，`canBecomeKey` 为 false，按键在进 `WKWebView` 之前就被丢掉了。同一个窗口带 `.titled`（即使不是 key、app 也不在前台）就能收到。Ghost Mode 去 `.titled` 比热键传递上线还早，而热键传递只在 Ghost Mode 下生效，所以这个功能从上线起就没有真正把按键送进过页面；单元测试只断言到 `forwardKeystroke` 被调用为止。

## 决定

`forwardKeystroke` 改为把按键直接交给 widget 的 `WKWebView`（`webView.keyDown(with:)` / `keyUp(with:)`），不经过系统事件路由：

- 先按现在的做法造一个 `CGEvent`，借 `NSEvent(cgEvent:)` 让当前键盘布局算出字符；再用 widget 窗口的 `windowNumber` 重建 `NSEvent`——窗口号为 0 时页面收得到 keydown，但获得焦点的输入框打不进字。
- 修饰键只取映射里的页面按键自带的，触发键里还按着的修饰键不会混进去。
- 页面没处理的按键，WebKit 会把**同一个** `NSEvent` 对象经 `NSApp.sendEvent` 交回来：主菜单会把它当快捷键（转发一个 ⌘H 就把 Mochi 隐藏了），视频控制的本地监听也会把它当成用户按的键。Mochi 记下自己交出去的事件对象，用一个 local monitor 按对象身份吞掉回流；视频控制的本地监听也同样跳过这些事件，因为几个 local monitor 谁先运行不由我们决定。

不选的方案：

- 保留 `CGEventPostToPid`，给 `MochiWidgetWindow` 重写 `canBecomeKey = true`：依赖一条没有文档的 AppKit 分发规则，而且等于放开了 [ADR-0012](0012-ghost-mode-as-pure-invisibility.md)「永不获得焦点」的护栏，任何一处 `makeKey` 都会破坏它。
- 用 JS 派发合成的 `KeyboardEvent`：`isTrusted` 为 false，按规范不会触发浏览器默认行为，还得自己找目标元素和 frame。

## Consequences

- 页面收到的按键是 `isTrusted: true`，会落到页面里当前获得焦点的元素上，跨域 iframe 也一样；窗口始终不是 key，Mochi 也不会被激活。
- 热键传递本身不再需要辅助功能权限：组合键触发的映射走 Carbon 全局热键，Carbon 本来就不需要这项权限。轻按 / 连按两次触发的映射仍然需要，但那是**监听**触发键的需要，由视频控制去申请（[ADR-0020](0020-video-control-listens-never-intercepts.md)）。`HotkeyForwarder` 里的授权检查和"需要辅助功能权限"弹窗随之删掉。
- 被页面处理掉的按键不会回流，所以记下的事件对象设了几秒的过期时间，免得越积越多。
