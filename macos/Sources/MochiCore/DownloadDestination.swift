import Foundation

/// 通用 → 文件下载位置 (#68): Safari's three options, same names.
public enum DownloadLocation: Equatable, Sendable {
    /// "下载" — the user's Downloads folder. The default.
    case downloadsFolder
    /// "每次询问" — a Save panel per download (Normal Mode only; see `DownloadDestination`).
    case askEachTime
    /// "其他…" — a folder the user picked. Falls back to Downloads when it has gone missing or
    /// can't be written to, so a deleted folder never makes downloads silently fail.
    case folder(URL)
}

/// The file-system facts a destination decision depends on, injected so the decision stays a pure
/// function and tests never touch the real disk (least of all the user's real ~/Downloads).
public struct DownloadFileSystem {
    public var downloadsFolder: URL
    public var fileExists: (URL) -> Bool
    /// An existing directory this process can create files in.
    public var isWritableDirectory: (URL) -> Bool

    public init(
        downloadsFolder: URL, fileExists: @escaping (URL) -> Bool, isWritableDirectory: @escaping (URL) -> Bool
    ) {
        self.downloadsFolder = downloadsFolder
        self.fileExists = fileExists
        self.isWritableDirectory = isWritableDirectory
    }

    public static var live: DownloadFileSystem {
        DownloadFileSystem(
            downloadsFolder: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0],
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            isWritableDirectory: { url in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                    && isDirectory.boolValue && FileManager.default.isWritableFile(atPath: url.path)
            })
    }
}

/// Decides where a download lands (#68) — the location kind, the fallback for a folder that has
/// gone bad, the " (n)" rename on collision, and Ghost Mode's degradation of 每次询问 (CONTEXT.md
/// 「Ghost Mode」: a request needing the user is settled without UI — the file goes to the default
/// location instead of a Save panel appearing).
public enum DownloadDestination {
    /// How many " (n)" suffixes to try before falling back to a UUID suffix — far beyond anything
    /// real, it only bounds the loop.
    static let maxCollisionSuffix = 9_999

    public static func decide(
        suggestedFilename: String, location: DownloadLocation, isGhostModeActive: Bool, fileSystem: DownloadFileSystem
    ) -> DownloadDestinationDecision {
        let filename = sanitizedFilename(suggestedFilename)
        let directory: URL
        switch location {
        case .downloadsFolder:
            directory = fileSystem.downloadsFolder
        case .askEachTime:
            guard isGhostModeActive else {
                // The Save panel handles its own collisions (it asks before replacing), so the
                // name is only a suggestion here.
                return .askWithSavePanel(directory: fileSystem.downloadsFolder, suggestedFilename: filename)
            }
            directory = fileSystem.downloadsFolder
        case .folder(let folder):
            directory = fileSystem.isWritableDirectory(folder) ? folder : fileSystem.downloadsFolder
        }
        return .saveTo(uniqueFileURL(for: filename, in: directory, fileExists: fileSystem.fileExists))
    }

    /// `name.ext`, else `name (1).ext`, `name (2).ext`, … — the first that doesn't exist. The
    /// suffix goes before the last extension (Safari's form); a leading dot (`.bashrc`) is part
    /// of the name, not an extension.
    static func uniqueFileURL(for filename: String, in directory: URL, fileExists: (URL) -> Bool) -> URL {
        let candidate = directory.appendingPathComponent(filename, isDirectory: false)
        guard fileExists(candidate) else { return candidate }
        let (stem, ext) = splitExtension(filename)
        for n in 1...maxCollisionSuffix {
            let url = directory.appendingPathComponent("\(stem) (\(n))\(ext)", isDirectory: false)
            if !fileExists(url) { return url }
        }
        return directory.appendingPathComponent("\(stem) (\(UUID().uuidString))\(ext)", isDirectory: false)
    }

    /// A name safe to use as one path component: no `/` (a path separator) or `:` (Finder shows
    /// it as `/`), no leading dots-only or empty name.
    static func sanitizedFilename(_ suggested: String) -> String {
        let cleaned = suggested
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || cleaned.allSatisfy({ $0 == "." }) { return "未命名" }
        return cleaned
    }

    /// Splits at the last dot, keeping the dot with the extension; a dot at index 0 doesn't count.
    private static func splitExtension(_ filename: String) -> (stem: String, ext: String) {
        guard let dot = filename.lastIndex(of: "."), dot != filename.startIndex else { return (filename, "") }
        return (String(filename[..<dot]), String(filename[dot...]))
    }
}
