import SwiftUI

extension FocusedValues {
    @Entry var reportZoom: Binding<Int>?
}

struct ReportZoomCommands: Commands {
    @FocusedValue(\.reportZoom) private var zoom

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("放大曲目列表") {
                if let zoom { zoom.wrappedValue = min(zoom.wrappedValue + 1, 1) }
            }
            .keyboardShortcut("+")
            .disabled(zoom.map { $0.wrappedValue >= 1 } ?? true)

            Button("缩小曲目列表") {
                if let zoom { zoom.wrappedValue = max(zoom.wrappedValue - 1, -1) }
            }
            .keyboardShortcut("-")
            .disabled(zoom.map { $0.wrappedValue <= -1 } ?? true)

            Button("恢复曲目列表大小") { zoom?.wrappedValue = 0 }
                .keyboardShortcut("0")
                .disabled(zoom.map { $0.wrappedValue == 0 } ?? true)
        }
    }
}
