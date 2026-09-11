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
        // The system symbol, not a hand-drawn path: SF Symbols has `exclamationmark.triangle`,
        // and drawing our own gained nothing but its own stroke-weight and alignment bugs
        // `GhostGlyph` is the only glyph still bespoke, because there is no ghost symbol.
        Image(systemName: DesignTokens.Symbol.failure)
            .font(.system(size: 34, weight: .regular))
            .foregroundStyle(color(palette.iconMuted))
    }

    private var palette: DesignTokens.GlassPalette { DesignTokens.glassPalette(dark: isDark) }

    private func color(_ rgba: DesignTokens.RGBA) -> Color {
        Color(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}
