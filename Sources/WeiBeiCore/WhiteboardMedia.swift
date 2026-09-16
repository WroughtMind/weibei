import Foundation
import WebKit

/// Only serves bundled voice packs to the local player. No URL or filesystem path comes from JavaScript.
@MainActor public final class WhiteboardVoiceResources: NSObject, WKScriptMessageHandlerWithReply {
    private let directory: URL
    public init(directory: URL) { self.directory = directory.resolvingSymlinksInPath(); super.init() }
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                                      replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame, let source = message.frameInfo.request.url, source.isFileURL,
              source.deletingLastPathComponent().resolvingSymlinksInPath() == directory,
              let group = message.body as? String, group.utf8.count == 1,
              group.utf8.allSatisfy({ (97...122).contains($0) }) else { replyHandler(nil, "无效的中文声音资源请求"); return }
        do {
            let data = try Data(contentsOf: directory.appendingPathComponent("chinese-voice-\(group).caf"), options: .mappedIfSafe)
            guard !data.isEmpty, data.count <= 1_024 * 1_024 else { throw WhiteboardFailure("中文声音资源大小无效") }
            replyHandler(data.base64EncodedString(), nil)
        } catch { replyHandler(nil, "中文声音资源读取失败：\(group)") }
    }
}

public struct WhiteboardMediaSettings: Codable, Equatable, Sendable {
    public enum Voice: String, Codable, CaseIterable, Sendable { case animalese, system, cloud, silent }
    public var voice: Voice = .animalese
    public var speed: Double = 1
    public var speech = Channel()
    public init() {}
    public struct Channel: Codable, Equatable, Sendable {
        public var baseURL = ""
        public var model = ""
        public var voice = ""
        public init() {}
        public var isConfigured: Bool { !baseURL.isEmpty && !model.isEmpty }
        public func credentialID(kind: String) throws -> String {
            "whiteboard-\(kind)-" + (try AgentProviderEndpoint(provider: .custom, baseURL: baseURL)).credentialProviderID
        }
    }
}

/// Redirects are rejected: a configured endpoint must never redirect its credentials elsewhere.
private final class WhiteboardNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public enum WhiteboardMedia {
    public static func request(channel: WhiteboardMediaSettings.Channel, kind: String, path: String,
                               body: Data, contentType: String = "application/json") async throws -> Data {
        guard channel.isConfigured else { throw WhiteboardFailure("请先配置\(kind)服务地址和模型。") }
        let endpoint = try AgentProviderEndpoint(provider: .custom, baseURL: channel.baseURL)
        guard let root = endpoint.baseURL.flatMap(URL.init(string:)) else { throw AgentProviderEndpointError.invalid }
        var request = URLRequest(url: root.appendingPathComponent(path))
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if let key = try NativeAgentCredentialStore.apiKey(forProviderID: channel.credentialID(kind: kind)) {
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        }
        return try await fetch(request)
    }

    private static func fetch(_ input: URLRequest) async throws -> Data {
        var request = input; request.timeoutInterval = 180
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 240
        let session = URLSession(configuration: configuration, delegate: WhiteboardNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WhiteboardFailure("媒体服务请求失败（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)），请检查服务配置。")
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 32 * 1_024 * 1_024 else { throw WhiteboardFailure("媒体超过 32 MB 限制。") }
            data.append(byte)
        }
        guard !data.isEmpty else { throw WhiteboardFailure("媒体服务返回空内容。") }
        return data
    }

    public static func speech(_ text: String, settings: WhiteboardMediaSettings) async throws -> Data {
        try await request(channel: settings.speech, kind: "speech", path: "audio/speech",
            body: JSONSerialization.data(withJSONObject: [
                "model": settings.speech.model, "input": text,
                "voice": settings.speech.voice, "response_format": "mp3", "speed": 1
            ]))
    }

}
