import Foundation

public struct AgentPromptPayload: Equatable {
    public var instructions: String
    public var input: String

    public init(instructions: String, input: String) {
        self.instructions = instructions
        self.input = input
    }
}

public struct OpenAIResponsesClient {
    let apiKey: String
    let model: String

    public init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model
    }

    public func ask(
        question: String,
        materialTitle: String,
        materialText: String,
        noteTitle: String = "当前笔记",
        noteText: String,
        selectionTitle: String? = nil,
        selectionText: String?,
        recentMessages: [AgentMessage]
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = Self.composePrompt(
            question: question,
            materialTitle: materialTitle,
            materialText: materialText,
            noteTitle: noteTitle,
            noteText: noteText,
            selectionTitle: selectionTitle,
            selectionText: selectionText,
            recentMessages: recentMessages
        )
        let body: [String: Any] = [
            "model": model,
            "instructions": prompt.instructions,
            "input": prompt.input
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "WeiBei.OpenAI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        return try Self.extractText(from: data)
    }

    public static func composePrompt(
        question: String,
        materialTitle: String,
        materialText: String,
        noteTitle: String = "当前笔记",
        noteText: String,
        selectionTitle: String? = nil,
        selectionText: String?,
        recentMessages: [AgentMessage]
    ) -> AgentPromptPayload {
        func label(_ value: String?, fallback: String) -> String {
            let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return cleaned.isEmpty ? fallback : cleaned
        }

        let materialLabel = label(materialTitle, fallback: "当前材料")
        let noteLabel = label(noteTitle, fallback: "当前笔记")
        let trimmedMaterial = focusedMaterialText(materialText, title: materialLabel, limit: 18_000)
        let trimmedNote = String(noteText.prefix(6_000))
        let trimmedSelection = selectionText.map { String($0.prefix(2_000)) } ?? ""
        let hasMaterial = !trimmedMaterial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let selectionLabel = label(selectionTitle, fallback: hasMaterial ? materialLabel : noteLabel)
        let materialBlock = hasMaterial ? """
        当前材料：\(materialLabel)

        材料内容：
        \(trimmedMaterial)
        """ : "当前材料：无"
        let selectionBlock = trimmedSelection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "当前选区：无" : """
        当前选区（来源：\(selectionLabel)）：
        \(trimmedSelection)
        """
        let noteBlock = """
        当前笔记：\(noteLabel)

        笔记内容：
        \(trimmedNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "无" : trimmedNote)
        """
        let dialogue = recentMessages.suffix(8).map { message in
            let role = message.role == .user ? "用户" : "助手"
            let source = message.source?.trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceText = source?.isEmpty == false ? "（来源：\(source!)）" : ""
            return "\(role)\(sourceText)：\(String(message.text.prefix(1_200)))"
        }.joined(separator: "\n")
        let sourceRule = "回答末尾用“来源依据”列出真正用到的材料标题、选区来源或笔记标题；没有用到的来源不要列。"
        let instructions = hasMaterial
            ? "你是魏碑里的学习助手。只根据当前材料、当前笔记和当前选区回答；没有证据就说未在材料或笔记中确认。回答用中文，先给结论。\(sourceRule)"
            : "你是魏碑里的学习助手。只根据当前笔记和当前选区回答；没有证据就说未在笔记或选区中确认。回答用中文，先给结论。\(sourceRule)"
        let input = """
        \(materialBlock)

        \(selectionBlock)

        \(noteBlock)

        最近对话：
        \(dialogue.isEmpty ? "无" : dialogue)

        用户问题：
        \(question)
        """
        return AgentPromptPayload(instructions: instructions, input: input)
    }

    private static func focusedMaterialText(_ text: String, title: String, limit: Int) -> String {
        let parsed = SourceReferenceTitle.parse(title)
        guard let pageIndex = parsed.pageIndex else {
            return String(text.prefix(limit))
        }
        let pageNumber = pageIndex + 1
        let pageHeaderPattern = #"(?m)^第\s*\#(pageNumber)\s*页(?:（OCR）)?\s*$"#
        guard let pageHeader = text.range(of: pageHeaderPattern, options: .regularExpression) else {
            return String(text.prefix(limit))
        }
        let nextPagePattern = #"(?m)^第\s*\d+\s*页(?:（OCR）)?\s*$"#
        let searchStart = pageHeader.upperBound
        let searchRange = searchStart..<text.endIndex
        let pageEnd = text.range(of: nextPagePattern, options: .regularExpression, range: searchRange)?.lowerBound ?? text.endIndex
        return String(text[pageHeader.lowerBound..<pageEnd].prefix(limit))
    }

    public static func extractText(from data: Data) throws -> String {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let outputText = json?["output_text"] as? String, !outputText.isEmpty {
            return outputText
        }

        let output = json?["output"] as? [[String: Any]] ?? []
        let chunks = output.flatMap { item -> [String] in
            let content = item["content"] as? [[String: Any]] ?? []
            return content.compactMap { part in
                part["text"] as? String
                    ?? part["output_text"] as? String
                    ?? (part["type"] as? String == "output_text" ? part["text"] as? String : nil)
            }
        }

        let text = chunks.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            throw NSError(domain: "WeiBei.OpenAI", code: -1, userInfo: [NSLocalizedDescriptionKey: "响应里没有可读文本"])
        }
        return text
    }
}
