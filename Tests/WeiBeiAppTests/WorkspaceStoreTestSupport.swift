import Foundation
import XCTest
@testable import WeiBei
import WeiBeiCore

@MainActor
class WorkspaceStoreTestCase: XCTestCase {
    /**
     * 创建当前测试独占的真实临时工作区。
     *
     * @returns 已存在的空目录
     */
    func makeTemporaryWorkspace() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiAppTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    /**
     * 在临时工作区内写入测试文件。
     *
     * @param name - 文件名
     * @param contents - UTF-8 文件内容
     * @param directory - 测试工作区
     * @returns 写入后的文件 URL
     */
    func writeFile(named name: String, contents: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /**
     * 构造不依赖网络或用户目录的 WorkspaceStore。
     *
     * @param directory - Store 使用的独占工作区
     * @returns 已完成加载的 Store
     */
    func makeStore(
        in directory: URL,
        modelListFetcher: @escaping (ModelListStrategy, String) async throws -> [String] = { _, _ in [] },
        agentRequestExecutor: ((StudyAgentRequest) async throws -> StudyAgentReply)? = nil
    ) -> WorkspaceStore {
        let profile = AgentCredentialProfile(name: "Test", provider: .openai)
        return WorkspaceStore(
            workspaceDirectory: directory,
            credentialProfiles: [profile],
            activeCredentialProfileID: profile.id,
            storedAPIKeyResolver: { "" },
            modelListFetcher: modelListFetcher,
            agentRequestExecutor: agentRequestExecutor
        )
    }
}
