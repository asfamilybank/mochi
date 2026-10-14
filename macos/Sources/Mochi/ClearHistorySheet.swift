import MochiCore
import SwiftUI

/// The 历史记录 window's 清除历史记录… (ADR-0032): 清除浏览数据's sheet with nothing but its time
/// range, because it clears history and only history — website data stays 清除浏览数据…'s. Shown
/// over the 历史记录 window; nothing is cleared until 清除 is clicked.
struct ClearHistorySheet: View {
    let onClear: (BrowsingDataTimeRange) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var range = BrowsingDataTimeRange.defaultRange

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("清除历史记录")
                .font(.headline)

            Form {
                Picker("时间范围：", selection: $range) {
                    ForEach(BrowsingDataTimeRange.allCases, id: \.self) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                .fixedSize()
            }
            .formStyle(.columns)

            Text("只清除这段时间内访问过的网页，不会清除 Cookie、缓存等网站数据，也不会退出登录。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("清除", role: .destructive) {
                    onClear(range)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
