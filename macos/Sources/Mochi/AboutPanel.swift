import AppKit
import MochiCore

/// The standard About panel (#37), plus #62's credits line and copyright. Reached only through
/// `Orchestrator.openAboutPanel()` — this type puts the panel up and nothing else; activating the
/// app is the orchestrator's call, through `PlatformOps`.
enum AboutPanel {
    /// `NSAboutPanelOptionKey` has no public constant for the copyright line, but the panel has
    /// always honoured this key (it predates the typed constants and is what overrides
    /// `NSHumanReadableCopyright`). Passing it here, rather than writing the key into
    /// `Info.plist`, is what lets a `swift run` build — which has no plist — show it too.
    private static let copyrightKey = NSApplication.AboutPanelOptionKey(rawValue: "Copyright")

    static func show() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: AppInfo.name,
            .applicationVersion: AppInfo.version(fromInfoDictionary: Bundle.main.infoDictionary),
            .credits: credits(),
            copyrightKey: AppInfo.copyright,
        ])
    }

    /// 「GitHub」|「反馈问题」, centred like the rest of the panel and at the small system size the
    /// panel's own secondary lines use. `.link` makes each word clickable in the panel's text view
    /// (it opens the URL in the default browser); colours come from dynamic system colours so the
    /// line follows light/dark appearance.
    private static func credits() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]

        let credits = NSMutableAttributedString()
        credits.append(link("GitHub", to: AppInfo.repositoryURL, base: base))
        credits.append(NSAttributedString(string: "  |  ", attributes: base))
        credits.append(link("反馈问题", to: AppInfo.issuesURL, base: base))
        return credits
    }

    private static func link(
        _ title: String, to url: URL, base: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        var attributes = base
        attributes[.link] = url
        attributes.removeValue(forKey: .foregroundColor)
        return NSAttributedString(string: title, attributes: attributes)
    }
}
