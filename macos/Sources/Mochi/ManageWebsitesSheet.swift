import Combine
import MochiCore
import SwiftUI

/// 管理网站和数据… (#106): what the sheet shows and does. The grouping and search are
/// `ManagedWebsites`'s, the deleting `SettingsController`'s; this only holds the list, the query
/// and the selection, and re-fetches after every change — WebKit is the source of truth.
final class ManageWebsitesViewModel: ObservableObject {
    private let settings: SettingsViewModel
    @Published private(set) var websites: [ManagedWebsite] = []
    @Published private(set) var isLoading = true
    @Published var query = ""
    /// 显示只有缓存的网站 — off, so the list opens on the websites that hold logins and exceptions.
    @Published var showsCacheOnly = false
    @Published var selection: Set<ManagedWebsite.ID> = []

    init(settings: SettingsViewModel) {
        self.settings = settings
    }

    var visibleWebsites: [ManagedWebsite] {
        ManagedWebsites.filtered(websites, matching: query, includingCacheOnly: showsCacheOnly)
    }

    var cacheOnlyCount: Int { ManagedWebsites.cacheOnlyCount(websites) }

    /// Only what the search still shows: a hidden row can't be seen to be selected, so it isn't acted on.
    var selectedWebsites: [ManagedWebsite] { visibleWebsites.filter { selection.contains($0.id) } }

    var canRemoveData: Bool { selectedWebsites.contains(where: \.hasData) }
    var canResetPermissions: Bool { selectedWebsites.contains { !$0.exceptions.isEmpty } }

    func reload() {
        settings.fetchManagedWebsites { [weak self] websites in
            guard let self else { return }
            self.websites = websites
            selection.formIntersection(websites.map(\.id))
            isLoading = false
        }
    }

    func removeDataOfSelection() {
        settings.removeWebsiteData(of: selectedWebsites) { [weak self] in self?.reload() }
    }

    func resetPermissionsOfSelection() {
        settings.resetPagePermissions(of: selectedWebsites)
        reload()
    }

    func removeAll() {
        settings.removeDataOfAllWebsites { [weak self] in self?.reload() }
    }
}

/// The sheet itself, after Safari's 管理网站数据…: a searchable list, one row per website, with
/// what it stores and the 网页权限 exceptions of the hosts under it.
struct ManageWebsitesSheet: View {
    @StateObject private var model: ManageWebsitesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingRemoveAll = false

    init(settings: SettingsViewModel) {
        _model = StateObject(wrappedValue: ManageWebsitesViewModel(settings: settings))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("这些网站在 Mochi 中存储了数据，或设置了网页权限例外。删除数据会让你退出这些网站的登录；网页权限例外不受影响。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            searchField
            list
            Toggle("显示只有缓存的网站（\(model.cacheOnlyCount) 个）", isOn: $model.showsCacheOnly)
                .font(.callout)
                .disabled(model.cacheOnlyCount == 0)
            buttons
        }
        .padding(20)
        // #140: inside the settings window it hangs from, a padding's margin to spare.
        .frame(width: SettingsPane.width - SettingsPane.padding, height: 460)
        .onAppear { model.reload() }
        .alert("确定要删除所有网站的数据吗？", isPresented: $isConfirmingRemoveAll) {
            Button("全部删除", role: .destructive) { model.removeAll() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会让你退出所有网站的登录。网页权限例外不受影响。")
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索", text: $model.query)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
    }

    @ViewBuilder private var list: some View {
        let websites = model.visibleWebsites
        List(websites, selection: $model.selection) { website in
            ManagedWebsiteRow(website: website)
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
        .overlay {
            if model.isLoading {
                ProgressView().controlSize(.small)
            } else if websites.isEmpty {
                Text(
                    model.websites.isEmpty ? "没有网站存储数据或设置网页权限例外"
                        : model.query.trimmingCharacters(in: .whitespaces).isEmpty ? "其余网站只存储了缓存"
                        : "没有匹配的网站")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var buttons: some View {
        HStack {
            Button("删除数据") { model.removeDataOfSelection() }
                .disabled(!model.canRemoveData)
            Button("重置权限") { model.resetPermissionsOfSelection() }
                .disabled(!model.canResetPermissions)
            Button("全部删除…") { isConfirmingRemoveAll = true }
                .disabled(!model.websites.contains(where: \.hasData))
            Spacer()
            Button("完成") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }
}

private struct ManagedWebsiteRow: View {
    let website: ManagedWebsite

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(website.domain)
            if let kinds = website.dataKinds {
                Text(kinds.map(\.displayName).joined(separator: "、"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(website.exceptions, id: \.host) { exceptions in
                Text(Self.describe(exceptions, under: website.domain))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    /// `meet.google.com：摄像头 允许，麦克风 拒绝` — without the host when it is the row's own
    /// domain, which the line above already names.
    private static func describe(_ exceptions: WebsiteHostExceptions, under domain: String) -> String {
        let settings = [("摄像头", exceptions.camera), ("麦克风", exceptions.microphone)]
            .compactMap { name, setting in setting.map { "\(name) \($0.displayName)" } }
            .joined(separator: "，")
        return exceptions.host == domain ? settings : "\(exceptions.host)：\(settings)"
    }
}
