import Foundation

#if canImport(AppKit)
    import AppKit
#endif

/// Single source of truth for Mochi's Liquid Glass visual language: colors, materials,
/// corner radii/spacing, the Ghost Mode shadow-vs-opacity formula, and accent-color
/// resolution. Every native view (Normal Mode toolbar, Ghost Mode summoned overlay, tray
/// icon, Empty Page) should read its numbers from here instead of writing its own.
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

        /// Retained only for Ghost Mode's summoned toolbar overlay (ADR-0009) — the Normal Mode
        /// toolbar itself no longer draws an independent glass capsule, since it now lives inside
        /// the native `NSToolbar` row and its Liquid Glass material is rendered by the system.
        public static let toolbarCapsuleCornerRadius: Double = 16
        public static let toolbarInnerPaddingHorizontal: Double = 8
        public static let toolbarInnerPaddingVertical: Double = 6
        public static let toolbarButtonSpacing: Double = 4
        public static let toolbarButtonDiameter: Double = 30
        public static let toolbarCapsuleHeight: Double = toolbarButtonDiameter + toolbarInnerPaddingVertical * 2

        /// The Normal Mode toolbar's own buttons (ADR-0009) — the back/forward segments plus Pin
        /// and settings. Sized against ADR-0011's Safari reference measurement (36×36 back/forward
        /// buttons inside a 52pt unified row), replacing ADR-0009's original 22pt estimate. The
        /// `DesignIcon` glyphs stay on their own 24×24 grid inside this hit area (the buttons use
        /// `scaleProportionallyDown`, which never upscales), so this number is the button's box,
        /// not the glyph's.
        public static let normalModeToolbarButtonDiameter: Double = 36

        /// Safari's own address-field height, measured for ADR-0011 (was 24pt before).
        public static let addressFieldHeight: Double = 31

        /// The Smart Address Field's elastic width bounds (ADR-0011) — it grows and shrinks
        /// between these, rather than stretching to fill every point left over between its
        /// neighbours the way it did before. The minimum is what still shows a readable host +
        /// the embedded refresh icon; the maximum keeps a wide window from turning the field into
        /// one enormous bar, matching Safari's own bounded behavior.
        public static let addressFieldMinWidth: Double = 200
        public static let addressFieldMaxWidth: Double = 320

        /// The refresh affordance embedded at the address field's trailing edge (ADR-0011) —
        /// smaller than a standalone toolbar button since it sits *inside* the field's 31pt box.
        public static let addressFieldEmbeddedIconDiameter: Double = 20
        public static let addressFieldEmbeddedIconTrailingPadding: Double = 4

        /// Normal Mode's minimum window width — measured, not derived from Safari's 574pt (which
        /// is calibrated to Safari's larger always-visible set, sidebar toggle included). Sweeping
        /// the real window width one point at a time (ADR-0011) found that at 428pt AppKit stops
        /// being able to fit the two items that must never collapse — the back/forward segmented
        /// control and the address field at `addressFieldMinWidth` — and sweeps the address field
        /// itself into the overflow menu. 440 is that threshold plus a small margin. Lowering this
        /// below ~430 re-breaks "the address bar is never collapsed", so re-measure rather than
        /// re-deriving it from the button sizes if any of them change.
        public static let normalModeWindowMinWidth: Double = 440

        /// The Loading Progress Bar's (#18) fixed height — a thin line under the toolbar, not a
        /// full-height track, per docs/design-language.md.
        public static let loadingProgressBarHeight: Double = 2

        /// The summoned toolbar overlay's (#10) distance from the window's top edge — measured
        /// off `design/mochi/GhostToolbar.dc.html`'s `top:14px`; the Normal Mode toolbar's own
        /// row is a native `NSToolbar` (ADR-0009) and has no comparable token.
        public static let ghostModeSummonedToolbarTopMargin: Double = 14

        public static let emptyPageGlassPanelCornerRadius: Double = 24

        /// The uniform stroke weight `DesignIcon` paths are drawn with — matching
        /// docs/design-language.md's "统一描边粗细、圆角端点" (even stroke weight, rounded caps).
        public static let iconStrokeWidth: Double = 1.75
    }

    /// One control in a toolbar's fixed left-to-right button order.
    public enum ToolbarButton: Equatable, Sendable {
        case back, forward, refresh, addressField, pin, ghostModeToggle, settings
    }

    /// Normal Mode's full toolbar in visual left-to-right order (ADR-0011). Two entries no longer
    /// map to a control of their own: `.back`/`.forward` render as the two segments of a single
    /// `NSSegmentedControl`, and `.refresh` is the icon embedded at the address field's trailing
    /// edge — which is why it now sits *after* `.addressField` rather than before it. This order
    /// is fixed by the design canvas, not a free choice.
    public static let normalModeToolbarOrder: [ToolbarButton] = [
        .back, .forward, .addressField, .refresh, .pin, .ghostModeToggle, .settings,
    ]

    /// Ghost Mode's summoned floating toolbar deliberately carries only three controls —
    /// no address bar, no back/forward — since it's a temporary emergency-access surface,
    /// not a navigation UI.
    public static let ghostModeSummonedToolbarOrder: [ToolbarButton] = [
        .pin, .ghostModeToggle, .refresh,
    ]

    /// Which glyph the address bar's leading icon shows.
    public enum AddressFieldGlyph: Equatable, Sendable {
        /// A page is loaded — shows a lock, like a browser's secure-page indicator.
        case lock
        /// No page is loaded (Empty Page) — a lock would misleadingly imply a secure page
        /// that isn't there, so this shows a magnifying glass instead.
        case search
    }

    public static func addressFieldGlyph(hasLoadedPage: Bool) -> AddressFieldGlyph {
        hasLoadedPage ? .lock : .search
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
