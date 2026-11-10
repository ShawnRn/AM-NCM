import SwiftUI

struct ReportView: View {
    let reportVersion: Int
    @State private var report: SyncReport?
    @State private var errorMessage: String?
    @State private var reload = 0

    var body: some View {
        Group {
            if let report {
                ReportBrowser(report: report, reload: { reload += 1 })
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("无法打开同步报告", systemImage: "music.note.list")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重新载入") { reload += 1 }
                        .keyboardShortcut("r")
                }
            } else {
                ProgressView("读取同步报告…")
            }
        }
        .alert("重新载入失败", isPresented: Binding(
            get: { report != nil && errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task(id: LoadTrigger(manual: reload, report: reportVersion)) {
            do {
                let latest = try await SyncReport.load()
                try Task.checkCancellation()
                report = latest
                errorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                if (error as NSError).code == NSFileReadNoSuchFileError {
                    errorMessage = "回到首页，选择「手动同步」后即可查看匹配明细。"
                } else {
                    errorMessage = ChineseInterfaceText.format(error.localizedDescription)
                }
            }
        }
    }
}


private struct LoadTrigger: Equatable {
    let manual: Int
    let report: Int
}
