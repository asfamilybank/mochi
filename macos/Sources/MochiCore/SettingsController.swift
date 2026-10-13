import Foundation

/// Drives every edit made in the settings panel (#13/#14/#15/#45/#46) — startup URL, Ghost Mode
/// opacity/Snap, the two action hotkeys, hotkey mapping CRUD, and custom/built-in script
/// management — exactly the way `Orchestrator` drives window/hotkey state: talking only to
/// `PlatformOps` plus an injected read/write pair, so it's exercisable against `FakePlatformOps`
/// without any AppKit/SwiftUI in the loop.
///
/// `currentConfig`/`persist` are a transform-based read-modify-write pair, not a cached copy of
/// the config handed in at init — mirroring `AppDelegate`'s own `persist(_:)` helper exactly, so a
/// settings edit is guaranteed to apply on top of whatever `Orchestrator` most recently persisted
/// (a window-state save, a URL navigation), never overwrite it with a stale snapshot taken
/// whenever the settings panel happened to open.
///
/// Every edit takes effect immediately (#45/#46): most settings are simply re-read by their
/// consumers at the point of use, so persisting *is* applying; the few that must be actively
/// pushed (Snap, an opacity edit made while in Ghost Mode) are covered by `configDidChange`, which
/// fires after every persisted edit and which the app wires to `Orchestrator.reapplyConfiguration`.
/// Hotkeys are the one kind of edit with an OS-level side effect, handled here directly as an
/// "unregister old → register new, roll back on failure" transaction before anything is persisted.
public final class SettingsController {
    private let platformOps: PlatformOps
    private let currentConfig: () -> WidgetConfig
    private let persist: (@escaping (WidgetConfig) -> WidgetConfig) -> Void
    private let onGlobalHotkeyPressed: (Hotkey) -> Void
    private let configDidChange: () -> Void
    /// #110: the history that 移除历史记录项目 and 清除浏览数据… act on — the same store
    /// `Orchestrator` records into. `nil` keeps no history (most tests).
    private let historyStore: HistoryStore?

    public var config: WidgetConfig { currentConfig() }

    /// - Parameters:
    ///   - onGlobalHotkeyPressed: the handler every hotkey this controller registers dispatches
    ///     to — `Orchestrator.handleGlobalHotkeyPressed`, the same one launch-time registrations
    ///     use, so a combo bound here behaves identically to one bound at launch.
    ///   - configDidChange: a core-to-core notification (not a `PlatformOps` method) fired after
    ///     each persisted edit, for the settings that must be actively re-applied (#46).
    ///   - historyStore: the app's one `HistoryStore` (#110).
    public init(
        platformOps: PlatformOps, currentConfig: @escaping () -> WidgetConfig,
        persist: @escaping (@escaping (WidgetConfig) -> WidgetConfig) -> Void,
        onGlobalHotkeyPressed: @escaping (Hotkey) -> Void = { _ in },
        configDidChange: @escaping () -> Void = {},
        historyStore: HistoryStore? = nil
    ) {
        self.platformOps = platformOps
        self.currentConfig = currentConfig
        self.persist = persist
        self.onGlobalHotkeyPressed = onGlobalHotkeyPressed
        self.configDidChange = configDidChange
        self.historyStore = historyStore
    }

    // MARK: Writes from anywhere (#109)

    private var configPersistedHandlers: [() -> Void] = []

    /// Told by whoever owns the app's one `persist` (`AppDelegate`) after every write — this
    /// controller's own edits and those made elsewhere alike: the 询问框's 「访问此网站时允许」 (#109),
    /// the page last visited, the window's geometry. Not a config edit itself: nothing is persisted
    /// and `configDidChange` doesn't fire.
    public func configWasPersisted() {
        configPersistedHandlers.forEach { $0() }
    }

