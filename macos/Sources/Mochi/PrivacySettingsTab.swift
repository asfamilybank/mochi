import MochiCore
import SwiftUI

/// 隐私与安全性 (#100): what is kept about websites and how they are reached, after Safari's 隐私
/// pane. Both sections moved here unchanged from 高级 (#72); later tickets append their own
/// (管理网站和数据…, 清除浏览数据…, history retention) as further rows or sections.
struct PrivacySettingsTab: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var isConfirmingDataRemoval = false

    var body: some View {
        Form {
            Section("网站数据") {
                Button("移除所有网站数据…") { isConfirmingDataRemoval = true }
                Text("清除 Cookie、缓存、本地存储与网站图标。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .alert("确定要移除所有网站数据吗？", isPresented: $isConfirmingDataRemoval) {
                Button("移除", role: .destructive) { viewModel.removeAllWebsiteData() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("这会让你退出所有网站的登录。")
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
