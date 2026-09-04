import SwiftUI

/// The error page (#38): shown in place of the WKWebView whenever a navigation fails for a
/// reason other than the user cancelling it (a mid-load address change, a new link click) — see
/// `AppKitPlatformOps.showErrorPageContent`. The widget sits in a desktop corner indefinitely, so
/// a blank page and a genuinely broken one are otherwise indistinguishable; this exists purely to
/// make a real failure legible.
///
/// No `design/mochi/*.dc.html` mockup exists for this page (the design canvas was retired), so
/// this follows `docs/design-language.md`'s material/color rules and matches `EmptyPageView`'s
/// existing look rather than a measured mockup.
struct ErrorPageView: View {
    let failedURL: String
    let message: String
    let onRetry: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        ZStack {
            color(DesignTokens.EmptyPage.backgroundBase(dark: isDark))
            VStack(spacing: 14) {
                icon
                VStack(spacing: 6) {
                    Text("无法打开网页")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(color(palette.textPrimary))
                    Text(failedURL)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(color(palette.textSecondary))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(message)
                        .font(.system(size: 12.5))
                        .foregroundStyle(color(palette.textSecondary))
                        .multilineTextAlignment(.center)
                }
                Button("重试", action: onRetry)
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var icon: some View {
        IconShape(path: DesignIcon.warning.path)
            .stroke(
                color(palette.iconMuted),
                style: StrokeStyle(lineWidth: CGFloat(DesignTokens.Layout.iconStrokeWidth), lineCap: .round, lineJoin: .round)
            )
            .frame(width: 40, height: 40)
    }

    private var palette: DesignTokens.GlassPalette { DesignTokens.glassPalette(dark: isDark) }

    private func color(_ rgba: DesignTokens.RGBA) -> Color {
        Color(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}

/// Renders a `DesignIcon`'s 24×24 `CGPath` as a SwiftUI `Shape`, scaled to fit whatever frame
/// it's given. Both `CGPath` and SwiftUI's `Path` share the same top-left-origin, y-down
/// coordinate convention (per `DesignIcon`'s own doc comment on needing a flip only for AppKit's
/// y-up `NSView` drawing, e.g. `ToolbarStyle.templateImage`'s `NSImage(flipped: true)`), so this
/// needs no vertical flip of its own — only the fit-to-rect scale/translate.
private struct IconShape: Shape {
    // `Path` (a `Sendable` SwiftUI value type), not the `CGPath` it's built from — `CGPath`
    // itself isn't `Sendable`, which `Shape`'s conformance requires.
    private let basePath: Path
    private let bounds: CGRect

    init(path: CGPath) {
        self.basePath = Path(path)
        self.bounds = path.boundingBoxOfPath
    }

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / max(bounds.width, 1), rect.height / max(bounds.height, 1))
        let transform = CGAffineTransform(translationX: -bounds.midX, y: -bounds.midY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY))
        return basePath.applying(transform)
    }
}