    /// For the panel to read `config` again after any write (see `configWasPersisted`) — reading
    /// it fresh rather than keeping a copy that someone else's write would leave stale.
    public func onConfigPersisted(perform handler: @escaping () -> Void) {
        configPersistedHandlers.append(handler)
    }

    /// Every edit goes through here so `configDidChange` can never be forgotten for a new setting
    /// — hot-reload is the default, not something each setting opts into (#46).
    private func persistAndNotify(_ transform: @escaping (WidgetConfig) -> WidgetConfig) {
        persist(transform)
        configDidChange()
    }

    public func updateStartupTarget(_ target: WidgetConfig.StartupTarget?) {
        persistAndNotify { $0.updatingStartupTarget(target) }
    }

    public func updateGhostOpacity(_ opacity: Double) {
        persistAndNotify { $0.updatingGhostOpacity(opacity) }
    }

    public func updateSnapEnabled(_ enabled: Bool) {
        persistAndNotify { $0.updatingSnapEnabled(enabled) }
    }

    /// #70 — applies on the next widget open (see `WidgetConfig.autoplayPolicy`).
    public func updateAutoplayPolicy(_ policy: WidgetConfig.AutoplayPolicy) {
        persistAndNotify { $0.updatingAutoplayPolicy(policy) }
    }

    /// #70 — `nil` removes the limit; pushed live through `configDidChange`.
    public func updateMinimumFontSize(_ size: Int?) {
        persistAndNotify { $0.updatingMinimumFontSize(size) }
    }

    /// #67 — pushed live through `configDidChange`.
    public func updatePopupWindowPolicy(_ policy: WidgetConfig.PopupWindowPolicy) {
        persistAndNotify { $0.updatingPopupWindowPolicy(policy) }
    }

    // #72: 高级 pane
    public func updateHTTPWarningEnabled(_ enabled: Bool) {
        persistAndNotify { $0.updatingHTTPWarningEnabled(enabled) }
    }

    public func updateWebInspectorEnabled(_ enabled: Bool) {
        persistAndNotify { $0.updatingWebInspectorEnabled(enabled) }
    }

    // #69: 网站 → 摄像头 / 麦克风's 「访问其他网站时」 default — read at each request, so persisting is applying.
    public func updateCameraPermission(_ permission: WidgetConfig.MediaCapturePermission) {
        persistAndNotify { $0.updatingCameraPermission(permission) }
    }

    public func updateMicrophonePermission(_ permission: WidgetConfig.MediaCapturePermission) {
        persistAndNotify { $0.updatingMicrophonePermission(permission) }
    }

    // #109: 网站 → 摄像头 / 麦克风's exceptions table (ADR-0027) — read at each request, so
    // persisting is applying.

    /// Stamps an exception edited in the table, and is what 清除浏览数据's 「过去 1 小时」 and the
    /// rest count back from (#107). Tests swap in a fixed date, like `Orchestrator.currentDate`.
    public var currentDate: () -> Date = { Date() }

    /// Sets `host`'s exception for `permission` to `setting`, stamped with the time of the edit.
    public func updatePagePermissionException(
        _ permission: PagePermission, host: String, setting: WidgetConfig.MediaCapturePermission
    ) {
        let modifiedAt = currentDate()
        persistAndNotify { $0.updatingPagePermissionException(permission, host: host, setting: setting, modifiedAt: modifiedAt) }
    }

    /// 移除: deletes the exceptions of `hosts` in one write, sending those websites back to the
    /// default. Removing nothing writes nothing.
    public func removePagePermissionExceptions(_ permission: PagePermission, hosts: Set<String>) {
        guard !hosts.isEmpty else { return }
        let modifiedAt = currentDate()
        persistAndNotify { config in
            hosts.reduce(config) {
                $0.updatingPagePermissionException(permission, host: $1, setting: nil, modifiedAt: modifiedAt)
            }
        }
    }

