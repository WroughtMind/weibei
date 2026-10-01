import SwiftUI

struct WhiteboardCanvasTools: View {
    @ObservedObject var classroom: WhiteboardClassroom
    var body: some View {
        HStack(spacing: 8) {
            tool("缩小画布", "minus", "zoom_out").disabled(classroom.canvasZoom <= 0.5)
            Button("\(Int((classroom.canvasZoom * 100).rounded()))%") { classroom.canvasCommand("reset_zoom") }
                .monospacedDigit().frame(width: 44).help("复位到 100%")
                .accessibilityLabel("复位画布缩放")
                .accessibilityValue("\(Int((classroom.canvasZoom * 100).rounded()))%")
            tool("放大画布", "plus", "zoom_in").disabled(classroom.canvasZoom >= 2)
            tool("适应板书宽度", "arrow.left.and.right", "fit_page")
            Divider().frame(height: 16)
            Button { classroom.canvasCommand("toggle_ink") } label: {
                Label("手写", systemImage: classroom.handwriting ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
            }.foregroundStyle(classroom.handwriting ? WeiBeiTheme.cinnabar : WeiBeiTheme.ink)
                .help(classroom.handwriting ? "关闭手写，恢复自动跟随" : "在板面上书写，暂停自动跟随")
                .accessibilityValue(classroom.handwriting ? "已开启" : "已关闭")
            Spacer(minLength: 0)
            if classroom.canvasPageCount > 1 {
                tool("上一页板书", "chevron.left", "previous_page").disabled(classroom.canvasPage == 0)
                Text("\(classroom.canvasPage + 1)/\(classroom.canvasPageCount)").font(.caption).monospacedDigit()
                tool("下一页板书", "chevron.right", "next_page").disabled(classroom.canvasPage + 1 >= classroom.canvasPageCount)
            }
            tool("撤销上一笔", "arrow.uturn.backward", "undo").disabled(!classroom.canUndoInk)
            tool("清空本页笔迹", "eraser", "clear_page").disabled(!classroom.canUndoInk)
        }.buttonStyle(.borderless).font(.callout).padding(.horizontal, 16).padding(.vertical, 8)
    }
    private func tool(_ label: String, _ icon: String, _ command: String) -> some View {
        Button { classroom.canvasCommand(command) } label: { Image(systemName: icon).frame(width: 22, height: 24) }
            .help(label).accessibilityLabel(label)
    }
}
