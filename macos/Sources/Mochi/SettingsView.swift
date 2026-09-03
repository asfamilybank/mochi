import MochiCore
import SwiftUI

/// The settings panel's content (#13/#14/#15) — General (startup URL / Ghost Mode opacity),
/// hotkey mappings, and scripts, each backed by `SettingsViewModel` so every edit flows through
/// `SettingsController`'s persistence path rather than any view-local state of its own.
struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        TabView {
            GeneralSettingsTab(viewModel: viewModel)
                .tabItem { Text("通用") }
            HotkeyMappingsTab(viewModel: viewModel)
                .tabItem { Text("热键映射") }
            ScriptsTab(viewModel: viewModel)
                .tabItem { Text("脚本") }
        }
        .padding(20)
        .frame(width: 480, height: 420)
    }
}

/// #13: read-only "上次访问 URL" + the editable "启动 URL" tri-state selector (具体网址 / 空页面 /
/// 不设置) that replaces the originally-planned single URL text field (see issue #13's comment),
/// plus Ghost Mode's target opacity.
private struct GeneralSettingsTab: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var startupKind: StartupKind
    @State private var startupURLText: String
    @State private var ghostOpacity: Double

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
        _ghostOpacity = State(initialValue: viewModel.config.ghostOpacity)
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
                // `GhostModeController` captures its target opacity once at launch — persisted
                // immediately, but only takes visual effect the next time Mochi starts.
                Text("改动将在重启 Mochi 后生效")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

/// #14: add/edit/delete "global hotkey → page keystroke" mappings, reusing
/// `SettingsController`'s conflict detection when a new trigger is recorded.
private struct HotkeyMappingsTab: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var newTrigger: Hotkey?
    @State private var newPageKeystroke: Hotkey?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Mappings are only actually (un)registered with the OS when `HotkeyForwarder` is
            // rebuilt at launch (`Orchestrator.start()`) — an edit made here is fully persisted
            // immediately, but a removed mapping keeps forwarding for the rest of this session,
            // and an added/edited one does nothing until restart. Disclosed rather than silently
            // surprising the user, since there's no live unregister path (`GlobalHotkeyRegistry`
            // doesn't expose one) to make this take effect immediately without a larger change to
            // how hotkeys are (re)registered at runtime.
            Text("改动将在重启 Mochi 后生效")
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

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("新增映射").font(.headline)
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
        }
        .padding(.vertical, 8)
    }
}

/// #15: enable/disable built-in official adapter scripts, edit/save a custom script — each
/// clearly labeled by source, per the ticket's AC.
private struct ScriptsTab: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var customScriptText: String

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        _customScriptText = State(initialValue: viewModel.config.customScript ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Like the hotkey mapping table, `Orchestrator` only reads the enabled/disabled set
            // and the custom script once at launch — an edit here is persisted immediately but
            // doesn't reach the already-running page until Mochi restarts.
            Text("改动将在重启 Mochi 后生效")
                .font(.caption)
                .foregroundStyle(.secondary)

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
