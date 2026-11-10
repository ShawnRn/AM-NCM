import SwiftUI

struct TrackTable: View, Animatable {
    let entries: [SyncReport.Entry]
    @Binding var selection: SyncReport.Entry.ID?
    @Binding var sortOrder: [TrackSort]
    nonisolated var fontSize: CGFloat

    nonisolated var animatableData: CGFloat {
        get { fontSize }
        set { fontSize = newValue }
    }

    var body: some View {
        if entries.isEmpty {
            ContentUnavailableView("没有符合条件的曲目", systemImage: "magnifyingglass")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let scale = fontSize / 13
            Table(entries, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("歌曲", sortUsing: TrackSort(column: .title)) { entry in cell(entry.source.title) }
                    .width(182 * scale)
                TableColumn("艺人", sortUsing: TrackSort(column: .artist)) { entry in
                    cell(entry.source.artist ?? "—")
                }
                .width(116 * scale)
                TableColumn("添加日期", sortUsing: TrackSort(column: .date)) { entry in
                    if let date = entry.source.dateAdded {
                        cell(ChineseInterfaceText.format(date.formatted(.dateTime.year().month().day())))
                    } else {
                        cell("—")
                    }
                }
                .width(130 * scale)
                TableColumn("匹配状态", sortUsing: TrackSort(column: .status)) { entry in cell(entry.statusLabel) }
                    .width(min: 76 * scale, ideal: 90 * scale)
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
