import CoreGraphics
import Foundation

public enum WeiBeiInterfaceLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case chinese = "zh-Hans"
    case english = "en"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .chinese:
            return "中文"
        case .english:
            return "English"
        }
    }

    public var settingsLabel: String {
        switch self {
        case .chinese:
            return "中文界面"
        case .english:
            return "English interface"
        }
    }

    public func text(_ chinese: String, _ english: String) -> String {
        switch self {
        case .chinese:
            return chinese
        case .english:
            return english
        }
    }
}

public enum StudyItemKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case html
    case pdf
    case markdown
    case text

    public var id: String { rawValue }

    public func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .html:
            return "HTML"
        case .pdf:
            return "PDF"
        case .markdown:
            return "Markdown"
        case .text:
            return language.text("文本", "Text")
        }
    }

    public var systemImage: String {
        switch self {
        case .html: "globe"
        case .pdf: "doc.richtext"
        case .markdown: "note.text"
        case .text: "doc.text"
        }
    }

    public static func detect(from url: URL) -> StudyItemKind {
        switch url.pathExtension.lowercased() {
        case "html", "htm":
            return .html
        case "pdf":
            return .pdf
        case "md", "markdown":
            return .markdown
        default:
            return .text
        }
    }

}

public enum PaneFocus: String, Codable, Hashable {
    case library
    case reader
    case notes
    case agent
}

public enum WorkspacePaneRole: String, Codable, CaseIterable, Identifiable, Hashable {
    case reader
    case agent
    case notes

    public var id: String { rawValue }

    public func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .reader:
            return language.text("文档", "Document")
        case .agent:
            return language.text("对话", "Chat")
        case .notes:
            return language.text("笔记", "Notes")
        }
    }

    public func shortLabel(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .reader:
            return language.text("文", "Doc")
        case .agent:
            return language.text("对", "Chat")
        case .notes:
            return language.text("笔", "Notes")
        }
    }

    public var focus: PaneFocus {
        switch self {
        case .reader:
            return .reader
        case .agent:
            return .agent
        case .notes:
            return .notes
        }
    }

    public var systemImage: String {
        switch self {
        case .reader:
            return "doc.text.magnifyingglass"
        case .agent:
            return "bubble.left.and.text.bubble.right"
        case .notes:
            return "square.and.pencil"
        }
    }

    public static var defaultThreePaneOrder: [WorkspacePaneRole] {
        [.reader, .agent, .notes]
    }

    public static func normalized(_ roles: [WorkspacePaneRole]) -> [WorkspacePaneRole] {
        var ordered: [WorkspacePaneRole] = []
        for role in roles where !ordered.contains(role) {
            ordered.append(role)
        }
        for role in WorkspacePaneRole.defaultThreePaneOrder where !ordered.contains(role) {
            ordered.append(role)
        }
        return Array(ordered.prefix(3))
    }
}

public enum ThreePaneReorderTargeting {
    public static func targetIndex(
        order rawOrder: [WorkspacePaneRole],
        frames: [WorkspacePaneRole: CGRect],
        role: WorkspacePaneRole,
        horizontalDelta: CGFloat
    ) -> Int? {
        let order = WorkspacePaneRole.normalized(rawOrder)
        guard let currentIndex = order.firstIndex(of: role),
              let sourceFrame = frames[role] else { return nil }
        let draggedFrame = sourceFrame.offsetBy(dx: horizontalDelta, dy: 0)
        let draggedCenterX = draggedFrame.midX

        let overlapTarget = order.enumerated().compactMap { offset, role -> (offset: Int, overlap: CGFloat, distance: CGFloat)? in
            guard let frame = frames[role] else { return nil }
            let overlap = horizontalOverlap(draggedFrame, frame)
            guard overlap > 0.5 else { return nil }
            return (offset, overlap, abs(frame.midX - draggedCenterX))
        }
        .max { left, right in
            if abs(left.overlap - right.overlap) > 0.5 {
                return left.overlap < right.overlap
            }
            return left.distance > right.distance
        }?.offset

        let targetIndex = overlapTarget ?? order.enumerated().compactMap { offset, role -> (offset: Int, distance: CGFloat)? in
            guard let frame = frames[role] else { return nil }
            return (offset, abs(frame.midX - draggedCenterX))
        }
        .min { $0.distance < $1.distance }?.offset

        return targetIndex == currentIndex ? nil : targetIndex
    }

    private static func horizontalOverlap(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        Swift.max(0, Swift.min(lhs.maxX, rhs.maxX) - Swift.max(lhs.minX, rhs.minX))
    }
}

public enum WikiLink {
    public static func targetTitle(from rawTitle: String) -> String {
        let target = splitObsidianFields(rawTitle).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let noteTitle = target
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return noteTitle.isEmpty ? target : noteTitle
    }

    private static func splitObsidianFields(_ raw: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var index = raw.startIndex
        while index < raw.endIndex {
            let character = raw[index]
            let nextIndex = raw.index(after: index)
            if character == "\\",
               nextIndex < raw.endIndex,
               raw[nextIndex] == "|" {
                fields.append(current)
                current = ""
                index = raw.index(after: nextIndex)
                continue
            }
            if character == "|" {
                fields.append(current)
                current = ""
                index = nextIndex
                continue
            }
            current.append(character)
            index = nextIndex
        }
        fields.append(current)
        return fields
    }

    public static func enclosingTitle(in text: String, cursor utf16Offset: Int) -> String? {
        let nsText = text as NSString
        let cursor = max(0, min(utf16Offset, nsText.length))
        let start = nsText.range(of: "[[", options: .backwards, range: NSRange(location: 0, length: cursor))
        let end = nsText.range(of: "]]", range: NSRange(location: cursor, length: nsText.length - cursor))
        guard start.location != NSNotFound,
              end.location != NSNotFound,
              start.location + 2 <= end.location else {
            return nil
        }
        let rawTitle = nsText.substring(with: NSRange(location: start.location + 2, length: end.location - start.location - 2))
        let title = targetTitle(from: rawTitle)
        return title.isEmpty ? nil : title
    }
}

