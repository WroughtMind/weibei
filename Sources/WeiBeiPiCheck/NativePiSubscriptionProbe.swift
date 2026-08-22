import Foundation
import WeiBeiCore

enum NativePiSubscriptionProbe {
    static func runIfRequested(arguments: [String], environment: [String: String]) async -> Bool {
        guard arguments.contains("--pi-subscription-probe") else { return false }
        do {
            try await run(environment: environment)
        } catch {
            fputs("pi-subscription-probe failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
        return true
    }

    static func run(environment: [String: String]) async throws {
        let explicit = environment["WEIBEI_PI_EXECUTABLE"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let executable = explicit.isEmpty
            ? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/pi-runtime/0.82.1/darwin-arm64/PiRuntime/bin/pi")
            : URL(fileURLWithPath: explicit)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-pi-sub-probe-\(UUID().uuidString)", isDirectory: true)
        let piAgent = root.appendingPathComponent("PiAgent", isDirectory: true)
        try FileManager.default.createDirectory(at: piAgent, withIntermediateDirectories: true)
        let runtime = PiAgentRuntime(
            executableURL: executable,
            runtimeDirectory: root.appendingPathComponent("Runtime", isDirectory: true),
            persistentPiConfigurationDirectory: piAgent
        )
        defer {
            Task { await runtime.shutdown() }
            try? FileManager.default.removeItem(at: root)
        }
        let catalog = try await runtime.managementCatalog()
        let targets = ["anthropic", "github-copilot", "radius"]
        print("pi-subscription-probe catalog providers=\(catalog.providers.count)")
        for id in targets {
            let provider = catalog.providers.first { $0.id == id }
            let models = catalog.models.filter { $0.providerId == id }.prefix(3).map(\.id)
            let oauth = provider?.authTypes.contains(.oauth) == true
            let apiKey = provider?.authTypes.contains(.apiKey) == true
            print(
                "pi-subscription-probe \(id): present=\(provider != nil) oauth=\(oauth) apiKey=\(apiKey) sampleModels=\(models.joined(separator: ","))"
            )
        }
        let userAuth = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/com.changfenhuang.weibei/PiAgent/auth.json")
        if FileManager.default.fileExists(atPath: userAuth.path),
           let object = try JSONSerialization.jsonObject(with: Data(contentsOf: userAuth)) as? [String: Any] {
            let configured = object.keys.sorted()
            print("pi-subscription-probe user-auth-providers=\(configured.joined(separator: ","))")
            for id in targets {
                print("pi-subscription-probe user-\(id)-configured=\(object[id] != nil)")
            }
        } else {
            print("pi-subscription-probe user-auth-providers=")
        }
        print("pi-subscription-probe note: login+send was not attempted; that needs the user at the browser.")
    }
}
