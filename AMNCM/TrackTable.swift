import SwiftUI

struct TrackTable: View {
    let entries: [SyncReport.Entry]
    @Binding var selection: SyncReport.Entry.ID?
    let fontSize: CGFloat

    var body: some View {
        if entries.isEmpty {
            ContentUnavailableView("没有符合条件的曲目", systemImage: "magnifyingglass")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(entries, selection: $selection) {
                TableColumn("歌曲") { entry in cell(entry.source.title) }
                TableColumn("艺人") { entry in
                    cell(entry.source.artist ?? "—")
                }
                TableColumn("添加日期") { entry in
                    if let date = entry.source.dateAdded {
                        cell(ChineseInterfaceText.format(date.formatted(.dateTime.year().month().day())))
                    } else {
                        cell("—")
                    }
                }
                TableColumn("匹配状态") { entry in cell(entry.statusLabel) }
            }
        }
    }

    private func cell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: fontSize))
            .lineLimit(1)
            .frame(minHeight: fontSize + 4)
    }
}
