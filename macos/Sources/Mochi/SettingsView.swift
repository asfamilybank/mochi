import MochiCore
import SwiftUI

/// The settings window's panes (#65), in toolbar order — the Safari-style preferences window
/// that `SettingsWindowController` builds, one toolbar button per case. Regrouped by the user's
/// mental model rather than by implementation (#46), then widened from four tabs to six so the
/// settings #64 adds each have a home: 网页内容 and 高级 start out empty and are filled by later
/// tickets, which add items to a pane rather than inventing panes of their own. #88 folded 热键
/// and 窗口 into 幽灵模式: nearly every hotkey only works in Ghost Mode, and its opacity sat a pane
/// away from them; 窗口's one remaining switch, Snap, moved to 通用.
///
/// Every pane is backed by `SettingsViewModel` so each edit flows through `SettingsController`'s
/// persistence path — view-local `@State` only ever holds a value mid-edit (text being typed, a
/// slider mid-drag), never the truth.
///
/// Nothing here says "改动将在重启 Mochi 后生效": every setting either is re-read at its point of
/// use or is actively re-applied on change (#46). Scripts are the one honest exception —
/// already-executed JavaScript can't be undone — so that pane says "next page load" and offers the
/// load as a button.
enum SettingsPane: CaseIterable {
    case general, ghostMode, webContent, scripts, advanced

    /// Fixed for every pane, like Safari's: only the height follows the content, so switching
    /// panes never makes the window jump sideways.
    static let width: CGFloat = 540

    var title: String {
        switch self {
        case .general: "通用"
        case .ghostMode: "幽灵模式"
        case .webContent: "网页内容"
        case .scripts: "脚本"
        case .advanced: "高级"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        // An SF Symbol rather than the hand-drawn ghost (ADR-0013); `eye.slash` would read as
        // Hidden, which is one thing inside Ghost Mode, not the mode itself.
        case .ghostMode: "rectangle.dashed"
        case .webContent: "globe"
        case .scripts: "curlybraces"
        case .advanced: "gearshape.2"
        }
    }

    /// The pane's content at its natural height and the shared fixed width. The two list-driven
    /// panes (幽灵模式's mapping table, scripts' editor) have no natural height of their own — a
    /// `List`/`TextEditor` takes whatever it is offered — so they get an explicit one.
    @ViewBuilder
    func content(viewModel: SettingsViewModel) -> some View {
        Group {
            switch self {
            case .general: GeneralSettingsTab(viewModel: viewModel)
            case .ghostMode: GhostModeSettingsTab(viewModel: viewModel).frame(height: 790)
            case .webContent: WebContentSettingsTab(viewModel: viewModel)
            case .scripts: ScriptsTab(viewModel: viewModel).frame(height: 560)
            case .advanced: AdvancedSettingsTab(viewModel: viewModel)
            }
        }
        .padding(20)
        .frame(width: Self.width)
    }
}