    /// #110: 移除历史记录项目. Shortening it removes what is now past it at once, not at the next
    /// launch.
    public func updateHistoryRetention(_ retention: HistoryRetention) {
        persistAndNotify { $0.updatingHistoryRetention(retention) }
        historyStore?.removeEntries(olderThan: currentConfig().historyRetention)
    }

    // MARK: - #107: 清除浏览数据…

    /// Clears `kinds` modified within `range`: 历史记录 from the history (the pages last visited
    /// since the start, #110), the website data ones through the platform, the 网页权限例外
    /// through the config (by their modification time). The page isn't reloaded. The UI asks for
    /// confirmation before calling this.
    public func clearBrowsingData(_ kinds: Set<BrowsingDataKind>, from range: BrowsingDataTimeRange) {
        let start = range.startDate(now: currentDate())
        if kinds.contains(.history) {
            historyStore?.removeEntries(visitedSince: start)
        }
        let categories = BrowsingDataKind.websiteDataCategories(for: kinds)
        if !categories.isEmpty {
            platformOps.removeData(ofTypes: categories, modifiedSince: start)
        }
        if kinds.contains(.pagePermissionExceptions) {
            persistAndNotify { $0.removingPagePermissionExceptions(modifiedSince: start) }
        }
    }

    // MARK: 管理网站和数据… (#106, ADR-0027) — deleting data and resetting 网页权限 are separate.

    /// The websites with data or exceptions, grouped by `ManagedWebsites.grouping` against the
    /// config in effect when the records arrive.
    public func fetchManagedWebsites(completion: @escaping ([ManagedWebsite]) -> Void) {
        platformOps.fetchWebsiteDataRecords { [currentConfig] records in
            completion(ManagedWebsites.grouping(records, exceptionsIn: currentConfig()))
        }
    }

    /// 删除数据: every kind of data of the websites that have any; their exceptions stay. Not a
    /// config edit, and the page isn't reloaded.
    public func removeWebsiteData(of websites: [ManagedWebsite], completion: @escaping () -> Void) {
        removeAllKindsOfData(forRecordsNamed: websites.filter(\.hasData).map(\.domain), completion: completion)
    }

    /// 全部删除: the data of every website WebKit has a record for. Exceptions stay, as for
    /// 删除数据; the UI asks for confirmation before calling this.
    public func removeDataOfAllWebsites(completion: @escaping () -> Void) {
        platformOps.fetchWebsiteDataRecords { [weak self] records in
            guard let self else { return completion() }
            removeAllKindsOfData(forRecordsNamed: records.map(\.displayName), completion: completion)
        }
    }

    private func removeAllKindsOfData(forRecordsNamed names: [String], completion: @escaping () -> Void) {
        guard !names.isEmpty else { return completion() }
        platformOps.removeWebsiteData(ofKinds: Set(WebsiteDataKind.allCases), forRecordsNamed: names, completion: completion)
    }

    /// 重置权限: removes both permissions' exceptions for every host listed under `websites`,
    /// sending them back to 「访问其他网站时」; their data stays.
    public func resetPagePermissions(of websites: [ManagedWebsite]) {
        let hosts = websites.flatMap { $0.exceptions.map(\.host) }
        guard !hosts.isEmpty else { return }
        let now = currentDate()
        persistAndNotify { config in
            hosts.reduce(config) { config, host in
                PagePermission.allCases.reduce(config) {
                    $0.updatingPagePermissionException($1, host: host, setting: nil, modifiedAt: now)
                }
            }
        }
    }

    public func updateSearchEngine(_ engine: SearchEngine) {
        persistAndNotify { $0.updatingSearchEngine(engine) }
    }

    /// #68 — read at each download, so persisting is applying.
    public func updateDownloadLocation(_ location: DownloadLocation) {
        persistAndNotify { $0.updatingDownloadLocation(location) }
    }

    public func updateCustomScript(_ script: String?) {
        persistAndNotify { $0.updatingCustomScript(script) }
    }

