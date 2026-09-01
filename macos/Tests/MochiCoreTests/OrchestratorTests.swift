import Foundation
import Testing

@testable import MochiCore

@Suite struct OrchestratorTests {
    @Test func startsWidgetWindowAndLoadsConfiguredURL() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(url: URL(string: "https://example.com")!)

        orchestrator.start(config: config)

        #expect(fake.createdWindowCount == 1)
        #expect(fake.loadedURLs.map(\.url) == [config.url])
        #expect(fake.shownWindowIDs == [1])
    }
}
