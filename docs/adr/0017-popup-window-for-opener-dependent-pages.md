# 为依赖 opener 的页面引入从属的 Popup Window，修订 ADR-0002 的"只有一个窗口"

ADR-0002 规定同一时刻只呈现一个 Widget 窗口。但网页里"用 Google/微信登录"这类流程靠 `window.open` 开一个小窗，登录结果通过 `window.opener` 回传原页面——在 Widget 内原地加载会替换掉原页面，交给默认浏览器则登录态落在别的浏览器里，两条路都让登录直接失败。因此引入一个从属于 Widget 的临时 Popup Window：共享同一份网站数据，页面 `window.close()` 时随之关闭，不是第二个 Widget、没有 Ghost Mode、不持久化位置。ADR-0002 的"不做多 Widget 并存"不变。

## Considered Options

- 用户点击的 `target=_blank` 链接与脚本 `window.open` 都在 Widget 内原地加载——OAuth 失效。
- 都交给默认浏览器——OAuth 失效。
- 用户点击的链接原地加载，脚本 `window.open` 开 Popup Window，未经点击的弹窗由"弹出式窗口"设置阻止（选定）。

## Consequences

- WebKit 公开 API 区分不出"点击触发的 `window.open`"和"网页自行弹窗"；后者依赖 WebKit 自身的弹窗拦截（`javaScriptCanOpenWindowsAutomatically = false`），也就是"弹出式窗口：阻止"这一档。
- Ghost Mode 期间不打开 Popup Window（见 CONTEXT.md 的 Ghost Mode 条目）。
