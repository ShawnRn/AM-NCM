import SwiftUI

struct TrackDetail: View {
    let entry: SyncReport.Entry

    var body: some View {
        Form {
            Section("Apple Music") {
                TrackArtwork(trackID: entry.id)
                    .id(entry.id)
                    .padding(.vertical, 4)
                LabeledContent("歌名", value: entry.source.title)
                LabeledContent("艺人", value: entry.source.artist ?? "—")
                LabeledContent("专辑", value: entry.source.album ?? "—")
                LabeledContent("时长", value: entry.source.durationLabel)
                LabeledContent("状态", value: entry.statusLabel)
            }

            Section("网易云候选") {
                if let candidates = entry.candidates, !candidates.isEmpty {
                    ForEach(candidates) { track in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.title)
                                .font(.headline)
                            Text(track.artist ?? "—")
                            Text(track.album ?? "—")
                            Text("\(track.durationLabel) · ID \(track.id)")
                                .monospacedDigit()
                        }
                        .foregroundStyle(.primary)
                        .padding(.vertical, 4)
                    }
                } else {
                    Text("报告中没有候选。")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .textSelection(.enabled)
    }
}
