import MochiCore
import SwiftUI

/// The settings window's panes (#65), in toolbar order — the Safari-style preferences window
/// that `SettingsWindowController` builds, one toolbar button per case. Grouped by the user's
/// mental model rather than by implementation (#46): a new setting joins the pane it belongs to
/// rather than inventing a pane of its own. 窗口模式 (named 幽灵模式 until #146 made room for
/// Float Mode, ADR-0035) holds each mode's own settings, and 热键 (split off it by #153, once the
/// two no longer fit one screen's height) the keys (#88) — nearly every one only works outside
/// Normal Mode — while Snap lives in 通用. 网站 and 隐私与安全性 (#100) follow
/// Safari's 网站 and 隐私: per-website settings in one, what is kept about websites in the other.
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
    case general, windowModes, hotkeys, websites, privacy, scripts, advanced

    /// Fixed for every pane, like Safari's: only the height follows the content, so switching
    /// panes never makes the window jump sideways.
    static let width: CGFloat = 580
    /// Around every pane's content, so the content area is the pane plus this on each side.
    static let padding: CGFloat = 20

    var title: String {
        switch self {
        case .general: "通用"
        case .windowModes: "窗口模式"
        case .hotkeys: "热键"
        case .websites: "网站"
        case .privacy: "隐私与安全性"
        case .scripts: "脚本"
        case .advanced: "高级"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        // An SF Symbol rather than the hand-drawn ghost (ADR-0013); `eye.slash` would read as
        // Hidden, which is one thing inside a mode, not the modes themselves.
        case .windowModes: "rectangle.dashed"
        case .hotkeys: "keyboard"
        case .websites: "globe"
        case .privacy: "hand.raised"
        case .scripts: "curlybraces"
        case .advanced: "gearshape.2"
        }
    }

    /// The pane's content at its natural height and the shared fixed width. The list-driven
    /// panes (热键's mapping table, 网站's sidebar, scripts' editor) have no natural height of
    /// their own — a `List`/`TextEditor` takes whatever it is offered — so they get an explicit one.
    @ViewBuilder
    func content(viewModel: SettingsViewModel) -> some View {
        Group {
            switch self {
            case .general: GeneralSettingsTab(viewModel: viewModel)
            case .windowModes: WindowModesSettingsTab(viewModel: viewModel)
            case .hotkeys: HotkeysSettingsTab(viewModel: viewModel).frame(height: 760)
            // #109: tall enough for the 系统权限 hint, ~6 exception rows and the bottom row.
            case .websites: WebsitesSettingsTab(viewModel: viewModel).frame(height: 380)
            case .privacy: PrivacySettingsTab(viewModel: viewModel)
            case .scripts: ScriptsTab(viewModel: viewModel).frame(height: 560)
            case .advanced: AdvancedSettingsTab(viewModel: viewModel)
            }
        }
        .padding(Self.padding)
        .frame(width: Self.width)
    }
}

/// 高级 (#70, #72): 辅助功能 and 开发, each a self-contained `Section`. HTTP 警告 and 网站数据 live
/// in 隐私与安全性 (#100).
struct AdvancedSettingsTab: View {
    @ObservedObject var viewModel: SettingsViewModel

    /// The size the popup shows while the checkbox is off, so ticking it restores the last pick.
    @State private var chosenMinimumFontSize: Int

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

/// 窗口模式 (#146; 幽灵模式 before it): each mode's own group — Ghost Mode's look for now, with
/// Float Mode and Hidden joining as groups of their own (ADR-0035). The keys live in 热键 (#153).
struct WindowModesSettingsTab: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GhostModeSection(viewModel: viewModel)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 热键 (#153, split off 窗口模式): the keys — #45 + #14 + #79, laid out per #84 as three sections
/// (全局热键, 视频控制, 热键传递), each saying whether its keys are taken from other apps, and every
/// row its own one-line description. 恢复默认热键 sits in a footer below all of them and leaves the
/// modes' opacities alone. The Accessibility banner heads it, since only 视频控制 needs that.
struct HotkeysSettingsTab: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let prompt = viewModel.systemPermissionPrompts.first(where: { $0.placement == .hotkeysPanelTop }) {
                AccessibilityPromptBanner(action: prompt.action) { viewModel.perform(prompt) }

                Divider()
            }

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
        .onAppear { viewModel.refreshSystemPermissions() }
    }
}