    public func updateCustomStylesheet(_ css: String?) {
        persistAndNotify { $0.updatingCustomStylesheet(css) }
    }

    public func setBuiltInScript(_ id: String, enabled: Bool) {
        persistAndNotify { config in
            var ids = config.disabledBuiltInScriptIDs
            if enabled { ids.remove(id) } else { ids.insert(id) }
            return config.updatingDisabledBuiltInScriptIDs(ids)
        }
    }

    // MARK: - #45: the two action hotkeys

    /// Rebinds `action` to `hotkey`, live, or clears it with `nil` (#85) — releasing the combo
    /// to other apps. Order matters: the old combo is released *before* the new one is claimed,
    /// since the new one might be the old one with a different action (a swap) — and if claiming
    /// fails (another app holds it), the old combo is re-registered and the config left
    /// untouched, so a failed attempt can never take away the hotkey the action had. A cleared
    /// action has nothing to release first, and nothing to fall back to: it stays cleared.
    ///
    /// Returns why it was refused (#86), or `nil` once the change is live.
    @discardableResult
    public func updateActionHotkey(_ action: HotkeyAction, to hotkey: Hotkey?) -> HotkeyRejection? {
        let current = currentConfig().hotkey(for: action)
        guard hotkey != current else { return nil }
        if let hotkey {
            if hotkey.isMissingModifier { return .missingModifier }
            if let conflict = inProcessConflict(with: hotkey, ignoringAction: action, ignoringMappingAt: nil) {
                return conflict
            }
            guard rebind(from: current, to: hotkey) else { return .heldByAnotherApp }
        } else if let current {
            platformOps.unregisterGlobalHotkey(current)
        }
        persistAndNotify { $0.updatingHotkeyOverride(action, to: hotkey) }
        return nil
    }

    /// Puts every overridden action back on its built-in combo, cleared ones included (#85) — the
    /// escape hatch for a user who bound both hotkeys to something odd and forgot what (#45). Each action is its own
    /// transaction with the same rollback rule as `updateActionHotkey`; one default being held —
    /// by another app, or in-process by a mapping or a video key — doesn't stop the other from
    /// being restored.
    public func resetActionHotkeysToDefaults() {
        var restored: [HotkeyAction] = []
        var failedNames: [String] = []
        for action in HotkeyAction.allCases {
            let current = currentConfig().hotkey(for: action)
            guard current != action.defaultHotkey else { continue }
            // Every action is on its way back to its own default and the defaults never collide,
            // so only something that isn't an action can be in the way.
            let conflict = inProcessConflict(with: action.defaultHotkey, ignoringAction: action, ignoringMappingAt: nil)
            if let conflict, !conflict.isActionConflict {
                failedNames.append(action.displayName)
            } else if rebind(from: current, to: action.defaultHotkey) {
                restored.append(action)
            } else {
                failedNames.append(action.displayName)
            }
        }
        if !restored.isEmpty {
            persistAndNotify { config in
                restored.reduce(config) { $0.updatingHotkeyOverride($1, to: $1.defaultHotkey) }
            }
        }
        if !failedNames.isEmpty {
            platformOps.presentAlert(
                title: "部分默认热键无法恢复",
                message: "以下功能的默认热键已被其他应用或 Mochi 的其他按键占用，已保留当前设置：\(failedNames.joined(separator: "、"))"
            )
        }
    }

    /// The unregister-then-register transaction shared by every live hotkey change, with the
    /// rollback that keeps "old released, new not claimed" from ever being an observable state.
    /// `old` is `nil` for a cleared action (#85): nothing to release, nothing to roll back to.
    private func rebind(from old: Hotkey?, to new: Hotkey) -> Bool {
        if let old { platformOps.unregisterGlobalHotkey(old) }
        if registerDispatching(new) { return true }
        if let old { platformOps.registerGlobalHotkey(old) { [onGlobalHotkeyPressed] in onGlobalHotkeyPressed(old) } }
        return false
    }

