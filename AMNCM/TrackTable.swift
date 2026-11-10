import SwiftUI

struct TrackTable: View {
    let entries: [SyncReport.Entry]
    @Binding var selection: SyncReport.Entry.ID?

    var body: some View {
        Table(entries, selection: $selection) {
            TableColumn("歌曲", value: \.source.title)
            TableColumn("艺人") { entry in
                Text(entry.source.artist ?? "—")
            }
            TableColumn("添加日期") { entry in
                if let date = entry.source.dateAdded {
                    Text(date, format: .dateTime.year().month().day())
                } else {
                    Text("—")
                }
            }
            TableColumn("匹配状态", value: \.statusLabel)
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView("没有符合条件的曲目", systemImage: "magnifyingglass")
            }
        }
    }
}
