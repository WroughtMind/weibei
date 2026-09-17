import Foundation

/// Codex uses its live catalog; API models use their documented, model-specific levels.
/// Unknown models do not acquire capabilities just because their provider speaks Responses.
public enum AgentReasoningEffort {
    public static func label(_ effort: String, language: WeiBeiInterfaceLanguage) -> String {
        guard language == .chinese else { return effort.capitalized }
        return ["none": "关闭", "minimal": "最低", "low": "低", "medium": "中",
                "high": "高", "xhigh": "很高", "max": "最高", "ultra": "极致"][effort] ?? effort
    }

    public static func selected(_ saved: String?, levels: [String], floating: Bool = false) -> String? {
        if floating { return levels.contains("low") ? "low" : nil }
        if let saved, levels.contains(saved) { return saved }
        return levels.contains("low") ? "low" : levels.first
    }

    public static func levels(provider: AgentProviderID, model: String) -> [String] {
        let id = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Match only exact IDs and dated snapshots, never speculative future model families.
        func matches(_ names: [String]) -> Bool {
            names.contains { name in
                id == name || (id.hasPrefix(name + "-")
                    && String(id.dropFirst(name.count + 1)).range(of: #"^(\d{4}-\d{2}-\d{2}|\d{8})$"#, options: .regularExpression) != nil)
            }
        }
        let standard = ["low", "medium", "high"]
        switch provider {
        case .openai, .azureOpenAI:
            // https://developers.openai.com/api/docs/models/{model}
            if matches(["gpt-6-astra"]) { return standard + ["xhigh", "max"] }
            if matches(["gpt-5.6", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"]) {
                return ["none"] + standard + ["xhigh", "max"]
            }
            if matches(["gpt-5.2", "gpt-5.4", "gpt-5.4-mini", "gpt-5.4-nano", "gpt-5.5"]) { return ["none"] + standard + ["xhigh"] }
            if matches(["gpt-5.2-pro", "gpt-5.5-pro"]) { return ["medium", "high", "xhigh"] }
            if matches(["gpt-5-pro"]) { return ["high"] }
            if matches(["gpt-5.1"]) { return ["none"] + standard }
            if matches(["gpt-5", "gpt-5-mini", "gpt-5-nano"]) { return ["minimal"] + standard }
            if matches(["gpt-5.2-codex"]) { return standard + ["xhigh"] }
            if matches(["o3", "o3-mini", "o4-mini", "o1"]) { return standard }
        case .anthropic:
            // https://platform.claude.com/docs/en/build-with-claude/effort
            if matches(["claude-opus-4-5"]) { return standard }
            if matches(["claude-opus-4-6", "claude-sonnet-4-6", "claude-mythos-preview"]) {
                return standard + ["max"]
            }
            if matches(["claude-opus-4-7", "claude-opus-4-8", "claude-opus-5", "claude-sonnet-5",
                        "claude-fable-5", "claude-fable-5-1", "claude-mythos-5", "claude-mythos-5-1"]) {
                return standard + ["xhigh", "max"]
            }
        case .google, .googleVertex:
            // https://ai.google.dev/gemini-api/docs/generate-content/thinking
            if matches(["gemini-3.1-pro-preview", "gemini-3.1-pro", "gemini-3.7-flash", "gemini-3.8-flash"]) {
                return standard
            }
            if matches(["gemini-3-flash-preview", "gemini-3-flash", "gemini-3.5-flash", "gemini-3.6-flash",
                        "gemini-3.1-flash-lite-preview", "gemini-3.1-flash-lite", "gemini-3.5-flash-lite"]) {
                return ["minimal"] + standard
            }
            if matches(["gemini-3.1-flash-lite-image"]) { return ["minimal", "high"] }
        default: break
        }
        return []
    }
}