/// 幽灵模式 (#88, headed 外观 until #146): Ghost Mode's target opacity, moved here from the old 窗口
/// pane and laid out like the hotkey rows. Written only when the drag ends — mid-drag values stay
/// in `@State`.
private struct GhostModeSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var opacity: Double

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        _opacity = State(initialValue: viewModel.config.ghostOpacity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("幽灵模式").font(.headline)
            HotkeyRow(title: "透明度") {
                HStack {
                    Slider(
                        value: $opacity, in: 0...1,
                        onEditingChanged: { editing in
                            if !editing { viewModel.updateGhostOpacity(opacity) }
                        }
                    ) {
                        Text("透明度")
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

/// 视频控制 (#79): the three video keys and the jump length. Whether Accessibility — without
/// which a combo with neither ⌃ nor ⌘ pressed in another app never reaches Mochi — is missing is
/// said at the top of the pane (#103, #111).
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
        }
    }
}

/// The top of the 热键 pane while Accessibility is missing and a 视频控制 key needs it
/// (#111, ADR-0029); nothing at all once it is granted. Its button is the camera's: 请求权限
/// while the system has never asked, 打开系统设置 once it has refused. Ad-hoc signing means an
/// update leaves System Settings' switch on but no longer honoured, and Mochi cannot tell that
/// apart from off — so the text itself says what to do about it.
private struct AccessibilityPromptBanner: View {
    let action: SystemPermissionPrompt.Action?
    let perform: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("需要辅助功能权限").font(.headline)
                Text("视频控制里不带 ⌃ 或 ⌘ 的组合键（如 ⌥P）要靠它在其他应用里听到按键。如果系统设置里已经打开，请先移除 Mochi 再重新添加（每次升级后都需要）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            switch action {
            case .request: Button("请求权限", action: perform)
            case .openSystemSettings: Button("打开系统设置", action: perform)
            case nil: EmptyView()
            }
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
/// (组合键 first, as every mapping used to be). Picking a kind starts recording, as in a 视频控制
/// row — but unlike there, it sticks: the add row is a draft, not a live binding, so there is
/// nothing to put back when the user leaves without a key. A trigger already recorded of another
/// kind no longer matches the dropdown and is dropped. Only a combo is taken from other apps, so
/// the section no longer says its keys are; a combo says so itself — a lock beside each
/// mapping's, a line under the add row while 组合键 is picked.
private struct HotkeyForwardingSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var newKind = TriggerKind.combo
    @State private var newTrigger: TriggerKey?
    @State private var newPageKeystroke: Hotkey?
    @State private var newTriggerRecordingRequest = 0

    private static let occupiedNote = "这个组合会被占用，其他应用里按不出来"
    private static let scrollerGutter = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "热键传递", caption: "幽灵模式下按触发键，向页面发送对应按键。")

            // A ScrollView, not a List: a List's row separators span the full width whatever the
            // row insets, so they ran under the scroller once enough mappings were added to
            // scroll. Here the rows and their separators stop a scroller's width short of the
            // edge, and the scroller overlays only that gutter.
            ScrollView {
                VStack(spacing: 0) {
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
                        .padding(.vertical, 3)
                        Divider()
                    }
                }
                .padding(.trailing, Self.scrollerGutter)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Picker(
                        "触发方式",
                        selection: Binding(
                            get: { newKind },
                            set: { kind in
                                if kind != newKind {
                                    newKind = kind
                                    newTrigger = nil
                                }
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
                        trigger: newTrigger, kind: newKind, accessibilityName: "触发键",
                        width: HotkeyRecorderField.mappingWidth,
                        recordingRequest: newTriggerRecordingRequest,
                        onRecordingStarted: viewModel.clearRowRejection,
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
                } else if newKind == .combo {
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
