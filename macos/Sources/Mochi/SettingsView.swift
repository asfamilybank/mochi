import MochiCore
import SwiftUI

/// The settings panel's content, regrouped into four tabs by the user's mental model rather than
/// by implementation (#46): 通用 (startup) / 窗口与外观 (how the window behaves on the desktop) /
/// 热键 (both kinds of hotkey in one place) / 脚本. Every tab is backed by `SettingsViewModel` so
/// each edit flows through `SettingsController`'s persistence path — view-local `@State` only ever
/// holds a value mid-edit (text being typed, a slider mid-drag), never the truth.
///
/// Nothing here says "改动将在重启 Mochi 后生效" any more: every setting either is re-read at its
/// point of use or is actively re-applied on change (#46). Scripts are the one honest exception —
/// already-executed JavaScript can't be undone — so that tab says "next page load" and offers the
/// load as a button.
struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        TabView {
            GeneralSettingsTab(viewModel: viewModel)
                .tabItem { Text("通用") }
            WindowAppearanceTab(viewModel: viewModel)
                .tabItem { Text("窗口与外观") }
            HotkeysTab(viewModel: viewModel)
                .tabItem { Text("热键") }
            ScriptsTab(viewModel: viewModel)
                .tabItem { Text("脚本") }
        }
        .padding(20)
        .frame(width: 480, height: 460)
    }
}

/// #13: read-only "上次访问 URL" + the editable "启动 URL" tri-state selector (具体网址 / 空页面 /
/// 不设置) that replaces the originally-planned single URL text field (see issue #13's comment).
/// Moved here verbatim from the old three-tab layout — behaviour unchanged (#46).
private struct GeneralSettingsTab: View {
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
            Section("上次访问 URL") {
                Text(viewModel.config.url?.absoluteString ?? "尚无浏览记录")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section("启动 URL") {
                Picker("启动时", selection: $startupKind) {
                    Text("继续上次访问页面").tag(StartupKind.notSet)
                    Text("使用空页面").tag(StartupKind.emptyPage)
                    Text("指定网址").tag(StartupKind.url)
                }
                .pickerStyle(.radioGroup)
                .onChange(of: startupKind) { _, newValue in applyStartupTarget(kind: newValue) }

                if startupKind == .url {
                    TextField("https://example.com", text: $startupURLText)
                        .onSubmit { applyStartupTarget(kind: .url) }
                }
            }
        }
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

/// #46: everything about how the window behaves on the desktop — Ghost Mode's target opacity,
/// mouse-entered avoidance (ADR-0012), and Snap (#39). The two switches get their first UI here;
/// before this they were only reachable by hand-editing the config file.
private struct WindowAppearanceTab: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var ghostOpacity: Double

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        _ghostOpacity = State(initialValue: viewModel.config.ghostOpacity)
    }

    var body: some View {
        Form {
            Section("Ghost Mode") {
                HStack {
                    Slider(
                        value: $ghostOpacity, in: 0...1,
                        onEditingChanged: { editing in
                            if !editing { viewModel.updateGhostOpacity(ghostOpacity) }
                        }
                    ) {
                        Text("目标透明度")
                    }
                    Text(String(format: "%.0f%%", ghostOpacity * 100))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                Toggle(
                    "鼠标移入时避让",
                    isOn: Binding(
                        get: { viewModel.config.isMouseAvoidanceEnabled },
                        set: { viewModel.updateMouseAvoidanceEnabled($0) }
                    )
                )
                Text("鼠标移到 Widget 上时窗口暂时让开，移开即恢复。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Normal Mode") {
                Toggle(
                    "拖动时吸附屏幕边缘",
                    isOn: Binding(
                        get: { viewModel.config.isSnapEnabled },
                        set: { viewModel.updateSnapEnabled($0) }
                    )
                )
            }
        }
    }
}

/// #45 + #14, together in one place since the user thinks of both as "hotkeys" (#46): the two
/// customizable action hotkeys on top, the forwarding mapping table below. Both sections reuse
/// the same recorder control and display formatting.
private struct HotkeysTab: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var newTrigger: Hotkey?
    @State private var newPageKeystroke: Hotkey?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("功能热键").font(.headline)
            ForEach(HotkeyAction.allCases, id: \.self) { action in
                HStack {
                    Text(action.displayName)
                    Spacer()
                    // The binding reads the combo currently in effect straight from the config, so
                    // a rejected recording (conflict, or held by another app) snaps the control
                    // back to the unchanged binding instead of displaying a combo that isn't live.
                    HotkeyRecorderView(
                        hotkey: Binding(
                            get: { viewModel.config.hotkey(for: action) },
                            set: { newValue in
                                guard let newValue else { return }
                                viewModel.updateActionHotkey(action, to: newValue)
                            }
                        ),
                        placeholder: "点击录制"
                    )
                }
            }
            HStack {
                Text("全局生效，按下即刻切换；刷新与缩放使用固定的 ⌘R / ⌘+ / ⌘- / ⌘0，不可自定义。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("恢复默认") {
                    viewModel.resetActionHotkeysToDefaults()
                }
                .disabled(viewModel.config.hotkeyOverrides.isEmpty)
            }

            Divider()

            Text("热键映射").font(.headline)
            Text("Ghost Mode 下按触发热键，向页面转发对应按键。")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach(Array(viewModel.config.hotkeyMappings.enumerated()), id: \.offset) { index, mapping in
                    HStack {
                        Text(HotkeyDisplay.describe(mapping.trigger))
                        Image(systemName: "arrow.right")
                        Text(HotkeyDisplay.describe(mapping.pageKeystroke))
                        Spacer()
                        Button {
                            viewModel.removeHotkeyMapping(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            HStack {
                HotkeyRecorderView(hotkey: $newTrigger, placeholder: "触发热键")
                Image(systemName: "arrow.right")
                HotkeyRecorderView(hotkey: $newPageKeystroke, placeholder: "页面按键")
                Button("添加") {
                    guard let trigger = newTrigger, let pageKeystroke = newPageKeystroke else { return }
                    if viewModel.addHotkeyMapping(trigger: trigger, pageKeystroke: pageKeystroke) {
                        newTrigger = nil
                        newPageKeystroke = nil
                    }
                }
                .disabled(newTrigger == nil || newPageKeystroke == nil)
            }
        }
        .padding(.vertical, 8)
    }
}

/// #15: enable/disable built-in official adapter scripts, edit/save a custom script — each
/// clearly labeled by source, per the ticket's AC. Since #46 the enabled set and the custom script
/// are re-read on every navigation, so a change applies on the next page load — stated as such,
/// with the load itself one click away.
private struct ScriptsTab: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var customScriptText: String

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        _customScriptText = State(initialValue: viewModel.config.customScript ?? "")
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
        }
        .padding(.vertical, 8)
    }
}
