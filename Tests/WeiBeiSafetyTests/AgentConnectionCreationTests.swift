import Foundation
import XCTest
@testable import WeiBei
@testable import WeiBeiCore

final class AgentConnectionCreationTests: XCTestCase {
    private let preferenceKeys = [
        "weibei.agentCredentialProfiles.v1",
        "weibei.agentCredentialActiveProfileID.v1",
    ]
    private var savedPreferences: [Any?] = []
    private var storeFixture: (store: WorkspaceStore, root: URL)?

    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        precondition(Thread.isMainThread)
        savedPreferences = preferenceKeys.map { UserDefaults.standard.object(forKey: $0) }
        storeFixture = try MainActor.assumeIsolated {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("WeiBeiConnectionCreation-\(UUID().uuidString)")
            let store = WorkspaceStore(
                workspaceDirectory: root,
                startsAtBlankEntries: true,
                startsCourseFileMaintenance: false
            )
            let original = AgentCredentialProfile(
                name: "Synthetic original",
                provider: .custom,
                modelName: "synthetic-model",
                baseURL: "https://old-gateway.example.test/v1"
            )
            store.agentCredentialProfiles = [original]
            AgentCredentialProfileStore.saveProfiles([original])
            store.selectAgentCredentialProfile(original.id)
            return (store, root)
        }
    }

    override func tearDownWithError() throws {
        let root = storeFixture?.root
        storeFixture = nil
        for (key, value) in zip(preferenceKeys, savedPreferences) {
            UserDefaults.standard.set(value, forKey: key)
        }
        if let root { try? FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

    @MainActor
    private func assertRejected(
        provider: AgentProviderID,
        baseURL: String,
        expectedError: AgentProviderEndpointError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let store = try XCTUnwrap(storeFixture, file: file, line: line).store
        let profiles = store.agentCredentialProfiles
        let active = store.activeAgentProfileID
        let providerBefore = store.agentProviderID
        let urlBefore = store.agentBaseURL
        let modelBefore = store.modelName
        let authBefore = store.agentAuthMethod
        let persisted = UserDefaults.standard.data(forKey: preferenceKeys[0])
        XCTAssertThrowsError(
            try store.createAgentConnection(provider: provider, authMethod: .apiKey, baseURL: baseURL),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? AgentProviderEndpointError, expectedError, file: file, line: line)
        }
        XCTAssertEqual(store.agentCredentialProfiles, profiles, file: file, line: line)
        XCTAssertEqual(store.activeAgentProfileID, active, file: file, line: line)
        XCTAssertEqual(store.agentProviderID, providerBefore, file: file, line: line)
        XCTAssertEqual(store.agentBaseURL, urlBefore, file: file, line: line)
        XCTAssertEqual(store.modelName, modelBefore, file: file, line: line)
        XCTAssertEqual(store.agentAuthMethod, authBefore, file: file, line: line)
        XCTAssertEqual(UserDefaults.standard.data(forKey: preferenceKeys[0]), persisted, file: file, line: line)
        XCTAssertEqual(AgentCredentialProfileStore.activeProfileID(), active, file: file, line: line)
    }

    @MainActor
    func testBlankRequiredURLsLeaveOriginalConnectionUntouched() throws {
        let store = try XCTUnwrap(storeFixture).store
        for previous in [AgentProviderID.custom, .azureOpenAI] {
            store.setAgentProviderID(previous)
            store.updateAgentBaseURL(previous == .custom
                ? "https://old-gateway.example.test/v1" : "https://old-resource.openai.azure.com")
            for provider in [AgentProviderID.azureOpenAI, .custom, .llamaCpp,
                             .googleVertex, .cloudflareAIGateway, .cloudflareWorkersAI] {
                for url in ["", "  \n "] {
                    try assertRejected(provider: provider, baseURL: url, expectedError: .missing)
                }
            }
        }
    }

    @MainActor
    func testInvalidURLsLeaveOriginalConnectionUntouched() throws {
        let store = try XCTUnwrap(storeFixture).store
        for previous in [AgentProviderID.custom, .azureOpenAI] {
            store.setAgentProviderID(previous)
            store.updateAgentBaseURL(previous == .custom
                ? "https://old-gateway.example.test/v1" : "https://old-resource.openai.azure.com")
            for provider in [AgentProviderID.azureOpenAI, .custom] {
                for url in ["not a URL", "https://user:synthetic@example.test/v1",
                            "https://example.test/v1?token=synthetic", "https://example.test/v1#fragment"] {
                    try assertRejected(provider: provider, baseURL: url, expectedError: .invalid)
                }
                try assertRejected(
                    provider: provider,
                    baseURL: "http://public.example.test/v1",
                    expectedError: .insecurePublicHTTP
                )
            }
        }
    }

    @MainActor
    func testAzureCredentialRequestUsesOnlyTheIntentionallyEnteredEndpoint() async throws {
        let fixture = try XCTUnwrap(storeFixture)
        let store = fixture.store
        let original = store.agentCredentialProfiles[0]
        let id = try store.createAgentConnection(
            provider: .azureOpenAI,
            authMethod: .apiKey,
            baseURL: "  HTTPS://Resource-B.openai.azure.com:443/  "
        )
        XCTAssertEqual(store.activeAgentProfileID, id)
        XCTAssertEqual(store.agentProviderID, .azureOpenAI)
        XCTAssertEqual(store.agentBaseURL, "https://resource-b.openai.azure.com")
        XCTAssertEqual(store.agentCredentialProfiles[0], original)
        let endpoint = try AgentProviderEndpoint(provider: store.agentProviderID, baseURL: store.agentBaseURL)
        let credentials = NativeAgentCredentialStore(fileURL: fixture.root.appendingPathComponent("synthetic-credentials.json"))
        try credentials.upsert(NativeAgentCredentialRecord(
            provider: endpoint.credentialProviderID,
            apiKey: "synthetic-new-key",
            boundEndpoint: endpoint.baseURL
        ))
        let adapter = try await NativeLLMAdapterFactory.make(
            provider: .azureOpenAI,
            model: "synthetic-deployment",
            endpoint: endpoint,
            authMethod: .apiKey,
            credentialStore: credentials
        )
        let responses = try XCTUnwrap(adapter as? OpenAIResponsesProvider)
        let request = responses.makeURLRequest(NativeLLMRequest(model: "synthetic-deployment", messages: []))
        XCTAssertEqual(request.url?.host, "resource-b.openai.azure.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "api-key"), "synthetic-new-key")
        XCTAssertEqual(try credentials.load()[endpoint.credentialProviderID]?.boundEndpoint, store.agentBaseURL)
        XCTAssertNotEqual(request.url?.host, URL(string: original.baseURL)?.host)
        // Request construction only: no URLSession or provider stream is executed.
    }

    @MainActor
    func testCustomCredentialRequestDoesNotUseThePreviousAzureEndpoint() async throws {
        let fixture = try XCTUnwrap(storeFixture)
        let store = fixture.store
        store.setAgentProviderID(.azureOpenAI)
        store.updateAgentBaseURL("https://old-resource.openai.azure.com")
        let original = store.agentCredentialProfiles[0]
        try store.createAgentConnection(
            provider: .custom,
            authMethod: .apiKey,
            baseURL: "https://new-gateway.example.test/v1/"
        )
        XCTAssertEqual(store.agentBaseURL, "https://new-gateway.example.test/v1")
        XCTAssertEqual(store.agentCredentialProfiles[0], original)
        let endpoint = try AgentProviderEndpoint(provider: .custom, baseURL: store.agentBaseURL)
        let credentials = NativeAgentCredentialStore(fileURL: fixture.root.appendingPathComponent("synthetic-credentials.json"))
        try credentials.upsert(NativeAgentCredentialRecord(
            provider: endpoint.credentialProviderID,
            apiKey: "synthetic-custom-key",
            boundEndpoint: endpoint.baseURL
        ))
        let adapter = try await NativeLLMAdapterFactory.make(
            provider: .custom,
            model: "synthetic-model",
            endpoint: endpoint,
            authMethod: .apiKey,
            credentialStore: credentials
        )
        let completions = try XCTUnwrap(adapter as? OpenAIChatCompletionsProvider)
        let request = try completions.makeURLRequest(NativeLLMRequest(model: "synthetic-model", messages: []))
        XCTAssertEqual(request.url?.host, "new-gateway.example.test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-custom-key")
        XCTAssertNotEqual(request.url?.host, URL(string: original.baseURL)?.host)
    }

    @MainActor
    func testSameProviderNewConnectionDoesNotCloneItsEndpoint() throws {
        let store = try XCTUnwrap(storeFixture).store
        let original = store.agentCredentialProfiles[0]
        try store.createAgentConnection(provider: .custom, authMethod: .apiKey, baseURL: "http://127.0.0.1:18080/v1/")
        XCTAssertEqual(store.agentBaseURL, "http://127.0.0.1:18080/v1")
        XCTAssertEqual(store.modelName, original.modelName)
        XCTAssertEqual(store.agentCredentialProfiles[0], original)
        XCTAssertEqual(AgentCredentialProfileStore.loadProfiles().last?.baseURL, store.agentBaseURL)
    }

    @MainActor
    func testSwitchingToBuiltInProvidersClearsThePreviousEndpoint() throws {
        let store = try XCTUnwrap(storeFixture).store
        let original = store.agentCredentialProfiles[0]
        for (provider, auth) in [(AgentProviderID.openai, AgentAuthMethod.apiKey), (.openaiCodex, .subscription)] {
            try store.createAgentConnection(provider: provider, authMethod: auth, baseURL: "")
            XCTAssertEqual(store.agentBaseURL, "")
            XCTAssertEqual(store.agentAuthMethod, auth)
            let endpoint = try AgentProviderEndpoint(provider: provider, baseURL: store.agentBaseURL)
            XCTAssertEqual(NativeProviderRouting.resolvedBaseURL(provider: provider, endpoint: endpoint), NativeProviderRouting.route(provider).baseURL)
        }
        XCTAssertEqual(store.agentCredentialProfiles[0], original)
    }

    @MainActor
    func testOptionalEndpointUsesItsDefaultOrTheExplicitNewURL() throws {
        let store = try XCTUnwrap(storeFixture).store
        try store.createAgentConnection(provider: .amazonBedrock, authMethod: .apiKey, baseURL: "")
        XCTAssertEqual(store.agentBaseURL, "")
        let defaultEndpoint = try AgentProviderEndpoint(provider: .amazonBedrock, baseURL: store.agentBaseURL)
        XCTAssertEqual(NativeProviderRouting.resolvedBaseURL(provider: .amazonBedrock, endpoint: defaultEndpoint), NativeProviderRouting.route(.amazonBedrock).baseURL)
        try store.createAgentConnection(
            provider: .amazonBedrock,
            authMethod: .apiKey,
            baseURL: "https://bedrock-runtime.eu-west-1.amazonaws.com/openai/v1/"
        )
        XCTAssertEqual(store.agentBaseURL, "https://bedrock-runtime.eu-west-1.amazonaws.com/openai/v1")
    }

    @MainActor
    func testRejectedDraftCanBeCorrectedWithoutChangingTheOriginalProfile() throws {
        let store = try XCTUnwrap(storeFixture).store
        let original = store.agentCredentialProfiles[0]
        try assertRejected(provider: .azureOpenAI, baseURL: "", expectedError: .missing)
        let id = try store.createAgentConnection(provider: .azureOpenAI, authMethod: .apiKey, baseURL: "https://corrected.openai.azure.com")
        XCTAssertEqual(store.agentCredentialProfiles.count, 2)
        XCTAssertEqual(store.agentCredentialProfiles[0], original)
        XCTAssertEqual(store.activeAgentProfileID, id)
        XCTAssertEqual(store.agentBaseURL, "https://corrected.openai.azure.com")
    }

    @MainActor
    func testLoginCompletionPersistsWithoutSettingsAndKeepsTheCurrentCardsRunAlive() throws {
        let store = try XCTUnwrap(storeFixture).store
        let target = try store.createAgentConnection(provider: .xai, authMethod: .apiKey, baseURL: "")
        let current = try store.createAgentConnection(provider: .openai, authMethod: .apiKey, baseURL: "")
        let currentRunID = UUID()
        let currentTask = Task<Void, Never> {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
        }
        defer { currentTask.cancel() }
        let currentRun = AgentConversationRun(chatID: currentRunID)
        currentRun.agentRequestTask = currentTask
        store.agentRuns[currentRunID] = currentRun

        XCTAssertTrue(store.completeAgentSubscriptionLogin(provider: .xai, profileID: target))

        XCTAssertEqual(store.activeAgentProfileID, current)
        XCTAssertEqual(store.agentProviderID, .openai)
        XCTAssertEqual(store.agentAuthMethod, .apiKey)
        XCTAssertEqual(store.agentCredentialProfiles.first(where: { $0.id == target })?.authMethod, .subscription)
        XCTAssertEqual(store.agentCredentialProfiles.first(where: { $0.id == current })?.authMethod, .apiKey)
        XCTAssertFalse(currentTask.isCancelled)
    }

    @MainActor
    func testLoginCompletionRejectsDeletedOrChangedTargetsWithoutTouchingCurrentCard() throws {
        let store = try XCTUnwrap(storeFixture).store
        let deleted = try store.createAgentConnection(provider: .xai, authMethod: .apiKey, baseURL: "")
        let changed = try store.createAgentConnection(provider: .xai, authMethod: .apiKey, baseURL: "")
        let current = try store.createAgentConnection(provider: .openai, authMethod: .apiKey, baseURL: "")
        store.agentCredentialProfiles.removeAll { $0.id == deleted }
        let changedIndex = try XCTUnwrap(store.agentCredentialProfiles.firstIndex { $0.id == changed })
        store.agentCredentialProfiles[changedIndex].provider = .anthropic
        AgentCredentialProfileStore.saveProfiles(store.agentCredentialProfiles)

        XCTAssertFalse(store.completeAgentSubscriptionLogin(provider: .xai, profileID: deleted))
        XCTAssertFalse(store.completeAgentSubscriptionLogin(provider: .xai, profileID: changed))

        XCTAssertEqual(store.activeAgentProfileID, current)
        XCTAssertEqual(store.agentProviderID, .openai)
        XCTAssertEqual(store.agentAuthMethod, .apiKey)
        XCTAssertFalse(store.agentCredentialProfiles.contains(where: { $0.id == deleted }))
        XCTAssertEqual(store.agentCredentialProfiles.first(where: { $0.id == changed })?.provider, .anthropic)
        XCTAssertEqual(store.agentCredentialProfiles.first(where: { $0.id == changed })?.authMethod, .apiKey)
    }
}