    private func registerDispatching(_ hotkey: Hotkey) -> Bool {
        platformOps.registerGlobalHotkey(hotkey) { [onGlobalHotkeyPressed] in onGlobalHotkeyPressed(hotkey) }
    }

    // MARK: - #14/#46: forwarding mappings

    /// Adds a new hotkey mapping (#14), live (#46). Conflict detection is two-tiered:
    ///
    /// 1. Combos already known in-process (the two action hotkeys at their *current* combos, the
    ///    fixed local menu shortcuts, or another entry already in the mapping table) are checked
    ///    directly against those — `GlobalHotkeyRegistry`'s underlying `RegisterEventHotKey` does
    ///    **not** fail on an in-process duplicate registration (it happily installs a second,
    ///    independently-firing handler for the same combo instead), so registration
    ///    success/failure alone cannot be trusted to catch these.
    /// 2. Anything left over is handed to `PlatformOps.registerGlobalHotkey` — reusing the same
    ///    OS-level check every other hotkey registration in the app already goes through — to
    ///    catch a combo another *application* holds. The registration this leaves behind is the
    ///    real one: it dispatches through `onGlobalHotkeyPressed`, which resolves the trigger to
    ///    its page keystroke against the config at press time, so the mapping forwards from the
    ///    moment it's persisted.
    ///
    /// A tap or double tap (#92) skips the second tier: nothing is registered — the input
    /// listener hears it, and starts listening through `configDidChange` — so it can only clash
    /// in-process, with a video key or another mapping.
    ///
    /// Returns why it was refused (#86), or `nil` once the mapping is live.
    @discardableResult
    public func addHotkeyMapping(trigger: TriggerKey, pageKeystroke: Hotkey) -> HotkeyRejection? {
        if let refusal = mappingTriggerRefusal(trigger, ignoringMappingAt: nil) { return refusal }
        if case .keystroke(let hotkey) = trigger, !registerDispatching(hotkey) { return .heldByAnotherApp }
        persistAndNotify { $0.updatingHotkeyMappings($0.hotkeyMappings + [HotkeyMapping(trigger: trigger, pageKeystroke: pageKeystroke)]) }
        return nil
    }

    @discardableResult
    public func addHotkeyMapping(trigger: Hotkey, pageKeystroke: Hotkey) -> HotkeyRejection? {
        addHotkeyMapping(trigger: .keystroke(trigger), pageKeystroke: pageKeystroke)
    }

    /// Re-runs the same two-tiered conflict check as `addHotkeyMapping` only when `trigger`
    /// actually changes, then swaps the OS registration as one unregister-old/register-new
    /// transaction with rollback (#46). Editing just the page-keystroke half never touches the OS
    /// hotkey table: the registered handler looks the page keystroke up at press time, so the
    /// persisted change is already live.
    ///
    /// Returns why it was refused (#86), or `nil` once the change is live — an index out of range
    /// is a no-op, not a refusal.
    @discardableResult
    public func updateHotkeyMapping(at index: Int, trigger: TriggerKey, pageKeystroke: Hotkey) -> HotkeyRejection? {
        let mappings = currentConfig().hotkeyMappings
        guard mappings.indices.contains(index) else { return nil }
        if trigger != mappings[index].trigger {
            if let refusal = mappingTriggerRefusal(trigger, ignoringMappingAt: index) { return refusal }
            let oldHotkey = mappings[index].registeredHotkey
            if case .keystroke(let hotkey) = trigger {
                guard rebind(from: oldHotkey, to: hotkey) else { return .heldByAnotherApp }
            } else if let oldHotkey {
                platformOps.unregisterGlobalHotkey(oldHotkey)
            }
        }
        persistAndNotify { config in
            var mappings = config.hotkeyMappings
            mappings[index] = HotkeyMapping(trigger: trigger, pageKeystroke: pageKeystroke)
            return config.updatingHotkeyMappings(mappings)
        }
        return nil
    }

