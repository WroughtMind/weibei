import Foundation

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
        noteText: String,
        selectionText: String?,
        recentMessages: [AgentMessage]
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let trimmedMaterial = String(materialText.prefix(18_000))
        let trimmedNote = String(noteText.prefix(6_000))
        let trimmedSelection = selectionText.map { String($0.prefix(2_000)) } ?? "无"
        let dialogue = recentMessages.suffix(8).map { message in
            let role = message.role == .user ? "用户" : "Agent"
            return "\(role)：\(String(message.text.prefix(1_200)))"
        }.joined(separator: "\n")
        let input = """
        当前材料：\(materialTitle)

        材料内容：
        \(trimmedMaterial)

        当前选区：
        \(trimmedSelection)

        当前笔记：
        \(trimmedNote)

        最近对话：
        \(dialogue.isEmpty ? "无" : dialogue)

        用户问题：
        \(question)
        """

        let body: [String: Any] = [
            "model": model,
            "instructions": "你是魏碑里的学习 Agent。只根据当前材料和当前笔记回答；没有证据就说未在材料中确认。回答用中文，先给结论，再列来源依据。",
            "input": input
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "WeiBei.OpenAI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        return try Self.extractText(from: data)
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
