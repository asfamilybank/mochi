import AppKit
import MochiCore
import SwiftUI

/// 通用 → 文件下载位置 (#68), Safari's popup: 下载 / 每次询问 / 其他…. Once a folder has been
/// picked it is listed by name (with its Finder icon) above 其他…, which picks another.
struct DownloadLocationSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    private enum Choice: Hashable {
        case downloads, ask, chosenFolder, other
    }

    var body: some View {
        Section("下载") {
            Picker("文件下载位置", selection: Binding(get: { currentChoice }, set: choose)) {
                Text("下载").tag(Choice.downloads)
                Text("每次询问").tag(Choice.ask)
                if case .folder(let folder) = viewModel.config.downloadLocation {
                    Divider()
                    Label {
                        Text(FileManager.default.displayName(atPath: folder.path))
                    } icon: {
                        Image(nsImage: Self.icon(for: folder))
                    }
                    .tag(Choice.chosenFolder)
                }
                Divider()
                Text("其他…").tag(Choice.other)
            }
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    private var currentChoice: Choice {
        switch viewModel.config.downloadLocation {
        case .downloadsFolder: .downloads
        case .askEachTime: .ask
        case .folder: .chosenFolder
        }
    }

    private func choose(_ choice: Choice) {
        switch choice {
        case .downloads: viewModel.updateDownloadLocation(.downloadsFolder)
        case .ask: viewModel.updateDownloadLocation(.askEachTime)
        case .chosenFolder: break
        case .other:
            // After the picker's own menu has closed, not inside SwiftUI's binding update.
            DispatchQueue.main.async { pickFolder() }
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        if case .folder(let folder) = viewModel.config.downloadLocation { panel.directoryURL = folder }
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.updateDownloadLocation(.folder(url))
        } else {
            // Cancelled: nothing changed, but the popup must stop showing 其他….
            viewModel.objectWillChange.send()
        }
    }

    private static func icon(for folder: URL) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: folder.path)
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}