    @discardableResult
    public func updateHotkeyMapping(at index: Int, trigger: Hotkey, pageKeystroke: Hotkey) -> HotkeyRejection? {
        updateHotkeyMapping(at: index, trigger: .keystroke(trigger), pageKeystroke: pageKeystroke)
    }

    /// Why `trigger` can't be a mapping's: a combo with no ⌃/⌥/⌘ (#89) or one already held
    /// in-process; a tap or double tap (#92) already some video key's or another mapping's.
    private func mappingTriggerRefusal(_ trigger: TriggerKey, ignoringMappingAt editedIndex: Int?) -> HotkeyRejection? {
        guard case .keystroke(let hotkey) = trigger else {
            return tapConflict(trigger, ignoringVideoAction: nil, ignoringMappingAt: editedIndex)
        }
        if hotkey.isMissingModifier { return .missingModifier }
        return inProcessConflict(with: hotkey, ignoringAction: nil, ignoringMappingAt: editedIndex)
    }

    /// What already listens for the tap or double tap `trigger` (#92): a video key or a mapping.
    /// Taps are never registered with the OS, so this is the only check they get.
    private func tapConflict(
        _ trigger: TriggerKey, ignoringVideoAction editedVideoAction: VideoControlAction?, ignoringMappingAt editedIndex: Int?
    ) -> HotkeyRejection? {
        let config = currentConfig()
        if let action = VideoControlAction.allCases.first(where: { $0 != editedVideoAction && config.videoControlTrigger(for: $0) == trigger }) {
            return .conflictsWithVideoControl(action)
        }
        let mapping = config.hotkeyMappings.enumerated().first { $0.offset != editedIndex && $0.element.trigger == trigger }
        return mapping.map { .conflictsWithMapping($0.element) }
    }

    /// Deleting a mapping hands its trigger back to the system immediately (#46) — the combo is
    /// genuinely released, not still intercepted until the next launch. A tap or double tap was
    /// never taken; the listener just stops answering for it.
    public func removeHotkeyMapping(at index: Int) {
        let mappings = currentConfig().hotkeyMappings
        guard mappings.indices.contains(index) else { return }
        if let hotkey = mappings[index].registeredHotkey { platformOps.unregisterGlobalHotkey(hotkey) }
        persistAndNotify { config in
            var mappings = config.hotkeyMappings
            guard mappings.indices.contains(index) else { return config }
            mappings.remove(at: index)
            return config.updatingHotkeyMappings(mappings)
        }
    }

    /// Whether `candidate` is already taken by something in this process, judged against the
    /// combos *actually in effect* — the action hotkeys at their current (possibly overridden)
    /// combos, not the built-in defaults (#45). Checking defaults would both miss a collision
    /// with a user's rebinding and wrongly refuse a combo that was a default but has since been
    /// released by being rebound.
    ///
    /// - Parameters:
    ///   - ignoringAction: the action being rebound, excluded so it can't collide with itself.
    ///   - ignoringMappingAt: the mapping index being edited, excluded for the same reason — `nil`
    ///     when adding a brand new mapping, where every existing entry counts.
    ///   - ignoringVideoAction: the 视频控制 action being rebound (#79), excluded the same way.
    ///
    /// Returns what already holds `candidate` (#86), or `nil` when nothing in-process does.
    private func inProcessConflict(
        with candidate: Hotkey, ignoringAction editedAction: HotkeyAction?, ignoringMappingAt editedIndex: Int?,
        ignoringVideoAction editedVideoAction: VideoControlAction? = nil
    ) -> HotkeyRejection? {
        let config = currentConfig()
        if let action = HotkeyAction.allCases.first(where: { $0 != editedAction && config.hotkey(for: $0) == candidate }) {
            return .conflictsWithAction(action)
        }
        if DefaultHotkeys.reservedLocalMenuShortcuts.contains(candidate) { return .reservedMenuShortcut }
        // A video key is never registered with the OS — it only listens — so an in-process check
        // is the only thing standing between it and a hotkey firing on the same press.
        if let action = VideoControlAction.allCases.first(where: {
            $0 != editedVideoAction && config.videoControlTrigger(for: $0) == .keystroke(candidate)
        }) {
            return .conflictsWithVideoControl(action)
        }
        let mapping = config.hotkeyMappings.enumerated().first { offset, mapping in
            offset != editedIndex && mapping.registeredHotkey == candidate
        }
        return mapping.map { .conflictsWithMapping($0.element) }
    }

