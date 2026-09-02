# 浏览器扩展（含 Chrome 插件）支持延后到 v2，v1 只做 Script Injection

调研发现 macOS 15.4+ 的 `WKWebExtension` API 理论上可以让第三方 App 加载转换后的 Safari Web Extension（多数 Chrome 插件可通过苹果的转换工具适配）。但这条路要求较高的系统版本门槛，且需要用户先手动转换插件格式，投入产出比在 v1 阶段不划算。

v1 决定只做已有的 Script Injection 机制（内置网站适配脚本 + 用户自定义脚本），完整的第三方浏览器扩展安装能力（含 crx）留到 v2 视需求再评估。
