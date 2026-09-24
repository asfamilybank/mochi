import Foundation

#if canImport(AppKit)
    import AppKit
#endif

/// Single source of truth for Mochi's Liquid Glass visual language: colors, materials,
/// corner radii/spacing, the Ghost Mode shadow-vs-opacity formula, and accent-color
/// resolution. Every native view (Normal Mode toolbar, tray icon, Empty Page) should read its
/// numbers from here instead of writing its own.
///
/// Values are transcribed from `design/mochi/*.dc.html`'s `renderVals()` (the canvas is the
/// primary source; docs/design-language.md is its prose summary) — see that doc for the
/// rendered picture these numbers produce.
public enum DesignTokens {
    /// A color expressed as 0–1 component doubles, independent of any UI framework's color type.
    public struct RGBA: Equatable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double
        public let alpha: Double

        public init(red: Double, green: Double, blue: Double, alpha: Double) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }

        /// - Parameter hex: a `"#RRGGBB"`, `"RRGGBB"`, `"#RGB"`, or `"RGB"` string, matching the
        ///   canvas's own `hex2rgba` helper.
        public init(hex: String, alpha: Double = 1) {
            var digits = Array(hex.hasPrefix("#") ? String(hex.dropFirst()) : hex)
            if digits.count == 3 {
                digits = digits.flatMap { [$0, $0] }
            }
            let value = UInt32(String(digits), radix: 16) ?? 0
            self.red = Double((value >> 16) & 0xFF) / 255
            self.green = Double((value >> 8) & 0xFF) / 255
            self.blue = Double(value & 0xFF) / 255
            self.alpha = alpha
        }

        public func withAlpha(_ alpha: Double) -> RGBA {
            RGBA(red: red, green: green, blue: blue, alpha: alpha)
        }
    }

    /// The Liquid Glass color set for one appearance (light or dark).
    public struct GlassPalette: Equatable {
        public let glassFill: RGBA
        public let titlebarFill: RGBA
        public let border: RGBA
        public let innerHighlight: RGBA
        public let hairline: RGBA
        public let fieldFill: RGBA
        public let fieldText: RGBA
        public let textPrimary: RGBA
        public let textSecondary: RGBA
        public let iconPrimary: RGBA
        public let iconMuted: RGBA
    }

    /// The faint disc behind an icon button inside the address bar while the pointer is over it.
    /// The icon itself also goes from `iconPrimary` to `textPrimary`, but that step alone (82% →
    /// 100% opacity in light) is too small to read as a response.
    public static func addressBarIconHoverBackground(dark: Bool) -> RGBA {
        dark ? RGBA(red: 1, green: 1, blue: 1, alpha: 0.12) : RGBA(red: 0, green: 0, blue: 0, alpha: 0.07)
    }

    /// - Parameter dark: `true` for the dark-appearance palette, `false` for light.
    public static func glassPalette(dark: Bool) -> GlassPalette {
        dark ? darkGlassPalette : lightGlassPalette
    }

    private static let lightGlassPalette = GlassPalette(
        glassFill: RGBA(red: 255 / 255, green: 255 / 255, blue: 255 / 255, alpha: 0.55),
        titlebarFill: RGBA(red: 248 / 255, green: 248 / 255, blue: 250 / 255, alpha: 0.72),
        border: RGBA(red: 255 / 255, green: 255 / 255, blue: 255 / 255, alpha: 0.6),
        innerHighlight: RGBA(red: 255 / 255, green: 255 / 255, blue: 255 / 255, alpha: 0.85),
        hairline: RGBA(red: 0, green: 0, blue: 0, alpha: 0.08),
        fieldFill: RGBA(red: 0, green: 0, blue: 0, alpha: 0.045),
        fieldText: RGBA(hex: "1D1D1F", alpha: 0.75),
        textPrimary: RGBA(hex: "1D1D1F"),
        textSecondary: RGBA(red: 60 / 255, green: 60 / 255, blue: 67 / 255, alpha: 0.6),
        iconPrimary: RGBA(hex: "1D1D1F", alpha: 0.82),
        iconMuted: RGBA(hex: "1D1D1F", alpha: 0.24)
    )

    private static let darkGlassPalette = GlassPalette(
        glassFill: RGBA(red: 44 / 255, green: 44 / 255, blue: 48 / 255, alpha: 0.55),
        titlebarFill: RGBA(red: 28 / 255, green: 28 / 255, blue: 32 / 255, alpha: 0.72),
        border: RGBA(red: 255 / 255, green: 255 / 255, blue: 255 / 255, alpha: 0.10),
        innerHighlight: RGBA(red: 255 / 255, green: 255 / 255, blue: 255 / 255, alpha: 0.05),
        hairline: RGBA(red: 255 / 255, green: 255 / 255, blue: 255 / 255, alpha: 0.08),
        fieldFill: RGBA(red: 0, green: 0, blue: 0, alpha: 0.25),
        fieldText: RGBA(hex: "F5F5F7", alpha: 0.85),
        textPrimary: RGBA(hex: "F5F5F7"),
        textSecondary: RGBA(red: 235 / 255, green: 235 / 255, blue: 245 / 255, alpha: 0.65),
        iconPrimary: RGBA(hex: "F5F5F7", alpha: 0.9),
        iconMuted: RGBA(hex: "F5F5F7", alpha: 0.28)
    )

    /// The system accent color options offered by the design canvas, matching macOS's own
    /// accent-color picker. `.orange` is the documented default.
    public enum AccentSwatch: String, CaseIterable, Sendable {
        case orange, blue, purple, pink, red, green, graphite

        public var hex: String {
            switch self {
            case .orange: return "#FF9500"
            case .blue: return "#007AFF"
            case .purple: return "#AF52DE"
            case .pink: return "#FF375F"
            case .red: return "#FF3B30"
            case .green: return "#34C759"
            case .graphite: return "#8E8E93"
            }
        }

        public var rgba: RGBA { RGBA(hex: hex) }
    }

    public static let defaultAccent: AccentSwatch = .orange

    /// The typeface Mochi draws with. Always the system font — no custom brand typeface is
    /// shipped — so this exists to record that choice as an intentional decision (map to
    /// SwiftUI's `.system(...)` or AppKit's `NSFont.systemFont`), not to carry a CSS-style
    /// font stack string.
    public enum FontFamily: Sendable {
        case system
    }

    public static let fontFamily: FontFamily = .system

    #if canImport(AppKit)
        /// The live system accent color, for the normal app runtime. Preview/test contexts
        /// without a real AppKit environment should use `defaultAccent.rgba` (or another
        /// `AccentSwatch`) directly instead of calling this.
        public static func resolveSystemAccent() -> RGBA {
            guard let converted = NSColor.controlAccentColor.usingColorSpace(.deviceRGB) else {
                return defaultAccent.rgba
            }
            return RGBA(
                red: converted.redComponent,
                green: converted.greenComponent,
                blue: converted.blueComponent,
                alpha: converted.alphaComponent
            )
        }
    #endif

    /// The colors an accent-tinted active control (Pin, Ghost Mode toggle) draws with —
    /// a tinted glass background and border plus a solid-accent icon, matching macOS's own
    /// selected-state glass tinting.
    public struct AccentTint: Equatable {
        public let background: RGBA
        public let border: RGBA
        public let icon: RGBA
    }

    public static func accentTint(_ accent: RGBA) -> AccentTint {
        AccentTint(background: accent.withAlpha(0.18), border: accent.withAlpha(0.45), icon: accent)
    }

    /// The Ghost Mode window's drop shadow, as a function of its current content opacity —
    /// "the more transparent the window, the fainter its shadow", so a barely-visible window
    /// doesn't drag around an obviously-visible shadow ring. Matches the `ghostShadow` formula
    /// in `design/mochi/GhostMode.dc.html` / `GhostToolbar.dc.html`.
    public struct GhostShadow: Equatable {
        public let verticalOffset: Double
        public let blurRadius: Double
        public let alpha: Double
    }

    /// - Parameter contentOpacity: the window's current target opacity, `0...1`.
    public static func ghostShadow(forContentOpacity contentOpacity: Double) -> GhostShadow {
        let opacity = min(max(contentOpacity, 0), 1)
        let alpha = min(max(opacity * 0.5, 0.04), 0.45)
        return GhostShadow(
            verticalOffset: (20 * opacity + 6).rounded(),
            blurRadius: (40 * opacity + 10).rounded(),
            alpha: alpha
        )
    }

    /// Corner radii, spacing, and fixed dimensions for the glass surfaces, measured off the
    /// design canvas.
    public enum Layout {
        public static let windowCornerRadius: Double = 14

        /// The Normal Mode toolbar's own buttons (ADR-0009) — the back/forward segments plus Pin
        /// and settings. Sized against ADR-0011's Safari reference measurement (36×36 back/forward
        /// buttons inside a 52pt unified row), replacing ADR-0009's original 22pt estimate. The
        /// glyphs inside are SF Symbols (and the ghost, matched to their metrics via
        /// `SymbolMetrics`), each a good deal smaller than this box — so this number is the
        /// button's hit area, not the glyph's.
        public static let normalModeToolbarButtonDiameter: Double = 36

        /// Safari's own address-field height, measured for ADR-0011 (was 24pt before).
        public static let addressFieldHeight: Double = 31

        /// The Smart Address Field's elastic width bounds (ADR-0011) — it grows and shrinks
        /// between these, rather than stretching to fill every point left over between its
        /// neighbours the way it did before. The minimum is what still shows a readable host +
        /// the embedded refresh icon; the maximum keeps a wide window from turning the field into
        /// one enormous bar, matching Safari's own bounded behavior. The maximum is close to
        /// Safari's own address group (492pt, read off its accessibility tree); 320 cut long
        /// titles short even in a wide window.
        public static let addressFieldMinWidth: Double = 200
        public static let addressFieldMaxWidth: Double = 480

        /// The `.unified` toolbar row's height (ADR-0011 measured it at 52 and pinned the style to
        /// get it). Used as the *starting* value for the web view's obscured inset and the
        /// backdrop, before the window can report its real `contentLayoutRect` — which it cannot
        /// do until it has laid out, i.e. after the startup page has already begun loading.
        /// Changing that inset mid-load leaves WebKit laid out but never painted (a blank page
        /// until something forces a redraw), so it has to be right from the first frame rather
        /// than corrected into place. `updateTitlebarMetrics` still reconciles it against the
        /// real measurement; they agree in practice, so nothing changes and nothing repaints.
        public static let normalModeToolbarRowHeight: Double = 52

        /// Breathing room left around the address bar's capsule inside its toolbar item, so the
        /// focus ring drawn *outside* the capsule has somewhere to land. `NSToolbarItemViewer`
        /// gives a hosted view only 4pt of horizontal slack, and the ring wants about 3 of its own
        /// on every side — measured, the ring's left and right arcs came back sliced flat against
        /// that boundary while the top and bottom (which have ~10pt to spare) drew intact.
        public static let addressFieldFocusRingInset: Double = 3

        /// The refresh affordance embedded at the address bar's trailing edge (ADR-0011) —
        /// smaller than a standalone toolbar button since it sits *inside* the 31pt capsule.
        public static let addressFieldEmbeddedIconDiameter: Double = 20
        public static let addressFieldEmbeddedIconTrailingPadding: Double = 4

        /// The site icon at the address field's leading edge — the favicon, or the symbol standing
        /// in for it. Sized to match what `NSSearchField`'s built-in magnifying glass occupied
        /// before the field became a plain `NSTextField`.
        public static let addressFieldLeadingIconDiameter: Double = 16
        /// Mirrors the refresh affordance: the site icon's center sits as far from the capsule's
        /// leading edge as refresh's does from the trailing one (14pt), so on a page the two
        /// read as a matched pair framing the title.
        public static let addressFieldLeadingIconLeadingPadding: Double =
            addressFieldEmbeddedIconTrailingPadding
                + (addressFieldEmbeddedIconDiameter - addressFieldLeadingIconDiameter) / 2
        /// Between the site icon and the text field's frame. The borderless field's cell adds ~2pt
        /// of its own before the first glyph, so the visible icon-to-text gap is about 4pt.
        public static let addressFieldLeadingIconTextGap: Double = 2

        /// Normal Mode's minimum window width — measured, not derived from Safari's 574pt (which
        /// is calibrated to Safari's larger always-visible set, sidebar toggle included). Nothing
        /// in the toolbar is allowed to collapse into an overflow "»": the Ghost Mode button is
        /// simply hidden once the row can't hold it (`ghostModeButtonMinWindowWidth`), leaving only the
        /// navigation control and the address field at `addressFieldMinWidth` — and this floor is
        /// where those two still fit. Sweeping the real window width 2pt at a time found the
        /// address field going into the overflow menu at 390pt and still in place at 392pt; no
        /// margin, so lowering it at all brings the "»" back. Re-measure rather than re-deriving
        /// it from the button sizes if any of them change.
        public static let normalModeWindowMinWidth: Double = 392

        /// Below this window width the Ghost Mode button is hidden rather than left for AppKit to
        /// sweep into an overflow "»". Measured the same way as `normalModeWindowMinWidth`: with
        /// the button shown, AppKit moved it into the overflow menu at 450pt and kept it at 452pt.
        /// Re-measure if the button, the navigation control or `addressFieldMinWidth` change.
        public static let ghostModeButtonMinWindowWidth: Double = 452

        /// The Loading Progress Bar's (#18) fixed height — a thin line under the toolbar, not a
        /// full-height track, per docs/design-language.md.
        public static let loadingProgressBarHeight: Double = 2

        public static let emptyPageGlassPanelCornerRadius: Double = 24

        /// The stroke weight `GhostGlyph`'s silhouette is drawn with *at
        /// `SymbolMetrics.referencePointSize`* — matching docs/design-language.md's "统一描边粗细、
        /// 圆角端点" (even stroke weight, rounded caps), and calibrated so the hand-drawn ghost
        /// carries the same visual weight as the real SF Symbols beside it (measured: `.regular`
        /// system symbols stroke at ≈1.75 at 15pt). `SymbolMetrics` scales it with point size;
        /// don't use this raw at another size.
        public static let iconStrokeWidth: Double = 1.75
    }

    /// One control in a toolbar's fixed left-to-right button order.
    public enum Motion {
        /// The address bar sliding between its display layout (icon + text centered) and its
        /// editing layout (icon at the leading edge, field across the whole middle).
        public static let addressBarModeChange: Double = 0.25
    }

    public enum ToolbarButton: Equatable, Sendable {
        case back, forward, refresh, addressField, ghostModeToggle
    }

    /// Normal Mode's full toolbar in visual left-to-right order (ADR-0011). Two entries no longer
    /// map to a control of their own: `.back`/`.forward` render as the two segments of a single
    /// `NSSegmentedControl`, and `.refresh` is the icon embedded at the address field's trailing
    /// edge — which is why it now sits *after* `.addressField` rather than before it. This order
    /// is fixed by the design canvas, not a free choice.
    public static let normalModeToolbarOrder: [ToolbarButton] = [
        .back, .forward, .addressField, .refresh, .ghostModeToggle,
    ]

    /// The SF Symbols the native chrome draws. Named here rather than written as string
    /// literals at each use site so `DesignTokensTests` can assert every one resolves against the
    /// deployment SDK — a mistyped symbol name is otherwise invisible until the glyph silently
    /// fails to appear at runtime.
    ///
    /// The ghost is deliberately absent: SF Symbols has no ghost, so it stays hand-drawn in
    /// `GhostGlyph`, matched to these symbols' metrics via `SymbolMetrics`.
    public enum Symbol {
        public static let back = "chevron.left"
        public static let forward = "chevron.right"
        public static let refresh = "arrow.clockwise"
        /// The address bar's embedded stop (#60) and the Display menu's 停止 — Safari's own.
        public static let stop = "xmark"
        /// The error page's (#38) failure glyph.
        public static let failure = "exclamationmark.triangle"
        /// The tray's 打开窗口 (#63).
        public static let openWidget = "macwindow"
        /// The tray's 隐藏窗口 (#63) — the boss key.
        public static let hideWidget = "eye.slash"
        /// 设置… — the App menu's and the tray's (#63).
        public static let settings = "gearshape"
        /// 关于 Mochi — the App menu's and the tray's (#63).
        public static let about = "info.circle"

        /// Every symbol name the app can ask for, the address field's drawn states included.
        /// `.siteIcon` contributes nothing here — it draws a downloaded favicon, not a symbol.
        public static let all: [String] = [
            back, forward, refresh, stop, failure, openWidget, hideWidget, settings, about,
            AddressFieldLeadingIcon.genericPage.symbolName!, AddressFieldLeadingIcon.search.symbolName!,
        ]
    }

    /// What the address bar's leading position shows.
    ///
    /// This used to be a lock once any page had loaded. A lock is every browser's *encryption*
    /// indicator, but nothing here ever looked at the scheme — it only knew a page existed — so
    /// a plain-http page got the same lock an https one did, which is a security claim Mochi
    /// cannot back. The site's own favicon says the useful part ("which site is this") without
    /// saying anything about the connection at all.
    public enum AddressFieldLeadingIcon: Equatable, Sendable {
        /// The site's own favicon, fetched from the site itself (never a third-party favicon
        /// service — that would hand a tracker one request per site visited).
        case siteIcon
        /// A page is loaded but has no favicon Mochi could fetch, or it hasn't arrived yet.
        case genericPage
        /// No page is loaded (Empty Page).
        case search

        /// The SF Symbol that draws this state, or `nil` for `.siteIcon`, which draws an image.
        /// `NSSearchField` supplies its own magnifying glass, but the leading icon has to be set
        /// explicitly either way — the field's stock glyph never changes, so leaving it alone
        /// would pin the address bar to "search" forever.
        public var symbolName: String? {
            switch self {
            case .siteIcon: return nil
            case .genericPage: return "globe"
            case .search: return "magnifyingglass"
            }
        }

        /// What the icon is announced as. Nothing here mentions security: the leading icon tracks
        /// which site is loaded, not how the bytes got here.
        public var accessibilityLabel: String {
            switch self {
            case .siteIcon: return "站点图标"
            case .genericPage: return "页面已加载"
            case .search: return "输入网址"
            }
        }
    }

    public static func addressFieldLeadingIcon(hasLoadedPage: Bool, hasSiteIcon: Bool) -> AddressFieldLeadingIcon {
        guard hasLoadedPage else { return .search }
        return hasSiteIcon ? .siteIcon : .genericPage
    }

    /// Colors for the Empty Page's (#16) abstract Liquid Glass composition and de-emphasized
    /// hotkey quick reference — measured off `design/mochi/EmptyPage.dc.html`.
    public enum EmptyPage {
        /// The composition's front panel — tinted with the resolved system accent, unlike the
        /// back panel below.
        public static func accentGlassPanelTint(_ accent: RGBA, dark: Bool) -> RGBA {
            accent.withAlpha(dark ? 0.16 : 0.14)
        }

        /// The composition's back panel — a fixed blue tint independent of the system accent
        /// color, per the design canvas (only the front panel follows the user's accent choice).
        public static func secondaryGlassPanelTint(dark: Bool) -> RGBA {
            RGBA(red: 120 / 255, green: 150 / 255, blue: 255 / 255, alpha: dark ? 0.16 : 0.14)
        }

        /// The pill background behind each hotkey combo in the quick reference row.
        public static func hotkeyBadgeBackground(dark: Bool) -> RGBA {
            dark ? RGBA(red: 1, green: 1, blue: 1, alpha: 0.10) : RGBA(red: 0, green: 0, blue: 0, alpha: 0.06)
        }

        /// The content area's base fill, beneath the two soft radial-gradient blobs.
        public static func backgroundBase(dark: Bool) -> RGBA {
            dark ? RGBA(hex: "0e0e10") : RGBA(hex: "f4f4f6")
        }
    }
}