    // MARK: - #79: 视频控制

    /// Binds a 视频控制 action to `trigger`, or clears it with `nil`. Nothing is registered with
    /// the OS — Video Control only listens (ADR-0020) — so the only conflicts are in-process: the
    /// action hotkeys, the local menu shortcuts, the mapping triggers, and the other video keys.
    /// Listening starts or stops through `configDidChange` when this binds the first key or
    /// clears the last.
    ///
    /// Returns why it was refused (#86), or `nil` once the change is live.
    @discardableResult
    public func updateVideoControlTrigger(_ trigger: TriggerKey?, for action: VideoControlAction) -> HotkeyRejection? {
        let config = currentConfig()
        if let trigger, trigger != config.videoControlTrigger(for: action) {
            if case .keystroke(let hotkey) = trigger {
                // The combo itself first, as for every other row, then who else holds it.
                if hotkey.isMissingModifier { return .missingModifier }
                if let other = VideoControlAction.allCases.first(where: { $0 != action && config.videoControlTrigger(for: $0) == trigger }) {
                    return .conflictsWithVideoControl(other)
                }
                if let conflict = inProcessConflict(with: hotkey, ignoringAction: nil, ignoringMappingAt: nil, ignoringVideoAction: action) {
                    return conflict
                }
            } else if let conflict = tapConflict(trigger, ignoringVideoAction: action, ignoringMappingAt: nil) {
                return conflict
            }
        }
        persistAndNotify { $0.updatingVideoControlTrigger(trigger, for: action) }
        return nil
    }

    public func updateVideoSeekStep(_ seconds: Int) {
        persistAndNotify { $0.updatingVideoSeekStep(seconds) }
    }

    /// Every video key back on its default, and the jump length back to its default.
    public func resetVideoControlToDefaults() {
        persistAndNotify { config in
            VideoControlAction.allCases
                .reduce(config) { $0.updatingVideoControlTrigger($1.defaultTrigger, for: $1) }
                .updatingVideoSeekStep(WidgetConfig.defaultVideoSeekStep)
        }
    }

    // MARK: 系统权限 (#98, ADR-0026)

    /// The panel's 系统权限 prompts — read fresh each time, since the user grants permissions in
    /// System Settings, outside Mochi.
    public var systemPermissionPrompts: [SystemPermissionPrompt] {
        SystemPermissionPrompts.prompts(
            for: config, status: platformOps.systemPermissionStatus,
            accessibilityRequested: platformOps.isSystemPermissionMarkerSet(.accessibilityRequested),
            downloadsFolderWriteDenied: platformOps.isSystemPermissionMarkerSet(.downloadsFolderWriteDenied))
    }

    /// What a prompt's button does; a prompt without one does nothing.
    public func perform(_ prompt: SystemPermissionPrompt) {
        prompt.perform(on: platformOps)
    }

    /// For the panel to read `systemPermissionPrompts` again (see
    /// `PlatformOps.onSystemPermissionsMayHaveChanged`).
    public func onSystemPermissionsMayHaveChanged(perform handler: @escaping () -> Void) {
        platformOps.onSystemPermissionsMayHaveChanged(perform: handler)
    }
}
