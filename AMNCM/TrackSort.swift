import Foundation

struct TrackSort: SortComparator {
    enum Column: Hashable {
        case title, artist, date, status
    }

    let column: Column
    var order: SortOrder = .forward

    func compare(_ lhs: SyncReport.Entry, _ rhs: SyncReport.Entry) -> ComparisonResult {
        let comparison: ComparisonResult
        switch column {
        case .title:
            comparison = lhs.source.title.localizedStandardCompare(rhs.source.title)
        case .artist:
            comparison = (lhs.source.artist ?? "").localizedStandardCompare(rhs.source.artist ?? "")
        case .date:
            comparison = (lhs.source.dateAdded ?? .distantPast).compare(rhs.source.dateAdded ?? .distantPast)
        case .status:
            comparison = lhs.statusLabel.localizedStandardCompare(rhs.statusLabel)
        }
        guard order == .reverse, comparison != .orderedSame else { return comparison }
        return comparison == .orderedAscending ? .orderedDescending : .orderedAscending
    }
}
