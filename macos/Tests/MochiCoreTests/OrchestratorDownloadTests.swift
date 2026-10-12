import Foundation
import Testing

@testable import MochiCore

/// The download kind of the 网页交互请求 seam (#68): Normal vs Ghost Mode × each 文件下载位置,
/// through `Orchestrator` and `FakePlatformOps`, against a fake disk.
@Suite struct OrchestratorDownloadTests {
    enum Mode: Sendable { case normal, ghost }
    enum Location: Sendable { case downloads, ask, chosenFolder, missingFolder }
    enum Expected: Sendable { case saveInDownloads, saveInChosen, savePanel }

    static let downloads = URL(fileURLWithPath: "/fake/Downloads", isDirectory: true)
    static let chosen = URL(fileURLWithPath: "/fake/Chosen", isDirectory: true)
    static let missing = URL(fileURLWithPath: "/fake/Gone", isDirectory: true)

    @Test(arguments: [
        (mode: Mode.normal, location: Location.downloads, expected: Expected.saveInDownloads),
        (mode: .normal, location: .ask, expected: .savePanel),
        (mode: .normal, location: .chosenFolder, expected: .saveInChosen),
        (mode: .normal, location: .missingFolder, expected: .saveInDownloads),
        (mode: .ghost, location: .downloads, expected: .saveInDownloads),
        (mode: .ghost, location: .ask, expected: .saveInDownloads),
        (mode: .ghost, location: .chosenFolder, expected: .saveInChosen),
        (mode: .ghost, location: .missingFolder, expected: .saveInDownloads),
    ])
    func downloadDestination(_ row: (mode: Mode, location: Location, expected: Expected)) {
        let location: DownloadLocation =
            switch row.location {
            case .downloads: .downloadsFolder
            case .ask: .askEachTime
            case .chosenFolder: .folder(Self.chosen)
            case .missingFolder: .folder(Self.missing)
            }
        let (fake, orchestrator) = makeWidget(in: row.mode, config: WidgetConfig(url: URL(string: "https://example.com")!).updatingDownloadLocation(location))
        defer { withExtendedLifetime(orchestrator) {} }

        let decision = fake.simulateDownloadRequested(DownloadRequest(suggestedFilename: "clip.mp4"))

        let expected: DownloadDestinationDecision =
            switch row.expected {
            case .saveInDownloads: .saveTo(Self.downloads.appendingPathComponent("clip.mp4"))
            case .saveInChosen: .saveTo(Self.chosen.appendingPathComponent("clip.mp4"))
            case .savePanel: .askWithSavePanel(directory: Self.downloads, suggestedFilename: "clip.mp4")
            }
        #expect(decision == expected)
        // Never leaves Ghost Mode to ask.
        #expect((fake.mousePassthroughChanges.last?.enabled ?? false) == (row.mode == .ghost))
    }

    /// The setting is read at the moment of each download, not when the window opened.
    @Test func followsASettingChangedAfterOpening() {
        var config = WidgetConfig(url: URL(string: "https://example.com")!)
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.downloadFileSystem = Self.fakeFileSystem
        orchestrator.start()

        config = config.updatingDownloadLocation(.askEachTime)

        #expect(
            fake.simulateDownloadRequested(DownloadRequest(suggestedFilename: "a.zip"))
                == .askWithSavePanel(directory: Self.downloads, suggestedFilename: "a.zip"))
    }

    @Test func reopenedWidgetStillAnswersDownloads() {
        let (fake, orchestrator) = makeWidget(in: .normal, config: WidgetConfig(url: URL(string: "https://example.com")!))
        orchestrator.closeWidget()
        orchestrator.openWidget()

        #expect(
            fake.simulateDownloadRequested(DownloadRequest(suggestedFilename: "a.zip"), windowID: 2)
                == .saveTo(Self.downloads.appendingPathComponent("a.zip")))
    }

    /// #99: the handler hands WebKit its answer through the completion once the disk work is
    /// done, never touching the disk itself — while the setting and the mode are still read at
    /// the moment of the download, not when the disk work happens to run.
    @Test func answersThroughTheCompletionAfterTheDiskWork() {
        let config = WidgetConfig(url: URL(string: "https://example.com")!).updatingDownloadLocation(.askEachTime)
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        var diskChecks = 0
        var pending: [() -> Void] = []
        var fileSystem = Self.fakeFileSystem
        fileSystem.fileExists = { _ in
            diskChecks += 1
            return false
        }
        fileSystem.offMainThread = { access, deliver in pending.append { deliver(access()) } }
        orchestrator.downloadFileSystem = fileSystem
        orchestrator.start()
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        defer { withExtendedLifetime(orchestrator) {} }

        var delivered: [DownloadDestinationDecision] = []
        fake.simulateDownloadRequested(DownloadRequest(suggestedFilename: "a.zip")) { delivered.append($0) }
        // Leaving Ghost Mode before the disk work runs doesn't turn the answer into a Save panel.
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)

        #expect(diskChecks == 0)
        #expect(delivered.isEmpty)

        pending.forEach { $0() }

        #expect(delivered == [.saveTo(Self.downloads.appendingPathComponent("a.zip"))])
        #expect(diskChecks == 1)
    }

    static var fakeFileSystem: DownloadFileSystem {
        DownloadFileSystem(
            downloadsFolder: downloads, fileExists: { _ in false }, isWritableDirectory: { $0 != missing })
    }

    private func makeWidget(in mode: Mode, config: WidgetConfig) -> (FakePlatformOps, Orchestrator) {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.downloadFileSystem = Self.fakeFileSystem
        orchestrator.start()
        if mode == .ghost { fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode) }
        return (fake, orchestrator)
    }
}
