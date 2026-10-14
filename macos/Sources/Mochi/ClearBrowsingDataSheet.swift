import MochiCore
import SwiftUI

/// 清除浏览数据… (#107), after Chrome's 删除浏览数据: a time range and the kinds to clear, shown as a
/// sheet on the settings window — and on the 历史记录 window, as its 清除历史记录… (#115,
/// ADR-0031). The sheet is the confirmation step — nothing is cleared until 清除 is clicked — and
/// `onClear` hands the choice to `SettingsController.clearBrowsingData`.
struct ClearBrowsingDataSheet: View {
    let onClear: BrowsingDataClearing
    @Environment(\.dismiss) private var dismiss
    @State private var range = BrowsingDataTimeRange.defaultRange
    @State private var kinds: Set<BrowsingDataKind>

    /// - Parameter initialKinds: what is ticked as the sheet opens — the defaults, except from the
    ///   历史记录 window, whose button says 清除历史记录… and so ticks 历史记录 alone.
    init(
        initialKinds: Set<BrowsingDataKind> = BrowsingDataKind.defaultSelection,
        onClear: @escaping BrowsingDataClearing
    ) {
        self.onClear = onClear
        _kinds = State(initialValue: initialKinds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("清除浏览数据")
                .font(.headline)

            Form {
                Picker("时间范围：", selection: $range) {
                    ForEach(BrowsingDataTimeRange.allCases, id: \.self) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                .fixedSize()

                LabeledContent("清除：") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(BrowsingDataKind.allCases, id: \.self) { kind in
                            Toggle(isOn: binding(for: kind)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(kind.displayName)
                                    Text(Self.detail(of: kind))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.columns)

            Text("当前页面不会自动刷新。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("清除", role: .destructive) {
                    onClear(kinds, range)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(kinds.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func binding(for kind: BrowsingDataKind) -> Binding<Bool> {
        Binding(
            get: { kinds.contains(kind) },
            set: { isOn in
                if isOn { kinds.insert(kind) } else { kinds.remove(kind) }
            }
        )
    }

    private static func detail(of kind: BrowsingDataKind) -> String {
        switch kind {
        case .history: "这段时间内访问过的网页，不会退出登录。"
        case .websiteData: "会让你退出这段时间内登录过的网站。"
        case .cache: "不会退出登录；网站下次打开时可能稍慢。"
        case .pagePermissionExceptions: "这段时间内新建或改过的摄像头、麦克风网站例外。"
        }
    }
}
