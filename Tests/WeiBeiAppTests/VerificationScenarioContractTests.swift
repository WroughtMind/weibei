import XCTest
@testable import WeiBei
@testable import WeiBeiDevCore

final class VerificationScenarioContractTests: XCTestCase {
    /// 保证应用 fixture 与开发工具的 Rich Answer 场景注册表不会独立漂移。
    func testRichAnswerFixtureMatchesDevelopmentToolRegistry() {
        let registeredScenarios = Set(
            VerificationScenarioRegistry().scenarios
                .map(\.id.rawValue)
                .filter { $0.hasPrefix("rich-answer-") }
        )

        XCTAssertEqual(RichAnswerVerificationFixture.supportedScenarios, registeredScenarios)
        XCTAssertTrue(registeredScenarios.allSatisfy(RichAnswerVerificationFixture.supports))
    }
}
