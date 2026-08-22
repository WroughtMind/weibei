import Foundation
import WeiBeiCore

enum NativeEvalCLI {
    static func runIfRequested(arguments: [String]) async -> Bool {
        guard arguments.contains("--native-eval") else { return false }
        do {
            try await run(arguments: arguments)
        } catch {
            fputs("native-eval failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
        return true
    }

    static func run(arguments: [String]) async throws {
        let store = try NativeAgentCredentialStore.defaultStore()
        let signedIn = try NativeOpenAIOAuth.leftoverCredentialExists(in: store)
        let model = ProcessInfo.processInfo.environment["WEIBEI_NATIVE_EVAL_MODEL"] ?? "gpt-5.6-luna"
        let effort = ProcessInfo.processInfo.environment["WEIBEI_NATIVE_EVAL_EFFORT"] ?? "low"
        let setURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Docs/audit/2026-08-22-native-agent-runtime-评测集.json")
        let data = try Data(contentsOf: setURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["items"] as? [[String: Any]] else {
            throw NSError(domain: "WeiBei.NativeEval", code: 1, userInfo: [NSLocalizedDescriptionKey: "eval set JSON missing items"])
        }
        print("native-eval model=\(model) effort=\(effort) items=\(items.count) signed-in=\(signedIn)")
        guard signedIn else {
            print("native-eval skipped live ChatGPT run: native oauth is signed-out. Re-login then rerun --native-eval.")
            return
        }
        let limit: Int
        if let index = arguments.firstIndex(of: "--limit"),
           let raw = arguments.dropFirst(index + 1).first,
           let parsed = Int(raw) {
            limit = parsed
        } else {
            limit = items.count
        }
        let endpoint = try AgentProviderEndpoint(provider: .openaiCodex, baseURL: "")
        let adapter = try await NativeLLMAdapterFactory.make(
            provider: .openaiCodex,
            model: model,
            endpoint: endpoint
        )
        let skillRoot = try? PiAgentResources.bundled().skillsURL
        let liveStores = NativeLiveStores(
            skillRegistry: skillRoot.flatMap { try? NativeSkillRegistry.load(from: $0) } ?? NativeSkillRegistry()
        )
        var ran = 0
        for item in items.prefix(limit) {
            let id = item["id"] as? String ?? "?"
            let scene = item["scene"] as? String ?? ""
            let question = item["question"] as? String ?? ""
            if scene == "cancel" || scene == "error" {
                print("native-eval \(id) skipped scene=\(scene)")
                continue
            }
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-eval-\(id)-\(UUID().uuidString)")
            let runtime = NativeStudyAgentRuntime(
                model: model,
                adapter: adapter,
                ledgerRoot: root,
                systemPromptText: (try? PiAgentResources.bundled().systemPrompt) ?? "you are webi",
                liveStores: liveStores
            )
            let reply = try await runtime.respond(
                to: StudyAgentRequest(
                    purpose: .conversation,
                    question: question,
                    materialTitle: "利率课程",
                    materialText: "利率是资金使用价格的表达。",
                    noteTitle: "",
                    noteText: "",
                    contextRevision: "eval-\(id)"
                ),
                progress: nil
            )
            let prefix = reply.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)
            print("native-eval \(id) scene=\(scene) tools=\(reply.toolTrace.joined(separator: ",")) prefix=\(prefix)")
            ran += 1
        }
        _ = effort
        print("native-eval live-ran=\(ran) model=\(model) effort=low")
    }
}
