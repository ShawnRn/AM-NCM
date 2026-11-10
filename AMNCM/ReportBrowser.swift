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
    let reload: () -> Void
    @State private var scope: Scope? = .review
    @State private var selection: SyncReport.Entry.ID?
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("reportZoom") private var zoom = 0

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
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Button("搜索", systemImage: "magnifyingglass") { searchFocused = true }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .keyboardShortcut("f")
                        TextField("搜索歌名、艺人或专辑", text: $query)
                            .textFieldStyle(.plain)
                            .focused($searchFocused)
                        if !query.isEmpty {
                            Button("清除搜索", systemImage: "xmark.circle.fill") { query = "" }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 7))
                    Button("重新载入", systemImage: "arrow.clockwise", action: reload)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                        .keyboardShortcut("r")
                        .help("重新载入匹配报告")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider()
                TrackTable(entries: entries, selection: $selection, fontSize: CGFloat(13 + min(max(zoom, -1), 1) * 2))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: zoom)
            }
            .navigationTitle(scope?.rawValue ?? Scope.all.rawValue)
            .navigationSubtitle(report.target.name)
            .navigationSplitViewColumnWidth(min: 395, ideal: 595)
        } detail: {
            if let entry = entries.first(where: { $0.id == selection }) {
                TrackDetail(entry: entry)
            } else {
                ContentUnavailableView(entries.isEmpty ? "没有曲目可显示" : "选择一首曲目", systemImage: "music.note")
            }
        }
        .focusedSceneValue(\.reportZoom, $zoom)
        .onAppear { zoom = min(max(zoom, -1), 1) }
    }
}
