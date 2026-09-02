# 接受原生 WebView 的透明度限制（macOS / WKWebView）

项目目标是不重新实现浏览器内核，直接复用系统原生 WebView（macOS WKWebView）渲染网页。WKWebView 没有官方公开 API 支持透明背景，业界通用做法是用私有属性 `drawsBackground` 做 KVC hack，存在 App Store 审核和跨版本崩溃的风险。

我们接受这一限制，不为此自建合成层/自定义渲染管线去绕过它：v1 的"透明度调节"依赖这个私有属性实现，半透明视觉效果由页面内容自身用 CSS 模拟。这与"轻量、不重新造浏览器内核"的项目定位一致。

若未来真的启动 Windows 版本（完全独立的代码，见 [ADR-0007](0007-native-per-platform-no-shared-code.md)），需要针对 WebView2 单独调研其透明度实现方式与限制，不能假设跟这里 macOS 的结论一致。

## Consequences

- 若启用 WKWebView 透明背景的私有属性 hack，需要额外评估 App Store 上架路径是否可行；若仅通过官网/GitHub Release 分发，风险可接受。
- 产品文案上的"透明度滑杆"需要管理预期：这是通过非公开 API 实现的效果，需要随 macOS 版本更新持续验证稳定性。
