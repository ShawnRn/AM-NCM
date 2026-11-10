import SwiftUI

struct TrackArtwork: View {
    let trackID: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: NSImage?
    @State private var loading = true

    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel("专辑封面")
                        .transition(.opacity)
                } else if loading && !reduceMotion {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在读取专辑封面")
                } else {
                    Image(systemName: "music.note")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel(loading ? "正在读取专辑封面" : "没有专辑封面")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .task {
                var loaded: NSImage?
                do {
                    try await Task.sleep(for: .milliseconds(180))
                    try await Engine().run("artwork", ids: [trackID]) { event in
                        guard !Task.isCancelled, event.kind == "artwork",
                              let encoded = event.data, let data = Data(base64Encoded: encoded) else { return }
                        loaded = NSImage(data: data)
                    }
                } catch {
                    // Leave the placeholder visible when artwork is unavailable.
                }
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                    image = loaded
                    loading = false
                }
            }
    }
}
