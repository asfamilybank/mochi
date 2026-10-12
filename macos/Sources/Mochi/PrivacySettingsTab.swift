import MochiCore
import SwiftUI

/// 隐私与安全性 (#100): what is kept about websites and how they are reached, after Safari's 隐私
/// pane. Both sections moved here unchanged from 高级 (#72); later tickets append their own
/// (管理网站和数据…, 清除浏览数据…, history retention) as further rows or sections.
struct PrivacySettingsTab: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var isManagingWebsites = false

    var body: some View {
        Form {
            // #110: Safari's wording. Shortening it removes the expired pages at once.
            Section("历史记录") {
                Picker(
                    "移除历史记录项目：",
                    selection: Binding(
                        get: { viewModel.config.historyRetention },
                        set: { viewModel.updateHistoryRetention($0) }
                    )
                ) {
                    ForEach(HistoryRetention.allCases, id: \.self) { retention in
                        Text(retention.displayName).tag(retention)
                    }
                }
                .fixedSize()
            }

            Section("网站数据") {
                // #106: replaces 移除所有网站数据…, whose job is the sheet's 全部删除.
                Button("管理网站和数据…") { isManagingWebsites = true }
                Text("按网站查看并删除 Cookie、缓存等数据，或重置网页权限。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // #107; the 历史记录 menu opens it too (#110), hence the view model's flag.
                Button("清除浏览数据…") { viewModel.isClearingBrowsingData = true }
                    .sheet(isPresented: $viewModel.isClearingBrowsingData) {
                        ClearBrowsingDataSheet { kinds, range in viewModel.clearBrowsingData(kinds, from: range) }
                    }
            }
            .sheet(isPresented: $isManagingWebsites) {
                ManageWebsitesSheet(settings: viewModel)
            }

            Section("安全性") {
                Toggle(
                    "通过 HTTP 连接网站前接收警告",
                    isOn: Binding(
                        get: { viewModel.config.isHTTPWarningEnabled },
                        set: { viewModel.updateHTTPWarningEnabled($0) }
                    )
                )
            }
        }
        .formStyle(.columns)
    }
}
