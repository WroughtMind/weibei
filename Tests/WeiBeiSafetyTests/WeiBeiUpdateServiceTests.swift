import XCTest
@testable import WeiBei

final class WeiBeiUpdateServiceTests: XCTestCase {
    func testSummaryKeepsCriticalReleaseNotesAvailableInFull() {
        let notes = """
        <ul><li>顶部栏显示下载入口</li><li>设置页共用更新状态</li></ul>
        - 下载完成后自动安装
        • 安装前保存工作区
        * 失败后可以重试
        <h2>破坏性变化</h2><p>旧格式不再写入</p>
        <h2>迁移</h2><p>首次启动会转换资料</p>
        <h2>已知问题</h2><p>离线时无法检查更新</p>
        """

        let allLines = WeiBeiAvailableUpdate.releaseNotesLines(from: notes)
        let summary = WeiBeiAvailableUpdate.summaryLines(from: notes)
        XCTAssertEqual(summary, Array(allLines.prefix(5)))
        XCTAssertEqual(
            Array(allLines.suffix(6)),
            [
                "破坏性变化", "旧格式不再写入",
                "迁移", "首次启动会转换资料",
                "已知问题", "离线时无法检查更新",
            ]
        )
        XCTAssertGreaterThan(allLines.count, summary.count)
    }
}
