import Foundation
import Testing

@testable import MochiCore

@Suite struct StartupContentTests {
    private static let lastVisited = URL(string: "https://last-visited.example.com")!
    private static let fixedStartup = URL(string: "https://fixed-startup.example.com")!

    @Test func explicitURLOverrideWinsRegardlessOfLastVisitedURL() {
        let config = WidgetConfig(url: Self.lastVisited, startupTarget: .url(Self.fixedStartup))

        #expect(StartupResolution.resolveStartupContent(for: config) == .url(Self.fixedStartup))
    }

    @Test func explicitEmptyPageOverrideWinsEvenWithALastVisitedURL() {
        let config = WidgetConfig(url: Self.lastVisited, startupTarget: .emptyPage)

        #expect(StartupResolution.resolveStartupContent(for: config) == .emptyPage)
    }

    @Test func fallsBackToLastVisitedURLWhenNoOverrideIsSet() {
        let config = WidgetConfig(url: Self.lastVisited, startupTarget: nil)

        #expect(StartupResolution.resolveStartupContent(for: config) == .url(Self.lastVisited))
    }

    @Test func fallsBackToEmptyPageWhenNoOverrideIsSetAndThereIsNoHistory() {
        let config = WidgetConfig(url: nil, startupTarget: nil)

        #expect(StartupResolution.resolveStartupContent(for: config) == .emptyPage)
    }
}
