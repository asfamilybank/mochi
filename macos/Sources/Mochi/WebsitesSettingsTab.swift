import MochiCore
import SwiftUI

/// 网站 (#100, formerly 网页内容 #70), laid out like Safari's 网站 pane: a list of settings on the
/// left, the selected one's page on the right. 通用 holds the settings that stay global (自动播放,
/// 弹出式窗口); 摄像头 and 麦克风 each hold their 网页权限 (ADR-0027).
///
/// Not a `NavigationSplitView`: inside a settings pane it would try to put its sidebar button into
/// the window's toolbar, which is the pane switcher. A plain `List` beside the page has no natural
/// height, so `SettingsPane` gives this pane a fixed one.
struct WebsitesSettingsTab: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var selection = WebsitesSettingsSection.general

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            List(
                selection: Binding(
                    get: { Optional(selection) },
                    // Clicking the empty space below the rows would deselect; keep the page shown.
                    set: { if let section = $0 { selection = section } }
                )
            ) {
                ForEach(WebsitesSettingsSection.allCases, id: \.self) { section in
                    Label(section.title, systemImage: section.symbolName).tag(section)
                }
            }
            .listStyle(.bordered)
            .frame(width: 150)

            Group {
                switch selection {
                case .general: WebsitesGeneralPage(viewModel: viewModel)
                case .camera:
                    PagePermissionPage(
                        permission: Binding(
                            get: { viewModel.config.cameraPermission },
                            set: { viewModel.updateCameraPermission($0) }
                        ),
                        systemPermissionPrompt: viewModel.websitesPermissionPagePrompt(for: .camera),
                        perform: viewModel.perform)
                case .microphone:
                    PagePermissionPage(
                        permission: Binding(
                            get: { viewModel.config.microphonePermission },
                            set: { viewModel.updateMicrophonePermission($0) }
                        ),
                        systemPermissionPrompt: viewModel.websitesPermissionPagePrompt(for: .microphone),
                        perform: viewModel.perform)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // #104: System Settings may have changed the camera or microphone since last shown.
        .onAppear { viewModel.refreshSystemPermissions() }
    }
}

/// The rows of 网站's left-hand list, in order.
enum WebsitesSettingsSection: CaseIterable {
    case general, camera, microphone

    var title: String {
        switch self {
        case .general: "通用"
        case .camera: "摄像头"
        case .microphone: "麦克风"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .camera: "video"
        case .microphone: "mic"
        }
    }
}

/// 网站 → 通用: the settings that stay global (ADR-0027) — WebKit reads autoplay only when the web
/// view is created, and per-site pop-ups would mean nothing in a single-page Widget.
private struct WebsitesGeneralPage: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Picker(
                    "自动播放：",
                    selection: Binding(
                        get: { viewModel.config.autoplayPolicy },
                        set: { viewModel.updateAutoplayPolicy($0) }
                    )
                ) {
                    ForEach(WidgetConfig.AutoplayPolicy.allCases, id: \.self) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                // The one setting that is not live: WebKit reads it only when the web view is
                // created, so say so and offer the reopen that applies it.
                HStack {
                    Text("下次打开窗口时生效")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("重新打开窗口") { viewModel.reopenWidgetNow() }
                        .controlSize(.small)
                }
            }

            // #67: applies to the open widget immediately.
            Section {
                Picker(
                    "弹出式窗口：",
                    selection: Binding(
                        get: { viewModel.config.popupWindowPolicy },
                        set: { viewModel.updatePopupWindowPolicy($0) }
                    )
                ) {
                    Text("允许").tag(WidgetConfig.PopupWindowPolicy.allow)
                    Text("阻止").tag(WidgetConfig.PopupWindowPolicy.block)
                }
                .pickerStyle(.menu)
                .fixedSize()
                Text("阻止网页未经点击自行打开的窗口。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.columns)
    }
}

/// 网站 → 摄像头 / 麦克风 (#69): one 网页权限. Its global value is the default for every website
/// (ADR-0027), hence Safari's label. Live: read at each request; Ghost Mode denies regardless.
///
/// The 系统权限 hint (#95) goes above, and the per-website exceptions table between that and the
/// default — which stays at the bottom, as in Safari.
private struct PagePermissionPage: View {
    @Binding var permission: WidgetConfig.MediaCapturePermission
    /// #104: shown above everything else while the system keeps pages from this device.
    var systemPermissionPrompt: SystemPermissionPrompt?
    var perform: (SystemPermissionPrompt) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let systemPermissionPrompt {
                SystemPermissionHint(prompt: systemPermissionPrompt, perform: perform)
            }
            form
        }
    }

    private var form: some View {
        Form {
            Section {
                Picker("访问其他网站时：", selection: $permission) {
                    ForEach(WidgetConfig.MediaCapturePermission.allCases, id: \.self) { permission in
                        Text(permission.displayName).tag(permission)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
        .formStyle(.columns)
    }
}

/// The 系统权限 hint at the top of 网站 → 摄像头 / 麦克风 (#104, ADR-0026): the 网页权限 lets pages
/// ask, but the system has not given Mochi the device, so they would get nothing.
private struct SystemPermissionHint: View {
    let prompt: SystemPermissionPrompt
    let perform: (SystemPermissionPrompt) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            switch prompt.action {
            case .request: Button("请求权限") { perform(prompt) }.controlSize(.small)
            case .openSystemSettings: Button("打开系统设置") { perform(prompt) }.controlSize(.small)
            case nil: EmptyView()
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var message: String {
        let device = prompt.permission == .camera ? "摄像头" : "麦克风"
        return switch prompt.action {
        case .request: "Mochi 还没有获得\(device)权限，网页暂时无法使用\(device)。"
        case .openSystemSettings: "Mochi 的\(device)权限已被拒绝，网页无法使用\(device)。"
        case nil: "\(device)权限受管理策略限制，网页无法使用\(device)。"
        }
    }
}

extension WidgetConfig.AutoplayPolicy {
    fileprivate var displayName: String {
        switch self {
        case .allowAll: "允许全部自动播放"
        case .stopMediaWithSound: "停止有声媒体"
        case .never: "永不自动播放"
        }
    }
}

// #69 — Safari's wording.
extension WidgetConfig.MediaCapturePermission {
    fileprivate var displayName: String {
        switch self {
        case .ask: "询问"
        case .deny: "拒绝"
        case .allow: "允许"
        }
    }
}
