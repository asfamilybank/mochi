import SwiftUI

/// The Empty Page (#16): a native SwiftUI view — not a webpage — shown in place of the WKWebView
/// whenever `StartupResolution.resolveStartupContent` resolves to `.emptyPage`. An abstract
/// Liquid Glass composition (two overlapping, slightly rotated glass panels) plus a
/// de-emphasized default-hotkey quick reference, matching `design/mochi/EmptyPage.dc.html`.
struct EmptyPageView: View {
    @Environment(\.colorScheme) private var colorScheme
    /// The toolbar strip's height. The page runs full-bleed underneath the toolbar, which floats
    /// over it, but the composition centers in the area below that strip. Passed in rather than
    /// read from the safe area: the safe area follows the window's chrome, and Ghost Mode removing
    /// the titlebar would drop it to 0 and send the composition jumping up.
    var topInset: CGFloat = 0

    /// The quick reference's own height, measured rather than guessed from its font sizes, so
    /// the composition knows how much of the page is left for it.
    @State private var quickReferenceHeight: CGFloat = 0

    private var isDark: Bool { colorScheme == .dark }

    /// The glass composition's size at full scale.
    private static let compositionSize = CGSize(width: 220, height: 150)
    private static let compositionSpacing: CGFloat = 22
    /// Kept clear above and below the content so it never touches the toolbar strip or the
    /// window's bottom edge.
    private static let verticalMargin: CGFloat = 16
    /// Below this the panels are too small to read as the composition, so they go altogether
    /// rather than shrink into a smudge.
    private static let minimumCompositionScale: CGFloat = 0.3

    var body: some View {
        ZStack {
            color(DesignTokens.EmptyPage.backgroundBase(dark: isDark))
            RadialGradient(colors: [primaryBlobColor, .clear], center: UnitPoint(x: 0.3, y: 0.3), startRadius: 0, endRadius: 320)
            RadialGradient(colors: [secondaryBlobColor, .clear], center: UnitPoint(x: 0.7, y: 0.7), startRadius: 0, endRadius: 300)
            GeometryReader { proxy in
                let layout = contentLayout(forHeight: proxy.size.height)
                VStack(spacing: layout.scale > 0 ? Self.compositionSpacing : 0) {
                    if layout.scale > 0 {
                        glassComposition
                            .scaleEffect(layout.scale)
                            .frame(
                                width: Self.compositionSize.width * layout.scale,
                                height: Self.compositionSize.height * layout.scale)
                    }
                    hotkeyQuickReference
                        .fixedSize()
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) { quickReferenceHeight = $0 }
                        .opacity(layout.showsQuickReference ? 1 : 0)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .padding(.top, topInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A short window can't hold the composition at full size above the quick reference — at the
    /// window's minimum height the panels ran up under the toolbar and the quick reference off the
    /// bottom. The composition shrinks to whatever height is left, and goes once it would be too
    /// small to read; the quick reference, the part that actually says something, stays until
    /// even it doesn't fit.
    private func contentLayout(forHeight height: CGFloat) -> (scale: CGFloat, showsQuickReference: Bool) {
        let available = height - Self.verticalMargin * 2
        let showsQuickReference = available >= quickReferenceHeight
        let compositionHeight = available - (showsQuickReference ? quickReferenceHeight + Self.compositionSpacing : 0)
        let scale = min(1, max(0, compositionHeight) / Self.compositionSize.height)
        return (scale >= Self.minimumCompositionScale ? scale : 0, showsQuickReference)
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
        .frame(width: Self.compositionSize.width, height: Self.compositionSize.height)
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

    /// The default hotkeys' actual combos (`HotkeyDisplay.keys`), not hardcoded label text —
    /// so this stays correct if `DefaultHotkeys` ever changes. Laid out like a menu's shortcut
    /// column: the action on the left, its keys on the right, one keycap per key.
    private var hotkeyQuickReference: some View {
        VStack(spacing: 10) {
            Text("默认热键")
                .font(.system(size: 11))
                .tracking(0.4)
                .foregroundStyle(color(palette.textSecondary))
            Grid(horizontalSpacing: 28, verticalSpacing: 8) {
                hotkeyRow(DefaultHotkeys.toggleGhostMode, label: "切换幽灵模式")
                // The Empty Page is Normal Mode content, and Hidden is a deliberate no-op outside
                // Ghost Mode (ADR-0012) — the label says so, or pressing it here would read as broken.
                hotkeyRow(DefaultHotkeys.hideWidget, label: "隐藏窗口（幽灵模式下）")
                hotkeyRow(DefaultHotkeys.openSettings, label: "打开设置")
            }
        }
        .opacity(0.55)
    }

    private func hotkeyRow(_ hotkey: Hotkey, label: String) -> some View {
        GridRow {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(color(palette.textSecondary))
                .gridColumnAlignment(.leading)
            HStack(spacing: 4) {
                ForEach(Array(HotkeyDisplay.keys(of: hotkey).enumerated()), id: \.offset) { _, key in
                    keycap(key)
                }
            }
            .gridColumnAlignment(.trailing)
        }
    }

    /// One key: a square cap for a single glyph, widening only for a named key ("Space").
    private func keycap(_ key: String) -> some View {
        Text(key)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color(palette.textSecondary))
            .padding(.horizontal, 4)
            .frame(minWidth: 20, minHeight: 20)
            .background(
                color(DesignTokens.EmptyPage.hotkeyBadgeBackground(dark: isDark)),
                in: RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(color(palette.border), lineWidth: 0.5))
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
