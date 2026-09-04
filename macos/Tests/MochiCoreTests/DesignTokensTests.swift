import Foundation
import Testing

@testable import MochiCore

@Suite struct DesignTokensTests {
    @Test func lightGlassPaletteMatchesTheDesignCanvas() {
        let palette = DesignTokens.glassPalette(dark: false)

        #expect(palette.textPrimary == DesignTokens.RGBA(hex: "1D1D1F"))
        #expect(palette.glassFill == DesignTokens.RGBA(red: 1, green: 1, blue: 1, alpha: 0.55))
        #expect(palette.border == DesignTokens.RGBA(red: 1, green: 1, blue: 1, alpha: 0.6))
        #expect(palette.hairline == DesignTokens.RGBA(red: 0, green: 0, blue: 0, alpha: 0.08))
    }

    @Test func darkGlassPaletteMatchesTheDesignCanvas() {
        let palette = DesignTokens.glassPalette(dark: true)

        #expect(palette.textPrimary == DesignTokens.RGBA(hex: "F5F5F7"))
        #expect(palette.glassFill == DesignTokens.RGBA(red: 44 / 255, green: 44 / 255, blue: 48 / 255, alpha: 0.55))
        #expect(palette.border == DesignTokens.RGBA(red: 1, green: 1, blue: 1, alpha: 0.10))
        #expect(palette.hairline == DesignTokens.RGBA(red: 1, green: 1, blue: 1, alpha: 0.08))
    }

    @Test func lightAndDarkPalettesDiffer() {
        #expect(DesignTokens.glassPalette(dark: false) != DesignTokens.glassPalette(dark: true))
    }

    @Test func rgbaParsesThreeAndSixDigitHex() {
        #expect(DesignTokens.RGBA(hex: "#FF9500") == DesignTokens.RGBA(hex: "FF9500"))
        #expect(DesignTokens.RGBA(hex: "F00") == DesignTokens.RGBA(hex: "FF0000"))
    }

    @Test func accentSwatchesMatchTheDocumentedPalette() {
        #expect(DesignTokens.AccentSwatch.orange.hex == "#FF9500")
        #expect(DesignTokens.AccentSwatch.blue.hex == "#007AFF")
        #expect(DesignTokens.AccentSwatch.purple.hex == "#AF52DE")
        #expect(DesignTokens.AccentSwatch.pink.hex == "#FF375F")
        #expect(DesignTokens.AccentSwatch.red.hex == "#FF3B30")
        #expect(DesignTokens.AccentSwatch.green.hex == "#34C759")
        #expect(DesignTokens.AccentSwatch.graphite.hex == "#8E8E93")
        #expect(DesignTokens.defaultAccent == .orange)
    }

    @Test func accentTintDerivesBackgroundAndBorderAlphaFromTheAccentColor() {
        let accent = DesignTokens.AccentSwatch.orange.rgba
        let tint = DesignTokens.accentTint(accent)

        #expect(tint.icon == accent)
        #expect(tint.background == accent.withAlpha(0.18))
        #expect(tint.border == accent.withAlpha(0.45))
    }

    @Test func ghostShadowFadesAsOpacityDrops() {
        let opacities = stride(from: 0.1, through: 0.9, by: 0.1).map { $0 }
        let shadows = opacities.map(DesignTokens.ghostShadow(forContentOpacity:))

        for (previous, next) in zip(shadows, shadows.dropFirst()) {
            #expect(next.blurRadius >= previous.blurRadius)
            #expect(next.verticalOffset >= previous.verticalOffset)
            #expect(next.alpha >= previous.alpha)
        }
    }

    @Test func ghostShadowClampsAlphaToTheDocumentedRange() {
        #expect(DesignTokens.ghostShadow(forContentOpacity: 0).alpha == 0.04)
        #expect(DesignTokens.ghostShadow(forContentOpacity: 1).alpha == 0.45)
    }

    @Test func ghostShadowClampsOutOfRangeOpacity() {
        #expect(DesignTokens.ghostShadow(forContentOpacity: -1) == DesignTokens.ghostShadow(forContentOpacity: 0))
        #expect(DesignTokens.ghostShadow(forContentOpacity: 2) == DesignTokens.ghostShadow(forContentOpacity: 1))
    }

    @Test func normalModeToolbarOrderIsFixed() {
        #expect(DesignTokens.normalModeToolbarOrder == [
            .back, .forward, .addressField, .refresh, .pin, .ghostModeToggle, .settings,
        ])
    }

    @Test func ghostModeSummonedToolbarOmitsNavigationControls() {
        #expect(DesignTokens.ghostModeSummonedToolbarOrder == [.pin, .ghostModeToggle, .refresh])
        #expect(!DesignTokens.ghostModeSummonedToolbarOrder.contains(.addressField))
        #expect(!DesignTokens.ghostModeSummonedToolbarOrder.contains(.back))
        #expect(!DesignTokens.ghostModeSummonedToolbarOrder.contains(.forward))
    }

    @Test func addressFieldGlyphSwitchesOnWhetherAPageIsLoaded() {
        #expect(DesignTokens.addressFieldGlyph(hasLoadedPage: true) == .lock)
        #expect(DesignTokens.addressFieldGlyph(hasLoadedPage: false) == .search)
    }

    @Test func toolbarCapsuleHeightIsDerivedFromButtonSizeAndPadding() {
        #expect(DesignTokens.Layout.toolbarCapsuleHeight == 42)
    }

    @Test func fontFamilyIsTheSystemFontNotACustomBrandTypeface() {
        #expect(DesignTokens.fontFamily == .system)
    }

    @Test func emptyPageSecondaryGlassPanelTintIsFixedRegardlessOfAccent() {
        #expect(DesignTokens.EmptyPage.secondaryGlassPanelTint(dark: false) == DesignTokens.RGBA(red: 120 / 255, green: 150 / 255, blue: 1, alpha: 0.14))
        #expect(DesignTokens.EmptyPage.secondaryGlassPanelTint(dark: true) == DesignTokens.RGBA(red: 120 / 255, green: 150 / 255, blue: 1, alpha: 0.16))
    }

    @Test func emptyPageAccentGlassPanelTintFollowsTheGivenAccent() {
        let accent = DesignTokens.AccentSwatch.blue.rgba
        #expect(DesignTokens.EmptyPage.accentGlassPanelTint(accent, dark: false) == accent.withAlpha(0.14))
        #expect(DesignTokens.EmptyPage.accentGlassPanelTint(accent, dark: true) == accent.withAlpha(0.16))
    }

    @Test func emptyPageBackgroundBaseDiffersBetweenLightAndDark() {
        #expect(DesignTokens.EmptyPage.backgroundBase(dark: false) == DesignTokens.RGBA(hex: "f4f4f6"))
        #expect(DesignTokens.EmptyPage.backgroundBase(dark: true) == DesignTokens.RGBA(hex: "0e0e10"))
    }
}
