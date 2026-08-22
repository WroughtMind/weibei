import Darwin
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
        let model = ProcessInfo.processInfo.environment["WEIBEI_NATIVE_EVAL_MODEL"] ?? "gpt-5.6-luna"
        let effort = ProcessInfo.processInfo.environment["WEIBEI_NATIVE_EVAL_EFFORT"] ?? "low"
        let backend: String
        if let index = arguments.firstIndex(of: "--backend"),
           let raw = arguments.dropFirst(index + 1).first,
           !raw.hasPrefix("--") {
            backend = raw
        } else {
            backend = "native"
        }
        let setURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Docs/audit/2026-08-22-native-agent-runtime-评测集.json")
        let data = try Data(contentsOf: setURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["items"] as? [[String: Any]] else {
            throw NSError(domain: "WeiBei.NativeEval", code: 1, userInfo: [NSLocalizedDescriptionKey: "eval set JSON missing items"])
        }
        let limit: Int
        if let index = arguments.firstIndex(of: "--limit"),
           let raw = arguments.dropFirst(index + 1).first,
           let parsed = Int(raw) {
            limit = parsed
        } else {
            limit = items.count
        }
        let selected = Array(items.prefix(limit))
        print("native-eval backend=\(backend) model=\(model) effort=\(effort) items=\(selected.count)")
        fflush()
        switch backend {
        case "pi":
            try await runPi(items: selected, model: model, effort: effort)
        case "native":
            try await runNative(items: selected, model: model)
        default:
            throw NSError(domain: "WeiBei.NativeEval", code: 2, userInfo: [NSLocalizedDescriptionKey: "backend must be native or pi"])
        }
        _ = effort
    }

    private static func fflush() {
        Darwin.fflush(stdout)
    }

    private static func runNative(items: [[String: Any]], model: String) async throws {
        let store = try NativeAgentCredentialStore.defaultStore()
        let signedIn = try NativeOpenAIOAuth.leftoverCredentialExists(in: store)
        print("native-eval signed-in=\(signedIn)")
        fflush()
        guard signedIn else {
            print("native-eval skipped live ChatGPT run: native oauth is signed-out. Re-login then rerun --native-eval.")
            return
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
        for item in items {
            let id = item["id"] as? String ?? "?"
            let scene = item["scene"] as? String ?? ""
            let question = item["question"] as? String ?? ""
            if scene == "cancel" || scene == "error" {
                print("native-eval \(id) skipped scene=\(scene)")
                fflush()
                continue
            }
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-eval-\(id)-\(UUID().uuidString)")
            let runtime = NativeStudyAgentRuntime(
                model: model,
                adapter: adapter,
                ledgerRoot: root,
                systemPromptText: (try? PiAgentResources.bundled().systemPrompt) ?? "you are webi",
                hostToolHandler: { request in
                    let item = StudyAgentCourseItem(
                        id: "material-rates",
                        title: "利率课程",
                        subtitle: "",
                        kind: "html",
                        role: "material",
                        searchText: "利率是资金使用价格的表达。"
                    )
                    _ = request
                    return StudyAgentHostToolResult(
                        query: "利率",
                        items: [StudyAgentHostToolItem(item: item, sourceRevision: "rev-eval")]
                    )
                },
                liveStores: liveStores
            )
            let reply = try await runtime.respond(
                to: evalRequest(id: id, question: question, sessionID: UUID()),
                progress: nil
            )
            try recordAnswer(
                backend: "native",
                id: id,
                scene: scene,
                question: question,
                text: reply.text,
                tools: reply.toolTrace
            )
            ran += 1
        }
        print("native-eval live-ran=\(ran) model=\(model) effort=low")
        fflush()
    }

    private static func runPi(items: [[String: Any]], model: String, effort: String) async throws {
        let executable: URL
        let cached = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/pi-runtime/0.82.1/darwin-arm64/PiRuntime/bin/pi")
        if FileManager.default.isExecutableFile(atPath: cached.path) {
            executable = cached
        } else if let located = PiExecutableLocator.locate() {
            executable = located
        } else {
            throw NSError(domain: "WeiBei.NativeEval", code: 3, userInfo: [NSLocalizedDescriptionKey: "embedded PI runtime not found"])
        }
        let authSource = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/com.changfenhuang.weibei/PiAgent/auth.json")
        guard FileManager.default.fileExists(atPath: authSource.path) else {
            throw NSError(domain: "WeiBei.NativeEval", code: 4, userInfo: [NSLocalizedDescriptionKey: "missing Pi auth.json"])
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-pi-eval-\(UUID().uuidString)", isDirectory: true)
        let piAgent = root.appendingPathComponent("PiAgent", isDirectory: true)
        let runtimeDir = root.appendingPathComponent("Runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: piAgent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runtimeDir, withIntermediateDirectories: true)
        let authDest = piAgent.appendingPathComponent("auth.json")
        try FileManager.default.copyItem(at: authSource, to: authDest)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: authDest.path
        )
        let runtime = PiAgentRuntime(
            executableURL: executable,
            runtimeDirectory: runtimeDir,
            persistentPiConfigurationDirectory: piAgent
        )
        await runtime.configure(
            PiAgentProviderConfiguration(provider: "openai-codex", model: model, thinkingLevel: effort)
        )
        defer {
            Task { await runtime.shutdown() }
            try? FileManager.default.removeItem(at: root)
        }
        var ran = 0
        for item in items {
            let id = item["id"] as? String ?? "?"
            let scene = item["scene"] as? String ?? ""
            let question = item["question"] as? String ?? ""
            if scene == "cancel" || scene == "error" {
                print("pi-eval \(id) skipped scene=\(scene)")
                fflush()
                continue
            }
            let sessionID = UUID()
            let request = evalRequest(id: id, question: question, sessionID: sessionID)
            do {
                let reply = try await runtime.respond(
                    to: request,
                    sessionID: sessionID,
                    workingDirectory: runtimeDir,
                    hostToolHandler: evalHost,
                    progress: nil
                )
                try recordAnswer(
                    backend: "pi",
                    id: id,
                    scene: scene,
                    question: question,
                    text: reply.text,
                    tools: reply.toolTrace
                )
                ran += 1
            } catch {
                let message = error.localizedDescription.replacingOccurrences(of: "\n", with: " ")
                try recordAnswer(
                    backend: "pi",
                    id: id,
                    scene: scene,
                    question: question,
                    text: "",
                    tools: [],
                    error: message
                )
            }
            fflush()
        }
        print("pi-eval live-ran=\(ran) model=\(model) effort=\(effort)")
        fflush()
    }

    private static func recordAnswer(
        backend: String,
        id: String,
        scene: String,
        question: String,
        text: String,
        tools: [String],
        error: String? = nil
    ) throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Docs/audit/2026-08-22-eval-luna-low/\(backend)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var body = """
        # \(id) · \(scene)

        ## 问题

        \(question)

        ## 工具

        \(tools.isEmpty ? "（无）" : tools.joined(separator: ", "))

        """
        if let error {
            body += "## 错误\n\n\(error)\n\n"
        }
        body += "## 完整回答\n\n\(text)\n"
        try Data(body.utf8).write(to: root.appendingPathComponent("\(id).md"), options: .atomic)
        var record: [String: Any] = [
            "id": id,
            "scene": scene,
            "question": question,
            "tools": tools,
            "text": text,
            "chars": (text as NSString).length,
        ]
        if let error { record["error"] = error }
        let line = try JSONSerialization.data(withJSONObject: record)
        let jsonl = root.appendingPathComponent("answers.jsonl")
        if FileManager.default.fileExists(atPath: jsonl.path),
           let handle = try? FileHandle(forWritingTo: jsonl) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            handle.write(line)
            handle.write(Data("\n".utf8))
        } else {
            try (line + Data("\n".utf8)).write(to: jsonl, options: .atomic)
        }
        let shown = error == nil ? "chars=\((text as NSString).length)" : "failed"
        print("\(backend)-eval \(id) scene=\(scene) \(shown) tools=\(tools.joined(separator: ","))")
        fflush()
    }

    private static func evalRequest(id: String, question: String, sessionID: UUID) -> StudyAgentRequest {
        StudyAgentRequest(
            purpose: .conversation,
            question: question,
            materialTitle: "利率课程",
            materialText: "利率是资金使用价格的表达。",
            noteTitle: "",
            noteText: "",
            courseContext: StudyAgentCourseContext(
                title: "货币金融学",
                items: [
                    StudyAgentCourseItem(
                        id: "material-rates",
                        title: "利率课程",
                        subtitle: "",
                        kind: "html",
                        role: "material",
                        searchText: "利率是资金使用价格的表达。"
                    ),
                ]
            ),
            projectScope: StudyAgentProjectScope(
                kind: .course,
                chatID: sessionID.uuidString.lowercased(),
                courseID: UUID().uuidString.lowercased()
            ),
            contextRevision: "eval-\(id)"
        )
    }

    private static let evalHost: StudyAgentHostToolHandler = { request in
        let item = StudyAgentCourseItem(
            id: "material-rates",
            title: "利率课程",
            subtitle: "",
            kind: "html",
            role: "material",
            searchText: "利率是资金使用价格的表达。"
        )
        _ = request
        return StudyAgentHostToolResult(
            query: "利率",
            items: [StudyAgentHostToolItem(item: item, sourceRevision: "rev-eval")]
        )
    }
}
