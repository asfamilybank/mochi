import SwiftUI

/// The Empty Page (#16): a native SwiftUI view — not a webpage — shown in place of the WKWebView
/// whenever `StartupResolution.resolveStartupContent` resolves to `.emptyPage`. An abstract
/// Liquid Glass composition (two overlapping, slightly rotated glass panels) plus a
/// de-emphasized default-hotkey quick reference, matching `design/mochi/EmptyPage.dc.html`.
struct EmptyPageView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        ZStack {
            color(DesignTokens.EmptyPage.backgroundBase(dark: isDark))
            RadialGradient(colors: [primaryBlobColor, .clear], center: UnitPoint(x: 0.3, y: 0.3), startRadius: 0, endRadius: 320)
            RadialGradient(colors: [secondaryBlobColor, .clear], center: UnitPoint(x: 0.7, y: 0.7), startRadius: 0, endRadius: 300)
            VStack(spacing: 22) {
                glassComposition
                hotkeyQuickReference
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var glassComposition: some View {
        ZStack {
            glassPanel(tint: DesignTokens.EmptyPage.accentGlassPanelTint(DesignTokens.resolveSystemAccent(), dark: isDark))
                .rotationEffect(.degrees(-6))
                .offset(x: -18, y: -13)
            glassPanel(tint: DesignTokens.EmptyPage.secondaryGlassPanelTint(dark: isDark))
                .rotationEffect(.degrees(8))
                .offset(x: 18, y: 13)
        }
        .frame(width: 220, height: 150)
    }

    private func glassPanel(tint: DesignTokens.RGBA) -> some View {
        RoundedRectangle(cornerRadius: DesignTokens.Layout.emptyPageGlassPanelCornerRadius)
            .fill(color(tint))
            .frame(width: 150, height: 110)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Layout.emptyPageGlassPanelCornerRadius)
                    .strokeBorder(color(palette.border), lineWidth: 1)
            )
    }

    /// The default hotkeys' actual combos (`HotkeyDisplay.describe`), not hardcoded label text —
    /// so this stays correct if `DefaultHotkeys` ever changes.
    private var hotkeyQuickReference: some View {
        VStack(spacing: 8) {
            Text("默认热键")
                .font(.system(size: 11))
                .tracking(0.4)
                .foregroundStyle(color(palette.textSecondary))
            HStack(spacing: 16) {
                hotkeyBadge(HotkeyDisplay.describe(DefaultHotkeys.toggleGhostMode), label: "切换 Ghost Mode")
            }
        }
        .opacity(0.55)
    }

    private func hotkeyBadge(_ combo: String, label: String) -> some View {
        HStack(spacing: 6) {
            Text(combo)
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color(DesignTokens.EmptyPage.hotkeyBadgeBackground(dark: isDark)), in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(color(palette.textSecondary))
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(color(palette.textSecondary))
        }
    }

    private var palette: DesignTokens.GlassPalette { DesignTokens.glassPalette(dark: isDark) }

    private var primaryBlobColor: Color {
        color((isDark ? DesignTokens.RGBA(hex: "3A5A99") : DesignTokens.RGBA(hex: "B9D3F5")).withAlpha(0.35))
    }

    private var secondaryBlobColor: Color {
        color((isDark ? DesignTokens.RGBA(hex: "8A4A3A") : DesignTokens.RGBA(hex: "F2CDB9")).withAlpha(0.3))
    }

    private func color(_ rgba: DesignTokens.RGBA) -> Color {
        Color(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}