public enum SourceReferenceTitle {
    public static func parse(
        _ raw: String
    ) -> (
        title: String,
        pageIndex: Int?,
        sectionTitle: String?,
        sectionLocationID: String?,
        sectionOrdinal: Int?,
        courseItemOrdinal: Int?
    ) {
        var text = raw
            .components(separatedBy: .newlines)
            .reversed()
            .compactMap(sourceFragment)
            .first
            ?? sourceFragment(in: raw)
            ?? cleanedLine(raw)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix(">") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.hasPrefix("来源：") {
            text = String(text.dropFirst("来源：".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if text.lowercased().hasPrefix("source:") {
            text = String(text.dropFirst("source:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var sectionTitle: String?
        if let markerRange = text.range(of: "，章节：", options: .backwards) {
            let section = text[markerRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            sectionTitle = section.isEmpty ? nil : unwrappedInlineMarkup(String(section))
            text = text[..<markerRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let markerRange = text.range(of: #",\s*section:\s*"#, options: [.regularExpression, .caseInsensitive]) {
            let section = text[markerRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            sectionTitle = section.isEmpty ? nil : unwrappedInlineMarkup(String(section))
            text = text[..<markerRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var sectionOrdinal: Int?
        if let range = text.range(
            of: #"(?:，章节序号：\s*\d+|,\s*section\s*(?:ordinal|number):?\s*\d+)$"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            sectionOrdinal = Int(text[range].filter(\.isNumber))
            text = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var sectionLocationID: String?
        if let range = text.range(
            of: #"(?:，章节标识：\s*[A-Za-z0-9-]+|,\s*section\s*(?:id|identifier):?\s*[A-Za-z0-9-]+)$"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let suffix = String(text[range])
            let separator = suffix.lastIndex(where: { $0 == "：" || $0 == ":" })
            let identifier = (separator.map { String(suffix[suffix.index(after: $0)...]) } ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            sectionLocationID = identifier.isEmpty ? nil : identifier
            text = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var pageIndex: Int?
        if let range = text.range(
            of: #"(?:，第\s*\d+\s*页|,\s*page\s*\d+)$"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let suffix = text[range]
            pageIndex = Int(suffix.filter(\.isNumber)).map { max($0 - 1, 0) }
            text = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var courseItemOrdinal: Int?
        if let range = text.range(
            of: #"(?:，条目：\s*\d+|,\s*(?:item|entry):?\s*\d+)$"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            courseItemOrdinal = Int(text[range].filter(\.isNumber))
            text = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (
            unwrappedInlineMarkup(text),
            pageIndex,
            sectionTitle,
            sectionLocationID,
            sectionOrdinal,
            courseItemOrdinal
        )
    }

    private static func unwrappedInlineMarkup(_ raw: String) -> String {
        var text = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for marker in ["**", "__", "`", "*"] {
            if text.hasPrefix(marker), text.hasSuffix(marker), text.count > marker.count * 2 {
                text = String(text.dropFirst(marker.count).dropLast(marker.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }

    private static func sourceFragment(in raw: String) -> String? {
        let line = cleanedLine(raw)
        let chinese = line.range(of: "来源：", options: .backwards)
        let english = line.range(of: "source:", options: [.backwards, .caseInsensitive])
        let markerRange: Range<String.Index>?
        switch (chinese, english) {
        case let (left?, right?): markerRange = left.lowerBound > right.lowerBound ? left : right
        case let (left?, nil): markerRange = left
        case let (nil, right?): markerRange = right
        case (nil, nil): markerRange = nil
        }
        guard let markerRange else { return nil }
        let fragment = String(line[markerRange.lowerBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let markerLength = fragment.hasPrefix("来源：") ? "来源：".count : "source:".count
        let suffix = String(fragment.dropFirst(markerLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return suffix.isEmpty ? nil : fragment
    }

    private static func cleanedLine(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix(">") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}

public enum WorkspaceLayout: String, Codable, CaseIterable, Identifiable {
    case documentAgentNotes
    case documentNotesAgent
    case documentNotesSplit
    case immersiveReading
    case immersiveConversation
    case immersiveWriting

    public var id: String { rawValue }

    public func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .documentAgentNotes:
            return language.text("阅读-对话-笔记", "Reader-Chat-Notes")
        case .documentNotesAgent:
            return language.text("阅读-笔记-对话", "Reader-Notes-Chat")
        case .documentNotesSplit:
            return language.text("阅读/笔记对半", "Reader / Notes")
        case .immersiveReading:
            return language.text("沉浸阅读", "Immersive Reading")
        case .immersiveConversation:
            return language.text("沉浸对话", "Immersive Chat")
        case .immersiveWriting:
            return language.text("沉浸写笔记", "Immersive Writing")
        }
    }

    public var hasCollapsibleRightPane: Bool {
        switch self {
        case .documentAgentNotes, .documentNotesAgent, .documentNotesSplit, .immersiveConversation:
            return true
        case .immersiveReading, .immersiveWriting:
            return false
        }
    }

    public var isDocumentThreePane: Bool {
        switch self {
        case .documentAgentNotes, .documentNotesAgent:
            return true
        case .documentNotesSplit, .immersiveReading, .immersiveConversation, .immersiveWriting:
            return false
        }
    }

    /// Document family (multi-pane) vs immersive single-pane — used so SwiftUI only animates family switches,
    /// not every document-internal pane toggle (those are animated by AppKit).
    public var isImmersiveFamily: Bool {
        switch self {
        case .immersiveReading, .immersiveConversation, .immersiveWriting:
            return true
        case .documentAgentNotes, .documentNotesAgent, .documentNotesSplit:
            return false
        }
    }

    public var allowsRailOnlyPanes: Bool {
        switch self {
        case .documentAgentNotes, .documentNotesAgent, .documentNotesSplit:
            return true
        case .immersiveReading, .immersiveConversation, .immersiveWriting:
            return false
        }
    }

    public var defaultThreePaneOrder: [WorkspacePaneRole]? {
        switch self {
        case .documentAgentNotes:
            return [.reader, .agent, .notes]
        case .documentNotesAgent:
            return [.reader, .notes, .agent]
        case .documentNotesSplit, .immersiveReading, .immersiveConversation, .immersiveWriting:
            return nil
        }
    }

    public var systemImage: String {
        switch self {
        case .documentAgentNotes:
            return "rectangle.split.3x1"
        case .documentNotesAgent:
            return "rectangle.split.3x1.fill"
        case .documentNotesSplit:
            return "rectangle.split.2x1"
        case .immersiveReading:
            return "doc.text.magnifyingglass"
        case .immersiveConversation:
            return "bubble.left.and.text.bubble.right"
        case .immersiveWriting:
            return "square.and.pencil"
        }
    }

    public var hasPrimaryAgentPane: Bool {
        switch self {
        case .documentAgentNotes, .documentNotesAgent, .immersiveConversation:
            return true
        case .documentNotesSplit, .immersiveReading, .immersiveWriting:
            return false
        }
    }
}

/// Conversation presentation overlays retained for 1.0.
/// Primary chat lives in the immersive conversation layout / agent pane;
/// only selection-float and hidden remain as `AgentSurface` cases.
/// How a provider is typically configured in Pi (subscription OAuth vs API key vs local/custom).
public enum AgentProviderKind: String, Codable, CaseIterable, Sendable {
    case subscription
    case apiKey
    case localOrCustom

    public func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .subscription:
            return language.text("订阅 OAuth", "Subscription OAuth")
        case .apiKey:
            return language.text("API 密钥", "API Key")
        case .localOrCustom:
            return language.text("本地 / 自定义", "Local / Custom")
        }
    }
}

/// Full set of Pi `KnownProvider` ids + local/custom (aligned with Pi `docs/providers.md` + `env-api-keys`).
/// Raw values match Pi provider ids so auth.json / --provider stay compatible.
public enum AgentProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    // MARK: Subscription / OAuth (Pi `/login`)
    case openaiCodex = "openai-codex"
    case anthropic
    case githubCopilot = "github-copilot"

    // MARK: API-key providers (Pi KnownProvider)
    case openai
    case antLing = "ant-ling"
    case azureOpenAI = "azure-openai-responses"
    case deepseek
    case nvidia
    case google
    case googleVertex = "google-vertex"
    case amazonBedrock = "amazon-bedrock"
    case xai
    case mistral
    case groq
    case cerebras
    case cloudflareAIGateway = "cloudflare-ai-gateway"
    case cloudflareWorkersAI = "cloudflare-workers-ai"
    case openrouter
    case vercelAIGateway = "vercel-ai-gateway"
    case zai
    case zaiCodingCN = "zai-coding-cn"
    case opencode
    case opencodeGo = "opencode-go"
    case huggingface
    case fireworks
    case together
    case kimiCoding = "kimi-coding"
    case moonshotai
    case moonshotaiCN = "moonshotai-cn"
    case minimax
    case minimaxCN = "minimax-cn"
    case xiaomi
    case xiaomiTokenPlanCN = "xiaomi-token-plan-cn"
    case xiaomiTokenPlanAMS = "xiaomi-token-plan-ams"
    case xiaomiTokenPlanSGP = "xiaomi-token-plan-sgp"

    // MARK: Local / custom (models.json / OpenAI-compatible)
    case llamaCpp = "llama.cpp"
    case custom

    public var id: String { rawValue }

    /// Pi `--provider` / auth.json key.
    public var piProviderName: String { rawValue == "custom" ? "weibei-custom" : rawValue }

    public var kind: AgentProviderKind {
        switch self {
        case .openaiCodex, .anthropic, .githubCopilot:
            return .subscription
        case .llamaCpp, .custom:
            return .localOrCustom
        default:
            return .apiKey
        }
    }

    /// Providers for which WeiBei can run browser OAuth (Pi-compatible).
    public var supportsInAppOAuth: Bool {
        switch self {
        case .openaiCodex, .anthropic:
            return true
        default:
            return false
        }
    }

    /// Show Base URL field (Azure resource endpoint, local llama.cpp, custom OpenAI-compatible).
    public var showsBaseURLField: Bool {
        switch self {
        case .custom, .llamaCpp, .azureOpenAI:
            return true
        default:
            return false
        }
    }

    /// Primary env var Pi reads for this provider (when using API keys).
    public var environmentAPIKeyName: String {
        switch self {
        case .openaiCodex: return "OPENAI_API_KEY"
        case .anthropic: return "ANTHROPIC_API_KEY"
        case .githubCopilot: return "COPILOT_GITHUB_TOKEN"
        case .openai: return "OPENAI_API_KEY"
        case .antLing: return "ANT_LING_API_KEY"
        case .azureOpenAI: return "AZURE_OPENAI_API_KEY"
        case .deepseek: return "DEEPSEEK_API_KEY"
        case .nvidia: return "NVIDIA_API_KEY"
        case .google: return "GEMINI_API_KEY"
        case .googleVertex: return "GOOGLE_CLOUD_API_KEY"
        case .amazonBedrock: return "AWS_BEARER_TOKEN_BEDROCK"
        case .xai: return "XAI_API_KEY"
        case .mistral: return "MISTRAL_API_KEY"
        case .groq: return "GROQ_API_KEY"
        case .cerebras: return "CEREBRAS_API_KEY"
        case .cloudflareAIGateway, .cloudflareWorkersAI: return "CLOUDFLARE_API_KEY"
        case .openrouter: return "OPENROUTER_API_KEY"
        case .vercelAIGateway: return "AI_GATEWAY_API_KEY"
        case .zai: return "ZAI_API_KEY"
        case .zaiCodingCN: return "ZAI_CODING_CN_API_KEY"
        case .opencode, .opencodeGo: return "OPENCODE_API_KEY"
        case .huggingface: return "HF_TOKEN"
        case .fireworks: return "FIREWORKS_API_KEY"
        case .together: return "TOGETHER_API_KEY"
        case .kimiCoding: return "KIMI_API_KEY"
        case .moonshotai, .moonshotaiCN: return "MOONSHOT_API_KEY"
        case .minimax: return "MINIMAX_API_KEY"
        case .minimaxCN: return "MINIMAX_CN_API_KEY"
        case .xiaomi: return "XIAOMI_API_KEY"
        case .xiaomiTokenPlanCN: return "XIAOMI_TOKEN_PLAN_CN_API_KEY"
        case .xiaomiTokenPlanAMS: return "XIAOMI_TOKEN_PLAN_AMS_API_KEY"
        case .xiaomiTokenPlanSGP: return "XIAOMI_TOKEN_PLAN_SGP_API_KEY"
        case .llamaCpp: return "OPENAI_API_KEY"
        case .custom: return "OPENAI_API_KEY"
        }
    }

    public var supportsOpenAIHTTPFallback: Bool {
        self == .openai
    }

    public func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .openaiCodex: return language.text("OpenAI Codex（ChatGPT 订阅）", "OpenAI Codex (ChatGPT sub)")
        case .anthropic: return language.text("Anthropic / Claude", "Anthropic / Claude")
        case .githubCopilot: return "GitHub Copilot"
        case .openai: return "OpenAI API"
        case .antLing: return "Ant Ling"
        case .azureOpenAI: return "Azure OpenAI"
        case .deepseek: return "DeepSeek"
        case .nvidia: return "NVIDIA NIM"
        case .google: return "Google Gemini"
        case .googleVertex: return "Google Vertex AI"
        case .amazonBedrock: return "Amazon Bedrock"
        case .xai: return "xAI (Grok)"
        case .mistral: return "Mistral"
        case .groq: return "Groq"
        case .cerebras: return "Cerebras"
        case .cloudflareAIGateway: return "Cloudflare AI Gateway"
        case .cloudflareWorkersAI: return "Cloudflare Workers AI"
        case .openrouter: return "OpenRouter"
        case .vercelAIGateway: return "Vercel AI Gateway"
        case .zai: return language.text("ZAI Coding Plan（全球）", "ZAI Coding Plan (Global)")
        case .zaiCodingCN: return language.text("ZAI Coding Plan（中国）", "ZAI Coding Plan (China)")
        case .opencode: return "OpenCode Zen"
        case .opencodeGo: return "OpenCode Go"
        case .huggingface: return "Hugging Face"
        case .fireworks: return "Fireworks"
        case .together: return "Together AI"
        case .kimiCoding: return "Kimi For Coding"
        case .moonshotai: return "Moonshot AI"
        case .moonshotaiCN: return language.text("Moonshot AI（中国）", "Moonshot AI (China)")
        case .minimax: return "MiniMax"
        case .minimaxCN: return language.text("MiniMax（中国）", "MiniMax (China)")
        case .xiaomi: return "Xiaomi MiMo"
        case .xiaomiTokenPlanCN: return language.text("Xiaomi Token Plan（中国）", "Xiaomi Token Plan (China)")
        case .xiaomiTokenPlanAMS: return language.text("Xiaomi Token Plan（阿姆斯特丹）", "Xiaomi Token Plan (Amsterdam)")
        case .xiaomiTokenPlanSGP: return language.text("Xiaomi Token Plan（新加坡）", "Xiaomi Token Plan (Singapore)")
        case .llamaCpp: return "llama.cpp"
        case .custom: return language.text("自定义 OpenAI 兼容", "Custom OpenAI-compatible")
        }
    }

    public var defaultModelHint: String {
        switch self {
        case .openaiCodex: return "gpt-5.1"
        case .anthropic: return "claude-sonnet-4-20250514"
        case .githubCopilot: return "gpt-4.1"
        case .openai: return "gpt-5.1"
        case .antLing: return "default"
        case .azureOpenAI: return "gpt-4o"
        case .deepseek: return "deepseek-chat"
        case .nvidia: return "meta/llama-3.1-70b-instruct"
        case .google: return "gemini-2.5-pro"
        case .googleVertex: return "gemini-2.5-pro"
        case .amazonBedrock: return "us.anthropic.claude-sonnet-4-20250514-v1:0"
        case .xai: return "grok-3"
        case .mistral: return "mistral-large-latest"
        case .groq: return "llama-3.3-70b-versatile"
        case .cerebras: return "llama-3.3-70b"
        case .cloudflareAIGateway: return "claude-sonnet-4-5"
        case .cloudflareWorkersAI: return "@cf/meta/llama-3.1-70b-instruct"
        case .openrouter: return "openai/gpt-4.1"
        case .vercelAIGateway: return "openai/gpt-4.1"
        case .zai, .zaiCodingCN: return "default"
        case .opencode, .opencodeGo: return "default"
        case .huggingface: return "meta-llama/Llama-3.1-70B-Instruct"
        case .fireworks: return "accounts/fireworks/models/llama-v3p1-70b-instruct"
        case .together: return "meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo"
        case .kimiCoding: return "moonshot-v1-auto"
        case .moonshotai, .moonshotaiCN: return "kimi-k2.5"
        case .minimax, .minimaxCN: return "MiniMax-Text-01"
        case .xiaomi, .xiaomiTokenPlanCN, .xiaomiTokenPlanAMS, .xiaomiTokenPlanSGP: return "default"
        case .llamaCpp: return "local-model"
        case .custom: return "model-id"
        }
    }

    public static var subscriptionProviders: [AgentProviderID] {
        allCases.filter { $0.kind == .subscription }
    }

    public static var apiKeyProviders: [AgentProviderID] {
        allCases.filter { $0.kind == .apiKey }
    }

    public static var localOrCustomProviders: [AgentProviderID] {
        allCases.filter { $0.kind == .localOrCustom }
    }
}

public enum AgentSurface: String, Codable, CaseIterable, Identifiable {
    case selectionFloat
    case hidden

    public var id: String { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        // Legacy surfaces (bottomDrawer / cornerPanel / quietInsight) fall back to hidden.
        self = AgentSurface(rawValue: raw) ?? .hidden
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .selectionFloat:
            return language.text("选区轻提示", "Selection Prompt")
        case .hidden:
            return language.text("隐藏对话", "Hide Chat")
        }
    }

    public func actionLabel(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .hidden:
            return label(language: language)
        case .selectionFloat:
            return language.text("使用\(label(language: language))", "Use \(label(language: language))")
        }
    }
}

public enum NoteRenderMode: String, Codable, CaseIterable, Identifiable {
    case rich
    case split
    case source
    case preview

    public var id: String { rawValue }
    public static let visibleCases: [NoteRenderMode] = [.rich, .split, .source]

    public var visibleMode: NoteRenderMode {
        self == .preview ? .rich : self
    }

    public func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .rich:
            return language.text("写作", "Write")
        case .split:
            return language.text("对照", "Compare")
        case .source:
            return language.text("源码", "Source")
        case .preview:
            return language.text("预览", "Preview")
        }
    }
}

public struct NoteEditorCommand: Identifiable, Hashable {
    public enum Kind: String, Hashable {
        case replaceSelection
        case applyAgentPatch
        case insertMarkdown
        case scrollToHeading
    }

    public var id: UUID
    public var kind: Kind
    public var markdown: String

    public init(id: UUID = UUID(), kind: Kind, markdown: String) {
        self.id = id
        self.kind = kind
        self.markdown = markdown
    }
}

public enum SelectionSource: String, Codable, Hashable {
    case document
    case note
}

public struct SelectionContext: Identifiable, Codable, Hashable {
    public var id: UUID
    public var text: String
    public var source: SelectionSource
    public var ownerTitle: String
    public var isEditable: Bool

    public init(id: UUID = UUID(), text: String, source: SelectionSource, ownerTitle: String, isEditable: Bool = true) {
        self.id = id
        self.text = text
        self.source = source
        self.ownerTitle = ownerTitle
        self.isEditable = isEditable
    }

    public func label(language: WeiBeiInterfaceLanguage) -> String {
        switch source {
        case .document:
            return language.text("文档选区：\(ownerTitle)", "Document selection: \(ownerTitle)")
        case .note:
            return language.text("笔记选区：\(ownerTitle)", "Note selection: \(ownerTitle)")
        }
    }

    public var isNoteSelection: Bool {
        source == .note
    }

    public var isReplaceableNoteSelection: Bool {
        source == .note && isEditable
    }
}

/// A durable link between a selected text span the user asked about and the chat turns that followed.
/// Used for underline marks in the reader/note and for reopening the floating selection agent.
public struct SelectionAskThread: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var selectionText: String
    public var source: SelectionSource
    public var ownerTitle: String
    /// Material or notebook item id when known.
    public var itemID: String?
    /// Conversation message ids (user + assistant) belonging to this selection thread.
    public var messageIDs: [UUID]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        selectionText: String,
        source: SelectionSource,
        ownerTitle: String,
        itemID: String? = nil,
        messageIDs: [UUID] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.selectionText = selectionText
        self.source = source
        self.ownerTitle = ownerTitle
        self.itemID = itemID
        self.messageIDs = messageIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var normalizedText: String {
        SelectionAttachmentMerge.normalized(selectionText)
    }
}

public enum SelectionAttachmentMerge {
    public static func mergedText(existing: String, incoming: String, withinSelectionGesture: Bool) -> String? {
        let existingText = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let incomingText = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedExisting = normalized(existingText)
        let normalizedIncoming = normalized(incomingText)
        guard !normalizedExisting.isEmpty, !normalizedIncoming.isEmpty else { return nil }
        if normalizedExisting.contains(normalizedIncoming) { return existingText }
        if normalizedIncoming.contains(normalizedExisting) { return incomingText }
        guard withinSelectionGesture else { return nil }
        if let merged = overlappedText(existingText, incomingText) {
            return merged
        }
        guard canStitchAdjacentText(existingText, incomingText) else { return nil }
        return existingText + incomingText
    }

    public static func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined()
    }

    public static func containsSelection(_ container: String, fragment: String) -> Bool {
        let normalizedContainer = normalized(container)
        let normalizedFragment = normalized(fragment)
        guard !normalizedContainer.isEmpty, !normalizedFragment.isEmpty else { return false }
        return normalizedContainer.contains(normalizedFragment)
    }

    private static func overlappedText(_ existing: String, _ incoming: String) -> String? {
        let maxLength = min(existing.count, incoming.count)
        guard maxLength > 0 else { return nil }
        for length in stride(from: maxLength, through: 1, by: -1) {
            let suffix = existing.suffix(length)
            let prefix = incoming.prefix(length)
            if suffix == prefix {
                return existing + incoming.dropFirst(length)
            }
            let incomingSuffix = incoming.suffix(length)
            let existingPrefix = existing.prefix(length)
            if incomingSuffix == existingPrefix {
                return incoming + existing.dropFirst(length)
            }
        }
        return nil
    }

    private static func canStitchAdjacentText(_ existing: String, _ incoming: String) -> Bool {
        let blockedPrefixes = ["#", ">", "-", "*", "|", "```", "$$", "!["]
        guard !blockedPrefixes.contains(where: incoming.hasPrefix) else { return false }
        guard !existing.hasSuffix("\n"), !incoming.hasPrefix("\n") else { return false }
        let terminal = CharacterSet(charactersIn: "。！？!?；;：:")
        guard let last = existing.unicodeScalars.last else { return false }
        return !terminal.contains(last) || incoming.count <= 12
    }
}

public struct FloatingAgentCoordinate: Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum SelectionAnchorCoordinate {
    public static func y(_ contentY: Double, contentHeight: Double, contentViewIsFlipped: Bool) -> Double {
        contentViewIsFlipped ? contentY : contentHeight - contentY
    }
}

public enum SelectionFloatingAgentPlacement {
    public static let expandedHalfWidth = 200.0
    public static let compactHalfWidth = 82.0

    public static func isVisible(
        surface: AgentSurface,
        hasSelection: Bool,
        hasAnchor: Bool,
        pinned: Bool
    ) -> Bool {
        surface == .selectionFloat && hasSelection && (hasAnchor || pinned)
    }

    public static func position(
        anchor: FloatingAgentCoordinate?,
        canvas: FloatingAgentCoordinate,
        topInset: Double = 0,
        surfaceHalfWidth: Double = expandedHalfWidth,
        prefersAnchorCenter: Bool = false
    ) -> FloatingAgentCoordinate {
        let edgePadding = 18.0
        let anchorGap = 10.0
        let verticalGap = 8.0
        let contentCanvas = FloatingAgentCoordinate(x: canvas.x, y: max(1, canvas.y - topInset))
        let fallback = FloatingAgentCoordinate(x: contentCanvas.x - 128, y: contentCanvas.y - 124)
        let anchor = anchor.map { FloatingAgentCoordinate(x: $0.x, y: max(0, $0.y - topInset)) } ?? fallback
        let minimumX = surfaceHalfWidth + edgePadding
        let maximumX = contentCanvas.x - surfaceHalfWidth - edgePadding
        let rightSideX = anchor.x + surfaceHalfWidth + anchorGap
        let leftSideX = anchor.x - surfaceHalfWidth - anchorGap
        let preferredX: Double
        if prefersAnchorCenter {
            preferredX = anchor.x
        } else if rightSideX <= maximumX {
            preferredX = rightSideX
        } else if leftSideX >= minimumX {
            preferredX = leftSideX
        } else {
            preferredX = anchor.x
        }
        return FloatingAgentCoordinate(
            x: clamp(preferredX, min: minimumX, max: maximumX),
            y: clamp(anchor.y + verticalGap, min: 64, max: contentCanvas.y - 92)
        )
    }

    private static func clamp(_ value: Double, min minimum: Double, max maximum: Double) -> Double {
        guard maximum >= minimum else { return (minimum + maximum) / 2 }
        return Swift.max(minimum, Swift.min(value, maximum))
    }
}

public struct ImportedFileIdentity: Codable, Hashable, Sendable {
    public var volumeID: UInt64
    public var fileID: UInt64
    public var birthTimeSeconds: Int64
    public var birthTimeNanoseconds: Int64

    public init(
        volumeID: UInt64,
        fileID: UInt64,
        birthTimeSeconds: Int64,
        birthTimeNanoseconds: Int64
    ) {
        self.volumeID = volumeID
        self.fileID = fileID
        self.birthTimeSeconds = birthTimeSeconds
        self.birthTimeNanoseconds = birthTimeNanoseconds
    }
}

public struct StudyItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var kind: StudyItemKind
    public var urlPath: String?
    public var importedFileIdentity: ImportedFileIdentity?
    public var importedFileBookmarkData: Data?
    public var importedFileLastKnownPath: String?
    public var isSample: Bool
    public var isNotebookNote: Bool

    public init(
        id: String,
        title: String,
        subtitle: String,
        kind: StudyItemKind,
        urlPath: String?,
        importedFileIdentity: ImportedFileIdentity? = nil,
        importedFileBookmarkData: Data? = nil,
        importedFileLastKnownPath: String? = nil,
        isSample: Bool,
        isNotebookNote: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.urlPath = urlPath
        self.importedFileIdentity = importedFileIdentity
        self.importedFileBookmarkData = importedFileBookmarkData
        self.importedFileLastKnownPath = importedFileLastKnownPath ?? urlPath
        self.isSample = isSample
        self.isNotebookNote = isNotebookNote
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case kind
        case urlPath
        case importedFileIdentity
        case importedFileBookmarkData
        case importedFileLastKnownPath
        case isSample
        case isNotebookNote
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decode(String.self, forKey: .subtitle)
        kind = try container.decode(StudyItemKind.self, forKey: .kind)
        urlPath = try container.decodeIfPresent(String.self, forKey: .urlPath)
        importedFileIdentity = try container.decodeIfPresent(ImportedFileIdentity.self, forKey: .importedFileIdentity)
        importedFileBookmarkData = try container.decodeIfPresent(Data.self, forKey: .importedFileBookmarkData)
        importedFileLastKnownPath = try container.decodeIfPresent(String.self, forKey: .importedFileLastKnownPath) ?? urlPath
        isSample = try container.decode(Bool.self, forKey: .isSample)
        isNotebookNote = try container.decodeIfPresent(Bool.self, forKey: .isNotebookNote) ?? false
    }

    public var url: URL? {
        urlPath.map { URL(fileURLWithPath: $0) }
    }

    public var isImportedMarkdownFile: Bool {
        !isSample && kind == .markdown && url != nil
    }

    public var editsBackingMarkdownFile: Bool {
        !isSample && kind == .markdown && isNotebookNote
    }

    public var canBecomeNotebookNote: Bool {
        isImportedMarkdownFile && !isNotebookNote
    }
}

public enum AgentRole: String, Codable, Sendable {
    case user
    case assistant
}

public enum StudyAgentBackend: String, Codable, Hashable, Sendable {
    case pi
    case openAI
    case offline
}

public struct AgentMessage: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var role: AgentRole
    public var text: String
    public var source: String?
    public var backend: StudyAgentBackend?
    public var richAnswer: RichAnswerPresentation?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        role: AgentRole,
        text: String,
        source: String?,
        backend: StudyAgentBackend? = nil,
        richAnswer: RichAnswerPresentation? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.source = source
        self.backend = backend
        self.richAnswer = richAnswer
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case text
        case source
        case backend
        case richAnswer
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(AgentRole.self, forKey: .role)
        text = try container.decode(String.self, forKey: .text)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        backend = try container.decodeIfPresent(StudyAgentBackend.self, forKey: .backend)
        richAnswer = try? container.decodeIfPresent(RichAnswerPresentation.self, forKey: .richAnswer)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(backend, forKey: .backend)
        try container.encodeIfPresent(richAnswer, forKey: .richAnswer)
        try container.encode(createdAt, forKey: .createdAt)
    }

    public var isUsableAgentAnswer: Bool {
        role == .assistant
            && !text.hasPrefix("未配置密钥")
            && !text.hasPrefix("未配置 OPENAI_API_KEY")
            && !text.hasPrefix("No key is configured")
            && !text.hasPrefix("请求失败：")
            && !text.hasPrefix("Agent 请求失败：")
            && !text.hasPrefix("Request failed:")
    }
}

public struct PendingNoteWriteState: Codable, Hashable, Sendable {
    public var baselineContentDigest: String?

    public init(baselineContentDigest: String?) {
        self.baselineContentDigest = baselineContentDigest
    }
}

public struct PersistedWorkspace: Codable {
    public var importedItems: [StudyItem]
    public var notesByItemID: [String: String]
    public var pendingNoteWritesByItemID: [String: PendingNoteWriteState]?
    public var noteBackingContentDigestsByItemID: [String: String]?
    public var selectedItemID: String?
    public var activeNotebookItemID: String?
    public var courses: [Course]?
    public var courseItemMemberships: [CourseItemMembership]?
    public var activeCourseID: UUID?
    public var noteSourceLinks: [NoteSourceLink]?
    public var noteSourceLinksMigrationVersion: Int?
    public var studyLocationsByItemID: [String: StudyLocation]?
    public var learningMemoryEntries: [LearningMemoryEntry]?
    public var learningMemoryRevision: UInt64?
    public var studySessions: [StudySession]?
    public var activeStudySessionID: UUID?
    public var modelName: String?
    public var agentProviderID: String?
    public var agentBaseURL: String?
    public var workspaceLayout: WorkspaceLayout?
    public var threePaneOrder: [WorkspacePaneRole]?
    public var agentSurface: AgentSurface?
    public var noteRenderMode: NoteRenderMode?
    public var showLibrary: Bool?
    public var showReader: Bool?
    public var showAgent: Bool?
    public var showNotes: Bool?
    public var showRightPane: Bool?
    public var showDailyInspiration: Bool?
    public var appearanceModeRaw: String?
    public var adaptImportedDocumentColors: Bool?
    public var interfaceLanguageRaw: String?

    public init(
        importedItems: [StudyItem] = [],
        notesByItemID: [String: String] = [:],
        pendingNoteWritesByItemID: [String: PendingNoteWriteState]? = nil,
        noteBackingContentDigestsByItemID: [String: String]? = nil,
        selectedItemID: String? = nil,
        activeNotebookItemID: String? = nil,
        courses: [Course]? = nil,
        courseItemMemberships: [CourseItemMembership]? = nil,
        activeCourseID: UUID? = nil,
        noteSourceLinks: [NoteSourceLink]? = nil,
        noteSourceLinksMigrationVersion: Int? = nil,
        studyLocationsByItemID: [String: StudyLocation]? = nil,
        learningMemoryEntries: [LearningMemoryEntry]? = nil,
        learningMemoryRevision: UInt64? = nil,
        studySessions: [StudySession]? = nil,
        activeStudySessionID: UUID? = nil,
        modelName: String? = nil,
        agentProviderID: String? = nil,
        agentBaseURL: String? = nil,
        workspaceLayout: WorkspaceLayout? = nil,
        threePaneOrder: [WorkspacePaneRole]? = nil,
        agentSurface: AgentSurface? = nil,
        noteRenderMode: NoteRenderMode? = nil,
        showLibrary: Bool? = nil,
        showReader: Bool? = nil,
        showAgent: Bool? = nil,
        showNotes: Bool? = nil,
        showRightPane: Bool? = nil,
        showDailyInspiration: Bool? = nil,
        appearanceModeRaw: String? = nil,
        adaptImportedDocumentColors: Bool? = nil,
        interfaceLanguageRaw: String? = nil
    ) {
        self.importedItems = importedItems
        self.notesByItemID = notesByItemID
        self.pendingNoteWritesByItemID = pendingNoteWritesByItemID
        self.noteBackingContentDigestsByItemID = noteBackingContentDigestsByItemID
        self.selectedItemID = selectedItemID
        self.activeNotebookItemID = activeNotebookItemID
        self.courses = courses
        self.courseItemMemberships = courseItemMemberships
        self.activeCourseID = activeCourseID
        self.noteSourceLinks = noteSourceLinks
        self.noteSourceLinksMigrationVersion = noteSourceLinksMigrationVersion
        self.studyLocationsByItemID = studyLocationsByItemID
        self.learningMemoryEntries = learningMemoryEntries
        self.learningMemoryRevision = learningMemoryRevision
        self.studySessions = studySessions
        self.activeStudySessionID = activeStudySessionID
        self.modelName = modelName
        self.agentProviderID = agentProviderID
        self.agentBaseURL = agentBaseURL
        self.workspaceLayout = workspaceLayout
        self.threePaneOrder = threePaneOrder
        self.agentSurface = agentSurface
        self.noteRenderMode = noteRenderMode
        self.showLibrary = showLibrary
        self.showReader = showReader
        self.showAgent = showAgent
        self.showNotes = showNotes
        self.showRightPane = showRightPane
        self.showDailyInspiration = showDailyInspiration
        self.appearanceModeRaw = appearanceModeRaw
        self.adaptImportedDocumentColors = adaptImportedDocumentColors
        self.interfaceLanguageRaw = interfaceLanguageRaw
    }
}

public struct QuietInsight: Hashable {
    public var body: String
    public var noteBlock: String

    public init(body: String, noteBlock: String) {
        self.body = body
        self.noteBlock = noteBlock
    }

    public static func agent(materialTitle: String, answer: String, language: WeiBeiInterfaceLanguage = .chinese) -> QuietInsight? {
        let body = String(answer.trimmingCharacters(in: .whitespacesAndNewlines).prefix(360))
        guard !body.isEmpty else { return nil }
        return QuietInsight(body: body, noteBlock: noteBlock(body: body, source: materialTitle, language: language))
    }

    public static func make(materialTitle: String, materialText: String, noteText: String, selectionText: String?, language: WeiBeiInterfaceLanguage = .chinese) -> QuietInsight {
        let hasMaterial = !materialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if let selection = selectionText?.trimmingCharacters(in: .whitespacesAndNewlines), !selection.isEmpty {
            let excerpt = short(selection, count: 54)
            if !noteText.contains(String(selection.prefix(18))) {
                let body = language.text("选区还没有进入笔记：\(excerpt)。先收为摘录，再补一句自己的判断。", "The selection is not in the note yet: \(excerpt). Save it as an excerpt, then add one sentence of your own judgment.")
                return QuietInsight(body: body, noteBlock: noteBlock(body: body, source: materialTitle, language: language))
            }
            let body = hasMaterial
                ? language.text("选区已经出现在笔记里。下一步更适合追问它和当前材料其他段落的关系。", "The selection is already in the note. Next, ask how it relates to other parts of the current material.")
                : language.text("选区已经出现在笔记里。下一步更适合追问这段话还能补哪条依据。", "The selection is already in the note. Next, ask what evidence could support this passage.")
            return QuietInsight(body: body, noteBlock: noteBlock(body: body, source: materialTitle, language: language))
        }

        let candidate = firstUsefulLine(in: materialText)
        guard !candidate.isEmpty else {
            let noteCandidate = firstUsefulLine(in: noteText)
            if !noteCandidate.isEmpty {
                let body = language.text("当前笔记有一条可以继续整理：\(short(noteCandidate, count: 58))。建议补来源或写成问题。", "The current note has a line worth organizing: \(short(noteCandidate, count: 58)). Add a source or turn it into a question.")
                return QuietInsight(body: body, noteBlock: noteBlock(body: body, source: materialTitle, language: language))
            }
            let body = language.text("当前没有可读材料。先导入或选择一份 HTML、PDF 或 Markdown。", "There is no readable material yet. Import or choose an HTML, PDF, or Markdown file first.")
            return QuietInsight(body: body, noteBlock: noteBlock(body: body, source: materialTitle, language: language))
        }

        if !noteText.contains(String(candidate.prefix(14))) {
            let body = language.text("当前材料有一条还没进入笔记：\(short(candidate, count: 58))。建议补到摘录区。", "The current material has a line not yet in the note: \(short(candidate, count: 58)). Add it to the excerpts.")
            return QuietInsight(body: body, noteBlock: noteBlock(body: body, source: materialTitle, language: language))
        }

        let body = language.text("当前笔记已经覆盖材料开头。建议检查是否写了来源、例子和待追问。", "The current note already covers the start of the material. Check whether it includes sources, examples, and follow-up questions.")
        return QuietInsight(body: body, noteBlock: noteBlock(body: body, source: materialTitle, language: language))
    }

    private static func noteBlock(body: String, source: String, language: WeiBeiInterfaceLanguage) -> String {
        """
        > [!note] \(language.text("阅读线索", "Reading clue"))
        >
        > \(body)
        >
        > \(language.text("来源", "Source"))：\(source)
        """
    }

    private static func firstUsefulLine(in text: String) -> String {
        text.components(separatedBy: .newlines)
            .map(cleanMarkdownLine)
            .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: "。！？.!?")) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: isUsefulCandidate) ?? ""
    }

    private static func cleanMarkdownLine(_ rawLine: String) -> String {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.hasPrefix("```"), !line.hasPrefix("|") else { return "" }
        line = line.replacingOccurrences(of: #"!\[[^\]]*\]\([^\)]*\)"#, with: " ", options: .regularExpression)
        line = line.replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]*\)"#, with: "$1", options: .regularExpression)
        line = line.replacingOccurrences(of: #"\[\[([^\]\|]+)(?:\|[^\]]+)?\]\]"#, with: "$1", options: .regularExpression)
        line = line.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: #"^>\s*(?:\[[!][^\]]+\][+-]?\s*)?"#, with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: #"^[-*+]\s+\[[ xX]\]\s+"#, with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: #"^[-*+]?\s*\d*\.?\s+"#, with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: #"[*_`~=#]"#, with: "", options: .regularExpression)
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isUsefulCandidate(_ text: String) -> Bool {
        guard text.count >= 8, !text.contains("|") else { return false }
        let readableCount = text.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || (0x4E00...0x9FFF).contains($0.value)
        }.count
        return readableCount >= 6
    }

    private static func short(_ text: String, count: Int) -> String {
        text.count > count ? "\(text.prefix(count))..." : text
    }
}

public enum PageNavigator {
    public static func previous(_ index: Int) -> Int {
        max(index - 1, 0)
    }

    public static func next(_ index: Int, pageCount: Int) -> Int {
        min(index + 1, max(pageCount - 1, 0))
    }

    public static func display(_ index: Int, pageCount: Int) -> String {
        "\(min(index + 1, max(pageCount, 1))) / \(max(pageCount, 1))"
    }
}

public enum TopBarLeadingInset {
    public static func value(isFullScreen: Bool) -> Double {
        isFullScreen ? 12 : 80
    }
}

public enum PDFModeChipPresentation {
    public static func showsLabel(isExpanded: Bool) -> Bool {
        isExpanded
    }

    public static func fillOpacity(isExpanded: Bool, isHovering: Bool) -> Double {
        if isExpanded { return 0.86 }
        return isHovering ? 0.78 : 0.66
    }

    public static func strokeOpacity(isExpanded: Bool, isHovering: Bool) -> Double {
        if isExpanded { return 0.58 }
        return isHovering ? 0.34 : 0.18
    }

    public static func controlOpacity(isExpanded: Bool, isHovering: Bool) -> Double {
        if isExpanded { return 0.94 }
        return isHovering ? 0.84 : 0.70
    }
}

public enum ReaderSearch {
    public static func cleaned(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func firstMatch(in text: String, query: String) -> NSRange? {
        let query = cleaned(query)
        guard !query.isEmpty else { return nil }
        let range = (text as NSString).range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
        return range.location == NSNotFound ? nil : range
    }
}

public enum LibraryNavigator {
    public static func adjacentID(in ids: [String], selectedID: String?, step: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let selectedID, let index = ids.firstIndex(of: selectedID) else {
            return ids[0]
        }
        return ids[(index + step + ids.count) % ids.count]
    }
}
