import XCTest
@testable import WeiBei

final class WeiBeiUpdateServiceTests: XCTestCase {
    func testReleaseNotesBecomeFivePlainHoverLines() {
        let notes = """
        <ul><li>顶部栏显示下载入口</li><li>设置页共用更新状态</li></ul>
        - 下载完成后自动安装
        • 安装前保存工作区
        * 失败后可以重试
        第六条不会进入悬停摘要
        """

        XCTAssertEqual(
            WeiBeiAvailableUpdate.summaryLines(from: notes),
            [
                "顶部栏显示下载入口",
                "设置页共用更新状态",
                "下载完成后自动安装",
                "安装前保存工作区",
                "失败后可以重试",
            ]
        )
    }
}
