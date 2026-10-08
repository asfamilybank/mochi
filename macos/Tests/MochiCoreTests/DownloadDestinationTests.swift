import Foundation
import Testing

@testable import MochiCore

/// 文件下载位置 (#68): where a download lands, given the setting, Ghost Mode and what's on disk.
/// The disk is a fake — no test here touches a real folder.
@Suite struct DownloadDestinationTests {
    static let downloads = URL(fileURLWithPath: "/fake/Downloads", isDirectory: true)
    static let chosen = URL(fileURLWithPath: "/fake/Chosen", isDirectory: true)

    enum Location: Sendable { case downloads, ask, chosenFolder }
    enum FolderState: Sendable { case writable, missingOrUnwritable }
    enum Expected: Equatable, Sendable { case saveInDownloads, saveInChosen, savePanel }

    @Test(arguments: [
        (location: Location.downloads, ghost: false, folder: FolderState.writable, expected: Expected.saveInDownloads),
        (location: .downloads, ghost: true, folder: .writable, expected: .saveInDownloads),
        (location: .ask, ghost: false, folder: .writable, expected: .savePanel),
        // Ghost Mode "不打扰": no Save panel, straight to the default location.
        (location: .ask, ghost: true, folder: .writable, expected: .saveInDownloads),
        (location: .chosenFolder, ghost: false, folder: .writable, expected: .saveInChosen),
        (location: .chosenFolder, ghost: true, folder: .writable, expected: .saveInChosen),
        // A folder gone missing or read-only falls back to Downloads.
        (location: .chosenFolder, ghost: false, folder: .missingOrUnwritable, expected: .saveInDownloads),
        (location: .chosenFolder, ghost: true, folder: .missingOrUnwritable, expected: .saveInDownloads),
    ])
    func decidesByLocationModeAndFolderState(
        _ row: (location: Location, ghost: Bool, folder: FolderState, expected: Expected)
    ) {
        let location: DownloadLocation =
            switch row.location {
            case .downloads: .downloadsFolder
            case .ask: .askEachTime
            case .chosenFolder: .folder(Self.chosen)
            }
        let fileSystem = Self.fakeFileSystem(chosenFolderIsWritable: row.folder == .writable)

        let decision = DownloadDestination.decide(
            suggestedFilename: "report.pdf", location: location, isGhostModeActive: row.ghost, fileSystem: fileSystem)

        let expected: DownloadDestinationDecision =
            switch row.expected {
            case .saveInDownloads: .saveTo(Self.downloads.appendingPathComponent("report.pdf"))
            case .saveInChosen: .saveTo(Self.chosen.appendingPathComponent("report.pdf"))
            case .savePanel: .askWithSavePanel(directory: Self.downloads, suggestedFilename: "report.pdf")
            }
        #expect(decision == expected)
    }

    @Test(arguments: [
        (name: "report.pdf", existing: [String](), expected: "report.pdf"),
        (name: "report.pdf", existing: ["report.pdf"], expected: "report (1).pdf"),
        (name: "report.pdf", existing: ["report.pdf", "report (1).pdf", "report (2).pdf"], expected: "report (3).pdf"),
        // Only the last extension moves behind the suffix.
        (name: "archive.tar.gz", existing: ["archive.tar.gz"], expected: "archive.tar (1).gz"),
        (name: "README", existing: ["README"], expected: "README (1)"),
        // A leading dot is part of the name, not an extension.
        (name: ".bashrc", existing: [".bashrc"], expected: ".bashrc (1)"),
        (name: "文件.pdf", existing: ["文件.pdf"], expected: "文件 (1).pdf"),
    ])
    func collisionsGetANumberedSuffix(_ row: (name: String, existing: [String], expected: String)) {
        let existing = Set(row.existing.map { Self.downloads.appendingPathComponent($0).path })
        let fileSystem = DownloadFileSystem(
            downloadsFolder: Self.downloads, fileExists: { existing.contains($0.path) }, isWritableDirectory: { _ in true })

        let decision = DownloadDestination.decide(
            suggestedFilename: row.name, location: .downloadsFolder, isGhostModeActive: false, fileSystem: fileSystem)

        #expect(decision == .saveTo(Self.downloads.appendingPathComponent(row.expected)))
    }

    /// A Save panel asks before replacing on its own, so its suggestion is not renamed.
    @Test func savePanelSuggestionIsNotRenamedOnCollision() {
        let fileSystem = DownloadFileSystem(
            downloadsFolder: Self.downloads, fileExists: { _ in true }, isWritableDirectory: { _ in true })
        let decision = DownloadDestination.decide(
            suggestedFilename: "a.zip", location: .askEachTime, isGhostModeActive: false, fileSystem: fileSystem)
        #expect(decision == .askWithSavePanel(directory: Self.downloads, suggestedFilename: "a.zip"))
    }

    @Test(arguments: [
        (suggested: "a/b.txt", expected: "a_b.txt"),
        (suggested: "a:b.txt", expected: "a_b.txt"),
        (suggested: "  x.txt ", expected: "x.txt"),
        (suggested: "", expected: "未命名"),
        (suggested: "..", expected: "未命名"),
    ])
    func unsafeSuggestedNamesAreSanitized(_ row: (suggested: String, expected: String)) {
        let decision = DownloadDestination.decide(
            suggestedFilename: row.suggested, location: .downloadsFolder, isGhostModeActive: false,
            fileSystem: Self.fakeFileSystem(chosenFolderIsWritable: true))
        #expect(decision == .saveTo(Self.downloads.appendingPathComponent(row.expected)))
    }

    static func fakeFileSystem(chosenFolderIsWritable: Bool) -> DownloadFileSystem {
        DownloadFileSystem(
            downloadsFolder: downloads, fileExists: { _ in false },
            isWritableDirectory: { $0 == chosen ? chosenFolderIsWritable : true })
    }
}
