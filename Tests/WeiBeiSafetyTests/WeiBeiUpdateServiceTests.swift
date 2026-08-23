import XCTest
@testable import WeiBei

final class WeiBeiUpdateServiceTests: XCTestCase {
    func testReleaseNotesSummaryKeepsLateCriticalSectionsAndFullText() {
        let notes = """
        <h2>本次更新</h2><ul><li>顶部栏显示下载入口</li><li>设置页共用更新状态</li><li>下载完成后自动安装</li><li>安装前保存工作区</li><li>失败后可以重试</li></ul>
        <h2>破坏性变化</h2><ul><li>旧版快捷键不再占用编辑器</li><li>旧工具名停止注册</li></ul>
        <h2>迁移</h2><ul><li>人工会话标题自动保留</li><li>旧快捷键配置会显示冲突</li></ul>
        <h2>已知问题</h2><ul><li>首次展开可能稍慢</li><li>第二项已知问题仍会显示</li></ul>
        """

        XCTAssertEqual(
            WeiBeiAvailableUpdate.summaryLines(from: notes),
            [
                "破坏性变化：旧版快捷键不再占用编辑器",
                "破坏性变化：旧工具名停止注册",
                "迁移：人工会话标题自动保留",
                "迁移：旧快捷键配置会显示冲突",
                "已知问题：首次展开可能稍慢",
                "已知问题：第二项已知问题仍会显示",
            ]
        )
        let update = WeiBeiAvailableUpdate(
            version: "1.2.3",
            releaseNotesLines: WeiBeiAvailableUpdate.releaseNotesLines(from: notes),
            informationOnly: false,
            informationURL: nil
        )
        XCTAssertTrue(update.helpText.contains("已知问题：第二项已知问题仍会显示"))
    }
}
