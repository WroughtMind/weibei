import Darwin
import Foundation
import WeiBeiCore

@main
struct WeiBeiPiCheckMain {
    static func main() async {
        let environment = ProcessInfo.processInfo.environment

        if CommandLine.arguments.contains("--authentication-status") {
            var status = AgentAuthenticationStatus()
            status.recordFailure(
                .offline,
                provider: .openaiCodex,
                authMethod: .subscription
            )
            status.recordFailure(
                .unauthorized,
                provider: .openaiCodex,
                authMethod: .apiKey
            )
            guard !status.requiresLogin(for: .openaiCodex) else {
                fputs("authentication-status-check failed: 非 OAuth 失效被误判为需要登录\n", stderr)
                exit(1)
            }
            status.recordFailure(
                .unauthorized,
                provider: .openaiCodex,
                authMethod: .subscription
            )
            guard status.requiresLogin(for: .openaiCodex) else {
                fputs("authentication-status-check failed: OAuth 认证失败后仍显示已连接\n", stderr)
                exit(1)
            }
            guard !status.requiresLogin(for: .anthropic) else {
                fputs("authentication-status-check failed: 一个服务失效误伤其他服务\n", stderr)
                exit(1)
            }
            status.recordSuccess(provider: .openaiCodex, authMethod: .subscription)
            guard !status.requiresLogin(for: .openaiCodex) else {
                fputs("authentication-status-check failed: 重新登录成功后仍要求登录\n", stderr)
                exit(1)
            }
            print("authentication-status-check passed")
            return
        }

        let liveCheckSetting = environment["WEIBEI_PI_LIVE_CHECK"] ?? "auto"
        let runsEvaluation = environment["WEIBEI_PI_EVAL"] == "1"
        let explicitPath = environment["WEIBEI_PI_EXECUTABLE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let executableURL = explicitPath.isEmpty
            ? PiExecutableLocator.locate()
            : URL(fileURLWithPath: explicitPath)
        let containingAppPath = environment["WEIBEI_PI_APP_BUNDLE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let containingAppURL = containingAppPath.isEmpty ? nil : URL(fileURLWithPath: containingAppPath)

        guard let executableURL else {
            fputs("pi-check failed: embedded PI runtime not found\n", stderr)
            exit(1)
        }

        if CommandLine.arguments.contains("--management-protocol") {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("weibei-pi-management-check-\(UUID().uuidString)", isDirectory: true)
            let piAgentURL = root.appendingPathComponent("PiAgent", isDirectory: true)
            let remoteCatalogCacheURL = piAgentURL.appendingPathComponent("models-store.json")
            let runtime = PiAgentRuntime(
                executableURL: executableURL,
                runtimeDirectory: root.appendingPathComponent("Runtime", isDirectory: true),
                persistentPiConfigurationDirectory: piAgentURL
            )
            do {
                try FileManager.default.createDirectory(at: piAgentURL, withIntermediateDirectories: true)
                try Data(#"{"remote-catalog-cache":"must-not-survive"}"#.utf8)
                    .write(to: remoteCatalogCacheURL, options: .atomic)
                let catalog = try await runtime.managementCatalog()
                let selectableProviderIDs = Set(AgentProviderID.allCases.map(\.piProviderName))
                let missingProviderIDs = catalog.providers
                    .map(\.id)
                    .filter { !selectableProviderIDs.contains($0) }
                let providersWithoutAuth = catalog.providers
                    .filter(\.authTypes.isEmpty)
                    .map(\.id)
                let modelProviderIDs = Set(catalog.models.map(\.providerId))
                let providersWithoutModels = catalog.providers
                    .filter { !$0.authTypes.contains(.oauth) }
                    .map(\.id)
                    .filter { !modelProviderIDs.contains($0) }
                guard catalog.providers.count >= 30,
                      catalog.models.count >= 500,
                      missingProviderIDs.isEmpty,
                      providersWithoutAuth.isEmpty,
                      providersWithoutModels.isEmpty,
                      catalog.providers.contains(where: {
                          $0.id == "openai" && $0.authTypes.contains(.apiKey)
                      }),
                      catalog.providers.contains(where: {
                          $0.id == "openai-codex" && $0.authTypes.contains(.oauth)
                      }),
                      catalog.credentials.isEmpty,
                      !FileManager.default.fileExists(atPath: remoteCatalogCacheURL.path) else {
                    throw PiAgentRuntimeError.protocolFailure(
                        "PI management catalog was incomplete; missing=\(missingProviderIDs.joined(separator: ",")) no-auth=\(providersWithoutAuth.joined(separator: ",")) no-models=\(providersWithoutModels.joined(separator: ","))"
                    )
                }
                let bedrockCredential = try await runtime.login(
                    providerID: "amazon-bedrock",
                    type: .apiKey,
                    interaction: PiManagementInteraction(
                        prompt: { prompt in
                            switch prompt.type {
                            case .select:
                                guard prompt.options?.contains(where: { $0.id == "aws-profile" }) == true else {
                                    throw PiAgentRuntimeError.protocolFailure("PI Bedrock login options were incomplete")
                                }
                                return "aws-profile"
                            case .text:
                                return "weibei-pi-check-profile"
                            default:
                                throw PiAgentRuntimeError.protocolFailure("PI Bedrock login requested unexpected input")
                            }
                        },
                        notify: { _ in }
                    )
                )
                guard bedrockCredential.providerId == "amazon-bedrock",
                      bedrockCredential.type == .apiKey,
                      try await runtime.managementCatalog().credentials.contains(where: {
                          $0.providerId == "amazon-bedrock" && $0.type == .apiKey
                      }) else {
                    throw PiAgentRuntimeError.protocolFailure("PI multi-step API login did not persist")
                }
                try await runtime.logout(providerID: "amazon-bedrock")
                let credential = try await runtime.login(
                    providerID: "openai",
                    type: .apiKey,
                    interaction: PiManagementInteraction(
                        prompt: { _ in "weibei-pi-check-key" },
                        notify: { _ in }
                    )
                )
                guard credential.providerId == "openai", credential.type == .apiKey,
                      try await runtime.managementCatalog().credentials.contains(where: {
                          $0.providerId == "openai" && $0.type == .apiKey
                      }) else {
                    throw PiAgentRuntimeError.protocolFailure("PI API-key login did not persist")
                }
                let authURL = piAgentURL.appendingPathComponent("auth.json")
                let directoryMode = (try FileManager.default.attributesOfItem(atPath: piAgentURL.path)[.posixPermissions] as? NSNumber)?.intValue
                let authMode = (try FileManager.default.attributesOfItem(atPath: authURL.path)[.posixPermissions] as? NSNumber)?.intValue
                guard directoryMode == 0o700, authMode == 0o600 else {
                    throw PiAgentRuntimeError.protocolFailure("PI credential permissions were not private")
                }
                try await runtime.logout(providerID: "openai")
                let azureEndpoint = "https://weibei-check.openai.azure.com/openai/v1"
                let azureCredential = try await runtime.login(
                    providerID: AgentProviderID.azureOpenAI.piProviderName,
                    type: .apiKey,
                    endpoint: azureEndpoint,
                    interaction: PiManagementInteraction(
                        prompt: { _ in "weibei-pi-check-azure-key" },
                        notify: { _ in }
                    )
                )
                let azureCatalog = try await runtime.managementCatalog()
                let azureAuth = try Data(contentsOf: authURL)
                let azureAuthObject = try JSONSerialization.jsonObject(with: azureAuth)
                    as? [String: Any]
                let storedAzureCredential = azureAuthObject?[AgentProviderID.azureOpenAI.piProviderName]
                    as? [String: Any]
                let storedAzureEnvironment = storedAzureCredential?["env"] as? [String: String]
                guard azureCredential.providerId == AgentProviderID.azureOpenAI.piProviderName,
                      azureCredential.type == .apiKey,
                      azureCredential.boundEndpoint == azureEndpoint,
                      azureCatalog.credentials.contains(where: {
                          $0.providerId == AgentProviderID.azureOpenAI.piProviderName
                              && $0.type == .apiKey
                              && $0.boundEndpoint == azureEndpoint
                      }),
                      storedAzureEnvironment?["AZURE_OPENAI_BASE_URL"] == azureEndpoint else {
                    throw PiAgentRuntimeError.protocolFailure(
                        "PI Azure credential did not retain its endpoint binding"
                    )
                }
                try await runtime.logout(providerID: AgentProviderID.azureOpenAI.piProviderName)
                let postLogoutCatalog = try await runtime.managementCatalog()
                let auth = try Data(contentsOf: authURL)
                let authObject = try JSONSerialization.jsonObject(with: auth) as? [String: Any]
                guard postLogoutCatalog.credentials.isEmpty,
                      authObject?.isEmpty == true else {
                    throw PiAgentRuntimeError.protocolFailure("PI logout did not remove the credential")
                }
                await runtime.shutdown()
                try? FileManager.default.removeItem(at: root)
                print(
                    "pi-management-check passed: providers=\(catalog.providers.count) models=\(catalog.models.count) multi-step-login=passed api-key-login=passed azure-binding=passed logout=passed"
                )
                return
            } catch {
                await runtime.shutdown()
                try? FileManager.default.removeItem(at: root)
                fputs("pi-management-check failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }

        let runtimeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-pi-check-\(UUID().uuidString)", isDirectory: true)
        let piAgentRoot = runtimeRoot.appendingPathComponent("PiAgent", isDirectory: true)
        let runtime = PiAgentRuntime(
            executableURL: executableURL,
            runtimeDirectory: runtimeRoot,
            persistentPiConfigurationDirectory: piAgentRoot
        )

        do {
            let manifest = try PiBundledRuntime.validate(
                executableURL: executableURL,
                containingAppURL: containingAppURL
            )
            let launchedPath = try await runtime.healthCheck()
            guard FileManager.default.fileExists(atPath: piAgentRoot.path) else {
                throw PiCheckError.missingIsolatedConfiguration
            }
            print("pi-check ready: PI \(manifest.piVersion) at \(launchedPath)")

            let isolatedAuth = piAgentRoot.appendingPathComponent("auth.json")
            let hasConfiguredAuth = ((try? isolatedAuth.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 2
            let runsLiveCheck = runsEvaluation
                || liveCheckSetting == "1"
                || (liveCheckSetting != "0" && hasConfiguredAuth)
            var expectedSessionID: UUID?
            if runsLiveCheck {
                expectedSessionID = try await checkNoteMaking(runtime)
            }
            if runsEvaluation {
                try await checkStudyCompanion(runtime)
                try await checkCourseWayfinding(runtime)
                try await checkCloseReading(runtime)
                try await checkRecallPractice(runtime)
                print("pi-eval completed: study-companion, course-wayfinding, close-reading, note-making, recall-practice")
            }
            await runtime.shutdown()
            try verifyPersistedSessionStateAfterShutdown(
                runtimeRoot,
                expectedSessionID: expectedSessionID
            )
            try? FileManager.default.removeItem(at: runtimeRoot)
        } catch {
            await runtime.shutdown()
            try? FileManager.default.removeItem(at: runtimeRoot)
            fputs("pi-check failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func checkNoteMaking(_ runtime: PiAgentRuntime) async throws -> UUID {
        let liveRequest = request(
            question: "请把当前选区整理成一个带来源的 Markdown 核心要点，并提交待确认的笔记建议。",
            revision: "pi-check-note"
        )
        let reply = try await runtime.respond(to: liveRequest)
        guard reply.backend == .pi,
              !reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let proposal = reply.noteProposal,
              proposal.contextRevision == "pi-check-note",
              !proposal.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !proposal.evidence.isEmpty else {
            throw PiCheckError.invalidLiveReply
        }
        print("pi-live-check passed: proposal=\(proposal.markdown.count) chars evidence=\(proposal.evidence.count)")
        return liveRequest.id
    }

    private static func checkCloseReading(_ runtime: PiAgentRuntime) async throws {
        let reply = try await runtime.respond(
            to: request(
                question: "只根据当前内容解释为什么利率可称为资金价格，并标明来源。",
                revision: "pi-check-reading"
            )
        )
        guard reply.backend == .pi,
              reply.noteProposal == nil,
              reply.text.contains("资金"),
              containsSourceLabel(reply.text) else {
            throw PiCheckError.invalidEvaluation("close-reading")
        }
    }

    private static func checkStudyCompanion(_ runtime: PiAgentRuntime) async throws {
        let reply = try await runtime.respond(
            to: request(
                question: "我上次学到哪了？请告诉我位置和下一步。",
                revision: "pi-check-companion"
            )
        )
        guard reply.backend == .pi,
              reply.text.contains("期限结构") || reply.text.contains("第 12 页") || reply.text.contains("第12页"),
              reply.text.contains("[学习记录：上次位置]") else {
            throw PiCheckError.invalidEvaluation("study-companion")
        }
    }

    private static func checkCourseWayfinding(_ runtime: PiAgentRuntime) async throws {
        let reply = try await runtime.respond(
            to: request(
                question: "利率和通货膨胀在课程里有哪份相关材料？说明关联，并原样给出工具返回的最精确 PDF 页码跳转。",
                revision: "pi-check-wayfinding"
            )
        )
        guard reply.backend == .pi,
              reply.text.contains("通货膨胀补充材料"),
              reply.text.contains("来源：通货膨胀补充材料，第 4 页"),
              containsSourceLabel(reply.text) else {
            throw PiCheckError.invalidEvaluation("course-wayfinding")
        }
    }

    private static func checkRecallPractice(_ runtime: PiAgentRuntime) async throws {
        let reply = try await runtime.respond(
            to: request(
                question: "只根据当前内容出 2 道复习题，并给出带来源的答案。",
                revision: "pi-check-recall"
            )
        )
        guard reply.backend == .pi,
              reply.noteProposal == nil,
              reply.text.contains("？") || reply.text.contains("?"),
              containsSourceLabel(reply.text) else {
            throw PiCheckError.invalidEvaluation("recall-practice")
        }
    }

    private static func request(
        question: String,
        revision: String
    ) -> StudyAgentRequest {
        StudyAgentRequest(
            purpose: .conversation,
            question: question,
            materialTitle: "利率课程",
            materialText: "利率是资金使用价格的表达。名义利率以货币单位表示，实际利率扣除了通货膨胀后的购买力变化。在课程的近似计算中：实际利率 = 名义利率 - 通货膨胀率。",
            noteTitle: "课堂笔记",
            noteText: "# 利率\n\n## 待整理",
            selectionTitle: "利率定义",
            selectionText: "利率是资金使用价格的表达。",
            courseContext: StudyAgentCourseContext(
                title: "货币金融学",
                items: [
                    StudyAgentCourseItem(
                        id: "material-rates",
                        title: "利率课程",
                        subtitle: "利率讲义",
                        kind: "html",
                        role: "material",
                        isCurrentMaterial: true,
                        linkedItemIDs: ["note-rates"],
                        headings: ["利率的含义", "名义利率与实际利率"],
                        searchText: "利率是资金使用价格的表达。实际利率会扣除通货膨胀对购买力的影响。在课程的近似计算中：实际利率 = 名义利率 - 通货膨胀率。"
                    ),
                    StudyAgentCourseItem(
                        id: "material-inflation",
                        title: "通货膨胀补充材料",
                        subtitle: "PDF 第 4 章",
                        kind: "pdf",
                        role: "material",
                        headings: ["第 4 页", "购买力与实际利率"],
                        searchText: "通货膨胀会改变货币购买力，区分名义利率与实际利率时需要考虑通货膨胀。"
                    ),
                    StudyAgentCourseItem(
                        id: "note-rates",
                        title: "利率笔记",
                        subtitle: "Markdown",
                        kind: "markdown",
                        role: "note",
                        isCurrentNote: true,
                        linkedItemIDs: ["material-rates"],
                        headings: ["核心要点"],
                        searchText: "名义利率与实际利率的区别还需要复习。"
                    ),
                ],
                relations: [
                    StudyAgentCourseRelation(noteItemID: "note-rates", sourceItemID: "material-rates"),
                ]
            ),
            learningContext: StudyAgentLearningContext(
                memoryRevision: 3,
                lastLocation: StudyLocation(
                    itemID: "material-rates",
                    itemTitle: "利率课程",
                    locationTitle: "期限结构",
                    pageIndex: 11
                ),
                memories: [
                    LearningMemoryEntry(
                        kind: .confusion,
                        text: "还不能稳定区分名义利率与实际利率",
                        evidence: "[用户：本轮] 用户上次明确说这个区别还没掌握",
                        origin: .userStatement
                    ),
                ],
                session: StudyAgentSessionSnapshot(
                    id: "pi-check-session",
                    title: "利率复习",
                    summary: "上次学到期限结构，实际利率与通货膨胀的关系还需要复习。",
                    phase: StudyPhase.recall.rawValue,
                    focusItemIDs: ["material-rates", "note-rates"],
                    turnCount: 6
                )
            ),
            language: .chinese,
            contextRevision: revision
        )
    }

    private static func containsSourceLabel(_ text: String) -> Bool {
        text.contains("[选区：")
            || text.contains("[材料：")
            || text.contains("[笔记：")
            || text.contains("[学习记录：")
            || text.contains("[学习记忆：")
    }

    private static func verifyPersistedSessionStateAfterShutdown(
        _ runtimeRoot: URL,
        expectedSessionID: UUID?
    ) throws {
        let fileManager = FileManager.default
        let contextURL = runtimeRoot.appendingPathComponent("context.json")
        guard !fileManager.fileExists(atPath: contextURL.path) else {
            throw PiCheckError.persistedTurnState
        }
        guard let expectedSessionID else { return }
        let sessionDirectory = runtimeRoot
            .appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent(
                expectedSessionID.uuidString.lowercased(),
                isDirectory: true
            )
        let sessionFiles = try fileManager.contentsOfDirectory(
            at: sessionDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        )
        guard sessionFiles.contains(where: { url in
            guard let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            ) else {
                return false
            }
            return values.isRegularFile == true && (values.fileSize ?? 0) > 0
        }) else {
            throw PiCheckError.persistedTurnState
        }
    }
}

private enum PiCheckError: LocalizedError {
    case invalidLiveReply
    case invalidEvaluation(String)
    case missingIsolatedConfiguration
    case persistedTurnState

    var errorDescription: String? {
        switch self {
        case .invalidLiveReply:
            "PI returned no revision-matched note proposal"
        case let .invalidEvaluation(name):
            "PI evaluation failed: \(name)"
        case .missingIsolatedConfiguration:
            "PI did not use an isolated WeiBei configuration directory"
        case .persistedTurnState:
            "PI did not keep only durable per-Chat sessions after shutdown"
        }
    }
}
