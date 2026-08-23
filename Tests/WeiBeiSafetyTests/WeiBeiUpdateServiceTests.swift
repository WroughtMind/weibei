import XCTest
@testable import WeiBei

final class WeiBeiUpdateServiceTests: XCTestCase {
    func testReleaseNotesSummaryKeepsLateCriticalSectionsAndFullText() {
        let notes = """
        <h2>本次更新</h2><ul><li>顶部栏显示下载入口</li><li>设置页共用更新状态</li><li>下载完成后自动安装</li><li>安装前保存工作区</li><li>失败后可以重试</li></ul>
        <h2>破坏性变化</h2><ul><li>旧版快捷键不再占用编辑器</li></ul>
        <h2>迁移</h2><ul><li>人工会话标题自动保留</li></ul>
        <h2>已知问题</h2><ul><li>首次展开可能稍慢</li></ul>
        """

        XCTAssertEqual(
            WeiBeiAvailableUpdate.summaryLines(from: notes),
            [
                "本次更新",
                "顶部栏显示下载入口",
                "破坏性变化：旧版快捷键不再占用编辑器",
                "迁移：人工会话标题自动保留",
                "已知问题：首次展开可能稍慢",
            ]
        )
        XCTAssertEqual(
            WeiBeiAvailableUpdate.releaseNotesLines(from: notes).last,
            "首次展开可能稍慢"
        )
    }
}
