# 网页视图对外报 Safari 的 User-Agent，后缀一变就清掉 HTTP 缓存

裸 `WKWebView` 的 User-Agent 只写到 `(KHTML, like Gecko)`，没有 `Version/…` 和 `Safari/…`。按浏览器版本拦截的站点会把它当成过时或无法识别的浏览器：bilibili.com 对 `www.bilibili.com/` 的请求按 UA 在服务端返回 302，跳到「浏览器下载建议」页（`/blackboard/fe/activity-CjJbuaD7Xw.html`），整站打不开。

## 决定

- 所有网页视图通过 `WKWebViewConfiguration.applicationNameForUserAgent` 追加 `Version/<本机 Safari 的 major.minor> Safari/605.1.15`（`WebUserAgent`）。只追加后缀，前缀（平台、WebKit 版本）仍由 WebKit 自己维护。Popup Window 用的是 WebKit 从 Widget 派生出来的 configuration，自动继承这项设置。
- 版本号读本机 Safari 的 `Info.plist`，不写死。macOS 上 Safari 和系统 WebKit 一起发布，这个版本号描述的正是当前在跑的引擎；写死的数字会随系统更新过时，而版本过旧恰恰是触发拦截的原因。读不到时兜底为 ADR-0008 的基线 `26.0`。
- 每次启动比较本次的后缀和上次运行记下的后缀，不一样（包括从未记录过）就先清空 WebKit 的 HTTP 缓存（磁盘 + 内存），然后才打开 Widget。cookie、本地存储和登录态都不动。上次的后缀记在 `UserDefaults`：这是 app 自己的记账，不是用户设置，不进 `config.toml`。

## 为什么必须清缓存

只加后缀的第一版（`d7f2e1d`）上线后，从地址栏输入 `bilibili.com` 还是会被跳走，而直接打开 `www.bilibili.com` 是好的。原因是 WebKit 缓存重定向时，会把**重定向后的那个请求连同请求头（包括 User-Agent）一起**存进去，之后命中缓存就照原样重放这个请求：`https://bilibili.com/` → `https://www.bilibili.com/` 的 301 是在修复前缓存的，记录的是裸 UA，于是之后每次都用裸 UA 去请求 `www`，服务端照样 302。页面里读到的 `navigator.userAgent` 带着后缀，网络请求却不带，只有翻 `NetworkCache` 的记录才能看出来。把这份缓存复制给独立 harness 能稳定复现；只删掉 `NetworkCache`，问题立即消失。

所以凡是后缀会变的场合（第一次升级到带后缀的版本、Safari 随系统升级换了版本号），旧缓存里的重定向都可能还带着旧 UA。

## Considered Options

- `customUserAgent` 整串覆盖：WebKit 前缀里的平台和版本就得自己维护，会随系统过时。
- 写死 `Version/26.0`：系统一升级就落后，而落后正是被拦截的原因。
- 不清缓存，让用户自己去设置里「清除网站数据」：用户无从知道症状和缓存有关，而且那个操作会把所有站点都登出。
- 只清 bilibili 的缓存记录：问题出在 WebKit 的重定向缓存机制，不是 bilibili 一家；按域名精确清理也无从知道该清哪些站点。
- 后缀变化时只清 HTTP 缓存（选定）。

## Consequences

- 已安装的用户升级后第一次启动会清一次 HTTP 缓存，之后只在 Safari 版本号变化时再清。代价是这几次启动后，常去的站点要重新下载一遍资源。
- 后缀没变的普通启动不等待任何异步操作，`Orchestrator.start()` 直接执行；需要清缓存时，要等 WebKit 的清理回调回来才打开 Widget。
- 以后如果再修改 User-Agent（换后缀格式、改兜底版本号），这套比较会自动触发一次清理，不需要另写迁移。