/// 网页内容 (#70). A `Form` of `Section`s so later #64 tickets can append their own sections.
struct WebContentSettingsTab: View {
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
            // #69 — live: read at each request. Ghost Mode denies regardless.
            Section {
                Picker(
                    "摄像头：",
                    selection: Binding(
                        get: { viewModel.config.cameraPermission },
                        set: { viewModel.updateCameraPermission($0) }
                    )
                ) {
                    ForEach(WidgetConfig.MediaCapturePermission.allCases, id: \.self) { permission in
                        Text(permission.displayName).tag(permission)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                Picker(
                    "麦克风：",
                    selection: Binding(
                        get: { viewModel.config.microphonePermission },
                        set: { viewModel.updateMicrophonePermission($0) }
                    )
                ) {
                    ForEach(WidgetConfig.MediaCapturePermission.allCases, id: \.self) { permission in
                        Text(permission.displayName).tag(permission)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
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

/// 高级 (#70, #72). Same `Form`/`Section` skeleton as 网页内容; each `Section` is self-contained so
/// later tickets can append their own.
struct AdvancedSettingsTab: View {
    @ObservedObject var viewModel: SettingsViewModel

    /// The size the popup shows while the checkbox is off, so ticking it restores the last pick.
    @State private var chosenMinimumFontSize: Int
    @State private var isConfirmingDataRemoval = false

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        _chosenMinimumFontSize = State(initialValue: viewModel.config.minimumFontSize ?? 9)
    }

    var body: some View {
        Form {
            Section("辅助功能") {
                HStack {
                    Toggle(
                        "字体大小不得小于",
                        isOn: Binding(
                            get: { viewModel.config.minimumFontSize != nil },
                            set: { viewModel.updateMinimumFontSize($0 ? chosenMinimumFontSize : nil) }
                        )
                    )
                    Picker(
                        "字体大小不得小于",
                        selection: Binding(
                            get: { chosenMinimumFontSize },
                            set: { size in
                                chosenMinimumFontSize = size
                                if viewModel.config.minimumFontSize != nil { viewModel.updateMinimumFontSize(size) }
                            }
                        )
                    ) {
                        ForEach(WidgetConfig.offeredMinimumFontSizes, id: \.self) { size in
                            Text("\(size)").tag(size)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .disabled(viewModel.config.minimumFontSize == nil)
                }
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

            Section("开发") {
                Toggle(
                    "显示网页开发者功能",
                    isOn: Binding(
                        get: { viewModel.config.isWebInspectorEnabled },
                        set: { viewModel.updateWebInspectorEnabled($0) }
                    )
                )
            }
        }
        .formStyle(.columns)
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

/// #13's editable "启动 URL" tri-state selector (具体网址 / 空页面 / 不设置), which replaces the
/// originally-planned single URL text field (see issue #13's comment).
///
/// It used to sit under a read-only "上次访问 URL" row echoing `config.url`. That row is gone: the
/// address bar already shows where you are, and a settings panel is a poor place to leave the last
/// site you visited sitting in plain text. `config.url` itself is untouched — it is what
/// "继续上次访问页面" resolves to, it just isn't displayed any more.
struct GeneralSettingsTab: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var startupKind: StartupKind
    @State private var startupURLText: String

    private enum StartupKind: Hashable {
        case notSet, emptyPage, url
    }

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        switch viewModel.config.startupTarget {
        case .url(let url):
            _startupKind = State(initialValue: .url)
            _startupURLText = State(initialValue: url.absoluteString)
        case .emptyPage:
            _startupKind = State(initialValue: .emptyPage)
            _startupURLText = State(initialValue: "")
        case nil:
            _startupKind = State(initialValue: .notSet)
            _startupURLText = State(initialValue: "")
        }
    }

    var body: some View {
        Form {
            Section("启动 URL") {
                Picker("启动时", selection: $startupKind) {
                    Text("继续上次访问页面").tag(StartupKind.notSet)
                    Text("使用空页面").tag(StartupKind.emptyPage)
                    Text("指定网址").tag(StartupKind.url)
                }
                .pickerStyle(.radioGroup)
                .onChange(of: startupKind) { _, newValue in applyStartupTarget(kind: newValue) }

                // Always shown, greyed out unless 指定网址 is chosen — the pane's height stays put
                // when switching options, and what was typed survives a detour through the other
                // two (switching never touches `startupURLText`), so coming back restores it.
                // Placeholder kept generic rather than a sample domain — an example URL in a
                // field that already means "type a URL here" only adds a site nobody asked about.
                // Not the address bar's "搜索或输入网址": this field only takes a URL.
                // The label sits in `LabeledContent` so the width below sizes the box alone — on a
                // labelled `TextField` in a `.columns` form, `.frame` would include the label column.
                LabeledContent("输入网址") {
                    TextField("输入网址", text: $startupURLText, prompt: Text("输入网址"))
                        .labelsHidden()
                        .onSubmit { applyStartupTarget(kind: .url) }
                        .disabled(startupKind != .url)
                        .frame(width: 166)
                }
            }

            Section("搜索") {
                Picker(
                    "搜索引擎",
                    selection: Binding(
                        get: { viewModel.config.searchEngine },
                        set: { viewModel.updateSearchEngine($0) }
                    )
                ) {
                    ForEach(SearchEngine.allCases, id: \.self) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
            }

            DownloadLocationSection(viewModel: viewModel)

            // Snap's home since #88 removed the 窗口 pane: it is the one window setting left that
            // isn't about Ghost Mode.
            Section("窗口") {
                Toggle(
                    "拖动时吸附屏幕边缘",
                    isOn: Binding(
                        get: { viewModel.config.isSnapEnabled },
                        set: { viewModel.updateSnapEnabled($0) }
                    )
                )
            }
        }
        .formStyle(.columns)
    }

    private func applyStartupTarget(kind: StartupKind) {
        switch kind {
        case .notSet:
            viewModel.updateStartupTarget(nil)
        case .emptyPage:
            viewModel.updateStartupTarget(.emptyPage)
        case .url:
            guard let url = URL(string: startupURLText), url.scheme != nil else { return }
            viewModel.updateStartupTarget(.url(url))
        }
    }
}

/// Everything about Ghost Mode in one pane (#88): its look, then the keys — #45 + #14 + #79,
/// laid out per #84 as three sections (全局热键, 视频控制, 热键传递), each saying whether its keys
/// are taken from other apps, and every row its own one-line description. 恢复默认热键 sits in a
/// footer below all of them and leaves the opacity alone.
struct GhostModeSettingsTab: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GhostAppearanceSection(viewModel: viewModel)

            Divider()

            SectionHeader(title: "全局热键", caption: "在任何应用里按下都会生效，并会占用这个组合。")
            ForEach(HotkeyAction.allCases, id: \.self) { action in
                HotkeyRow(
                    title: action.displayName, description: action.settingsDescription,
                    rejection: viewModel.rejectionMessage(for: .action(action))
                ) {
                    // The field shows the combo currently in effect, read straight from the config, so
                    // a rejected recording (conflict, or held by another app) snaps the control
                    // back to the unchanged binding instead of displaying a combo that isn't live.
                    HotkeyRecorderView(
                        hotkey: viewModel.config.hotkey(for: action),
                        accessibilityName: action.displayName,
                        onRecordingStarted: viewModel.clearRowRejection,
                        onHint: { viewModel.showHint($0, on: .action(action)) },
                        onCapture: { viewModel.updateActionHotkey(action, to: $0) },
                        onClear: { viewModel.updateActionHotkey(action, to: nil) }
                    )
                }
            }

            Divider()

            VideoControlSection(viewModel: viewModel)

            Divider()

            HotkeyForwardingSection(viewModel: viewModel)

            Divider()

            HStack {
                Spacer()
                Button("恢复默认热键") {
                    viewModel.resetHotkeysToDefaults()
                }
                .disabled(
                    viewModel.config.hotkeyOverrides.isEmpty && viewModel.config.videoControlOverrides.isEmpty
                        && viewModel.config.videoSeekStep == WidgetConfig.defaultVideoSeekStep)
            }
        }
        .padding(.vertical, 8)
    }
}

/// 外观 (#88): Ghost Mode's target opacity, moved here from the old 窗口 pane and laid out like
/// the hotkey rows below it. Written only when the drag ends — mid-drag values stay in `@State`.
private struct GhostAppearanceSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var opacity: Double

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        _opacity = State(initialValue: viewModel.config.ghostOpacity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("外观").font(.headline)
            HotkeyRow(title: "目标透明度") {
                HStack {
                    Slider(
                        value: $opacity, in: 0...1,
                        onEditingChanged: { editing in
                            if !editing { viewModel.updateGhostOpacity(opacity) }
                        }
                    ) {
                        Text("目标透明度")
                    }
                    .labelsHidden()
                    .frame(width: 180)
                    Text(String(format: "%.0f%%", opacity * 100))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
    }
}

/// A section's headline plus the one line saying what all its keys share — chiefly whether they
/// are taken from every other app (#84).
private struct SectionHeader: View {
    var title: String
    var caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// One hotkey: its name with a one-line description underneath on the left, the recorder on the
/// right (#84). A refused recording's reason takes the description's place, in red (#86).
private struct HotkeyRow<Control: View>: View {
    var title: String
    var description: String?
    var rejection: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let rejection {
                    Text(rejection)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            control
        }
    }
}

private extension HotkeyAction {
    var settingsDescription: String {
        switch self {
        case .toggleGhostMode: "隐藏窗口装饰、置顶并让鼠标穿透；再按一次退出。"
        case .hideWidget: "幽灵模式下让窗口完全看不见，页面继续运行，视频会暂停。"
        }
    }
}

private extension VideoControlAction {
    var settingsDescription: String {
        switch self {
        case .togglePlayback: "作用于正在播放或最近播放过的视频。"
        case .seekBackward, .seekForward: "按下面设定的步长跳转。"
        }
    }
}

/// 视频控制 (#79): the three video keys, the jump length, and whether Accessibility — without
/// which keys pressed in other apps never reach Mochi — has been granted.
private struct VideoControlSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "视频控制", caption: "幽灵模式下生效。按键照常传给当前应用，不会被占用。")
            ForEach(VideoControlAction.allCases, id: \.self) { action in
                VideoControlRow(viewModel: viewModel, action: action)
            }
            HotkeyRow(title: "后退/前进步长") {
                Stepper(
                    "\(viewModel.config.videoSeekStep) 秒",
                    value: Binding(
                        get: { viewModel.config.videoSeekStep },
                        set: { viewModel.updateVideoSeekStep($0) }
                    ),
                    in: WidgetConfig.videoSeekStepRange
                )
            }
            HStack {
                if viewModel.isAccessibilityTrusted {
                    Label("已获得辅助功能权限", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Label("需要辅助功能权限，才能在其他应用里响应这些按键", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("打开系统设置") {
                        viewModel.openAccessibilitySettings()
                    }
                }
            }
            .font(.caption)
        }
        .onAppear { viewModel.refreshAccessibilityStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refreshAccessibilityStatus()
        }
    }
}

/// One 视频控制 key (#90): a dropdown for how it is pressed, then the recorder. The dropdown shows
/// the kind of the binding in effect — 轻按 for an unbound row —
/// and picking another starts recording that kind straight away. Until a key is captured the
/// old binding stays live, and leaving without one (Esc, a click elsewhere) puts the dropdown
/// back: picking a kind is not an edit, recording a key is.
private struct VideoControlRow: View {
    @ObservedObject var viewModel: SettingsViewModel
    let action: VideoControlAction
    /// The kind being tried out while recording; `nil` otherwise.
    @State private var pendingKind: TriggerKind?
    @State private var recordingRequest = 0

    private var boundKind: TriggerKind { viewModel.config.videoControlTrigger(for: action)?.kind ?? .tap }

    var body: some View {
        HotkeyRow(
            title: action.displayName, description: action.settingsDescription,
            rejection: viewModel.rejectionMessage(for: .videoControl(action))
        ) {
            HStack(spacing: 8) {
                Picker(
                    "\(action.displayName)的触发方式",
                    selection: Binding(
                        get: { pendingKind ?? boundKind },
                        set: { kind in
                            pendingKind = kind
                            recordingRequest += 1
                        }
                    )
                ) {
                    ForEach(TriggerKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .labelsHidden()
                .fixedSize()
                // Shows the binding in effect straight from the config, like the action
                // hotkeys above, so a refused recording snaps back to what is live.
                TriggerKeyRecorderView(
                    trigger: viewModel.config.videoControlTrigger(for: action),
                    kind: pendingKind ?? boundKind,
                    accessibilityName: action.displayName,
                    recordingRequest: recordingRequest,
                    onRecordingStarted: viewModel.clearRowRejection,
                    onRecordingStopped: { pendingKind = nil },
                    onHint: { viewModel.showHint($0, on: .videoControl(action)) },
                    onCapture: { viewModel.updateVideoControlTrigger($0, for: action) },
                    onClear: { viewModel.updateVideoControlTrigger(nil, for: action) }
                )
            }
        }
    }
}

/// 热键传递 (#14): each 映射 read-only — re-recording one in place would mean re-registering
/// its trigger but not its page key, so a change is delete-and-add — with the add row below.
///
/// Since #92 a trigger is a tap, a double tap or a combo, picked in the add row's dropdown
/// (组合键 first, as every mapping used to be). Like a 视频控制 row's, picking a kind only tries
/// it out: it starts recording, and leaving without a key puts the dropdown back and keeps any
/// trigger already recorded. Only a combo is taken from other apps, so the section no longer
/// says its keys are; a combo says so itself — a lock beside each mapping's, a line under the add
/// row while 组合键 is picked.
private struct HotkeyForwardingSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var newKind = TriggerKind.combo
    /// The kind being tried out while recording; `nil` otherwise.
    @State private var pendingKind: TriggerKind?
    @State private var newTrigger: TriggerKey?
    @State private var newPageKeystroke: Hotkey?
    @State private var newTriggerRecordingRequest = 0

    private static let occupiedNote = "这个组合会被占用，其他应用里按不出来"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "热键传递", caption: "幽灵模式下按触发键，向页面发送对应按键。")

            List {
                ForEach(Array(viewModel.config.hotkeyMappings.enumerated()), id: \.offset) { index, mapping in
                    HStack {
                        TriggerKeyRecorderView(
                            trigger: mapping.trigger, kind: mapping.trigger.kind, accessibilityName: "触发键",
                            isRecordable: false, width: HotkeyRecorderField.mappingWidth)
                        // Always takes its width, so every row's arrow lines up.
                        Image(systemName: "lock")
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                            .opacity(mapping.trigger.kind == .combo ? 1 : 0)
                            .help(Self.occupiedNote)
                            .accessibilityLabel(Self.occupiedNote)
                            .accessibilityHidden(mapping.trigger.kind != .combo)
                        Image(systemName: "arrow.right")
                        HotkeyRecorderView(hotkey: mapping.pageKeystroke, accessibilityName: "页面按键", isRecordable: false,
                            width: HotkeyRecorderField.mappingWidth)
                        Spacer()
                        Button {
                            viewModel.removeHotkeyMapping(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("删除映射")
                        .accessibilityLabel("删除映射")
                    }
                    .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Picker(
                        "触发方式",
                        selection: Binding(
                            get: { pendingKind ?? newKind },
                            set: { kind in
                                pendingKind = kind
                                newTriggerRecordingRequest += 1
                            }
                        )
                    ) {
                        ForEach(TriggerKind.allCases, id: \.self) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    TriggerKeyRecorderView(
                        trigger: newTrigger, kind: pendingKind ?? newKind, accessibilityName: "触发键",
                        width: HotkeyRecorderField.mappingWidth,
                        recordingRequest: newTriggerRecordingRequest,
                        onRecordingStarted: viewModel.clearRowRejection,
                        onRecordingStopped: { pendingKind = nil },
                        onHint: { viewModel.showHint($0, on: .newMapping) },
                        onCapture: { trigger in
                            newTrigger = trigger
                            newKind = trigger.kind
                        },
                        onClear: { newTrigger = nil })
                    Image(systemName: "arrow.right")
                    HotkeyRecorderView(
                        hotkey: newPageKeystroke, accessibilityName: "页面按键", width: HotkeyRecorderField.mappingWidth,
                        target: .pageKeystroke,
                        onRecordingStarted: viewModel.clearRowRejection,
                        onCapture: { newPageKeystroke = $0 }, onClear: { newPageKeystroke = nil })
                    Spacer()
                    Button("添加映射") {
                        guard let trigger = newTrigger, let pageKeystroke = newPageKeystroke else { return }
                        if viewModel.addHotkeyMapping(trigger: trigger, pageKeystroke: pageKeystroke) {
                            newTrigger = nil
                            newPageKeystroke = nil
                        }
                    }
                    .disabled(newTrigger == nil || newPageKeystroke == nil)
                }
                if let rejection = viewModel.rejectionMessage(for: .newMapping) {
                    Text(rejection)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if (pendingKind ?? newKind) == .combo {
                    Text(Self.occupiedNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// #15: enable/disable built-in official adapter scripts, edit/save a custom script — each
/// clearly labeled by source, per the ticket's AC. Since #46 the enabled set and the custom script
/// are re-read on every navigation, so a change applies on the next page load — stated as such,
/// with the load itself one click away.
struct ScriptsTab: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var customScriptText: String
    @State private var customStylesheetText: String

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        _customScriptText = State(initialValue: viewModel.config.customScript ?? "")
        _customStylesheetText = State(initialValue: viewModel.config.customStylesheet ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Honest about the one limit hot-reload can't cross: JavaScript that already ran
                // in the page can't be un-run. Both directions — enabling and disabling — wait
                // for the next load, deliberately symmetric so the rule is learnable.
                Text("脚本改动将在下次加载页面后生效")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("刷新页面") {
                    viewModel.reloadPageNow()
                }
            }

            Text("官方内置适配脚本").font(.headline)
            ForEach(BuiltInScripts.all, id: \.id) { script in
                Toggle(
                    isOn: Binding(
                        get: { !viewModel.config.disabledBuiltInScriptIDs.contains(script.id) },
                        set: { viewModel.setBuiltInScript(script.id, enabled: $0) }
                    )
                ) {
                    HStack {
                        Text(script.displayName)
                        Text("官方内置")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            HStack {
                Text("自定义脚本").font(.headline)
                Text("用户自定义 · 使用风险自负")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextEditor(text: $customScriptText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
            Button("保存") {
                viewModel.updateCustomScript(customScriptText.isEmpty ? nil : customScriptText)
            }

            // #73: third Script Injection source — same next-load rule as the script above.
            HStack {
                Text("自定义样式表").font(.headline)
                Text("用户自定义 · CSS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextEditor(text: $customStylesheetText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
            Button("保存样式表") {
                viewModel.updateCustomStylesheet(customStylesheetText.isEmpty ? nil : customStylesheetText)
            }
        }
        .padding(.vertical, 8)
    }
}
