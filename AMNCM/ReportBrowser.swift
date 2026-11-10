import SwiftUI

struct ReportBrowser: View {
    private enum Scope: String, CaseIterable, Identifiable {
        case all = "全部曲目"
        case additions = "计划新增"
        case review = "待复核"
        case matched = "已匹配"

        var id: Self { self }

        var symbol: String {
            switch self {
            case .all: "music.note.list"
            case .additions: "plus.circle"
            case .review: "exclamationmark.magnifyingglass"
            case .matched: "checkmark.circle"
            }
        }

        func includes(_ entry: SyncReport.Entry, additions: Set<String>) -> Bool {
            switch self {
            case .all: true
            case .additions: entry.targetID.map(additions.contains) == true
            case .review: entry.needsReview
            case .matched: entry.isMatched
            }
        }
    }

    let report: SyncReport
    @State private var scope: Scope? = .review
    @State private var selection: SyncReport.Entry.ID?
    @State private var query = ""

    private var filteredEntries: [SyncReport.Entry] {
        let scope = scope ?? .all
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let additions = report.additions ?? []
        return report.entries.filter { entry in
            scope.includes(entry, additions: additions) && (search.isEmpty
                || entry.source.title.localizedStandardContains(search)
                || entry.source.artist?.localizedStandardContains(search) == true
                || entry.source.album?.localizedStandardContains(search) == true)
        }
    }

    var body: some View {
        let entries = filteredEntries
        NavigationSplitView {
            List(selection: $scope) {
                Section("匹配报告") {
                    ForEach(Scope.allCases) { scope in
                        Label(scope.rawValue, systemImage: scope.symbol)
                            .badge(report.entries.count { scope.includes($0, additions: report.additions ?? []) })
                            .tag(scope)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 155, ideal: 175)
        } content: {
            TrackTable(entries: entries, selection: $selection)
                .navigationTitle(scope?.rawValue ?? Scope.all.rawValue)
                .navigationSubtitle(report.target.name)
                .searchable(text: $query, prompt: "搜索歌名、艺人或专辑")
                .navigationSplitViewColumnWidth(min: 395, ideal: 595)
        } detail: {
            if let entry = entries.first(where: { $0.id == selection }) {
                TrackDetail(entry: entry)
            } else {
                ContentUnavailableView("选择一首曲目", systemImage: "music.note", description: Text("查看 Apple Music 元数据与网易云候选。"))
            }
        }
    }
}
