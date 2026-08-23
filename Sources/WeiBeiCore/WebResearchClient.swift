import Darwin
import Foundation

public enum WeiBeiWebResearchError: LocalizedError, Equatable, Sendable {
    case invalidURL
    case insecureURL
    case privateAddress
    case unavailable
    case unsupportedContent
    case responseTooLarge
    case emptyContent

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "网页地址无效。"
        case .insecureURL:
            return "网页读取只接受 HTTPS 地址。"
        case .privateAddress:
            return "网页读取不能访问本机、局域网或保留网络地址。"
        case .unavailable:
            return "网页暂时无法读取。"
        case .unsupportedContent:
            return "这个地址返回的不是可读取网页。"
        case .responseTooLarge:
            return "网页内容超过读取上限。"
        case .emptyContent:
            return "网页没有可读取的正文。"
        }
    }
}

public enum WeiBeiWebResearchURLPolicy {
    public static func isAuthorized(
        _ url: String,
        in userQuestion: String,
        webSearchURLs: [String]
    ) -> Bool {
        guard let requested = canonicalAuthorizationURL(url) else { return false }
        return isExplicitlyProvided(url, in: userQuestion)
            || webSearchURLs.contains { canonicalAuthorizationURL($0) == requested }
    }

    public static func isExplicitlyProvided(_ url: String, in userQuestion: String) -> Bool {
        guard let requested = canonicalAuthorizationURL(url),
              let detector = try? NSDataDetector(
                types: NSTextCheckingResult.CheckingType.link.rawValue
              ) else {
            return false
        }
        let range = NSRange(userQuestion.startIndex..., in: userQuestion)
        return detector.matches(in: userQuestion, options: [], range: range).contains { match in
            guard match.resultType == .link,
                  let matchRange = Range(match.range, in: userQuestion) else {
                return false
            }
            let detected = String(userQuestion[matchRange])
            var candidates = [detected]
            if matchRange.lowerBound > userQuestion.startIndex {
                let opener = userQuestion[userQuestion.index(before: matchRange.lowerBound)]
                let closer: Character? = opener == "[" ? "]" : (opener == "`" ? "`" : nil)
                if let closer,
                   let boundary = detected.firstIndex(of: closer) {
                    candidates.append(String(detected[..<boundary]))
                }
            }
            return candidates.contains { canonicalAuthorizationURL($0) == requested }
        }
    }

    public static func consumeSearchAuthorization(
        for url: String,
        from webSearchURLs: inout [String]
    ) {
        guard let requested = canonicalAuthorizationURL(url) else { return }
        webSearchURLs.removeAll { canonicalAuthorizationURL($0) == requested }
    }

    public static func validatedPublicHTTPSURL(_ rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.utf8.count <= 2_048,
              var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil else {
            if URLComponents(string: trimmed)?.scheme?.lowercased() == "http" {
                throw WeiBeiWebResearchError.insecureURL
            }
            throw WeiBeiWebResearchError.invalidURL
        }
        components.scheme = "https"
        components.host = host
        components.fragment = nil
        guard let url = components.url else {
            throw WeiBeiWebResearchError.invalidURL
        }
        guard resolvedAddressesArePublic(host) else {
            throw WeiBeiWebResearchError.privateAddress
        }
        return url
    }

    private static func canonicalAuthorizationURL(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count <= 2_048,
              var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil else {
            return nil
        }
        components.scheme = "https"
        components.host = host
        components.fragment = nil
        if components.port == 443 {
            components.port = nil
        }
        if components.percentEncodedPath.isEmpty {
            components.percentEncodedPath = "/"
        }
        return components.url?.absoluteString
    }

    private static func resolvedAddressesArePublic(_ host: String) -> Bool {
        let normalizedHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        guard normalizedHost != "localhost",
              !normalizedHost.hasSuffix(".localhost"),
              !normalizedHost.hasSuffix(".local") else {
            return false
        }

        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var head: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(normalizedHost, "443", &hints, &head) == 0,
              let first = head else {
            return false
        }
        defer { freeaddrinfo(first) }

        var foundAddress = false
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ai_next }
            guard let socketAddress = current.pointee.ai_addr else { continue }
            switch Int32(socketAddress.pointee.sa_family) {
            case AF_INET:
                foundAddress = true
                let address = UnsafeRawPointer(socketAddress)
                    .assumingMemoryBound(to: sockaddr_in.self)
                    .pointee
                    .sin_addr
                guard ipv4IsPublic(address) else { return false }
            case AF_INET6:
                foundAddress = true
                var address = UnsafeRawPointer(socketAddress)
                    .assumingMemoryBound(to: sockaddr_in6.self)
                    .pointee
                    .sin6_addr
                let bytes = withUnsafeBytes(of: &address) { Array($0) }
                guard ipv6IsPublic(bytes) else { return false }
            default:
                break
            }
        }
        return foundAddress
    }

    private static func ipv4IsPublic(_ address: in_addr) -> Bool {
        let value = UInt32(bigEndian: address.s_addr)
        let first = value >> 24
        return first != 0
            && first != 10
            && first != 127
            && first < 224
            && !(value >= 0x6440_0000 && value <= 0x647F_FFFF)
            && !(value >= 0xA9FE_0000 && value <= 0xA9FE_FFFF)
            && !(value >= 0xAC10_0000 && value <= 0xAC1F_FFFF)
            && !(value >= 0xC000_0000 && value <= 0xC000_00FF)
            && !(value >= 0xC0A8_0000 && value <= 0xC0A8_FFFF)
            && !(value >= 0xC612_0000 && value <= 0xC613_FFFF)
            && value >> 8 != 0xC000_02
            && value >> 8 != 0xC058_63
            && value >> 8 != 0xC633_64
            && value >> 8 != 0xCB00_71
    }

    private static func ipv6IsPublic(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return false }
        if bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 0xFF, bytes[11] == 0xFF {
            var address = in_addr()
            withUnsafeMutableBytes(of: &address) { destination in
                destination.copyBytes(from: bytes[12...15])
            }
            return ipv4IsPublic(address)
        }
        // Current globally routable unicast space is 2000::/3. This rejects
        // loopback, unspecified, ULA, link-local, multicast and documentation ranges.
        guard (bytes[0] & 0xE0) == 0x20 else { return false }
        return !(bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0D && bytes[3] == 0xB8)
    }
}

public enum WeiBeiWebResearchClient {
    private static let maximumResponseBytes = 1_000_000
    private static let maximumRedirects = 5

    public static func open(
        _ rawURL: String,
        maximumCharacters: Int
    ) async throws -> StudyAgentWebPage {
        let url = try WeiBeiWebResearchURLPolicy.validatedPublicHTTPSURL(rawURL)
        let redirectDelegate = WebResearchRedirectDelegate(maximumRedirects: maximumRedirects)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.httpAdditionalHeaders = [
            "Accept": "text/html,application/xhtml+xml,text/plain;q=0.9",
            "User-Agent": "WeiBei/1 Web Reader",
        ]
        let session = URLSession(
            configuration: configuration,
            delegate: redirectDelegate,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WeiBeiWebResearchError.unavailable
        }
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let finalRawURL = http.url?.absoluteString else {
            throw WeiBeiWebResearchError.unavailable
        }
        let finalURL = try WeiBeiWebResearchURLPolicy.validatedPublicHTTPSURL(finalRawURL)
        let mimeType = http.mimeType?.lowercased() ?? ""
        guard mimeType == "text/html"
                || mimeType == "application/xhtml+xml"
                || mimeType == "text/plain" else {
            throw WeiBeiWebResearchError.unsupportedContent
        }
        guard http.expectedContentLength <= Int64(maximumResponseBytes)
                || http.expectedContentLength < 0 else {
            throw WeiBeiWebResearchError.responseTooLarge
        }

        var data = Data()
        data.reserveCapacity(min(max(Int(http.expectedContentLength), 0), maximumResponseBytes))
        do {
            for try await byte in bytes {
                guard data.count < maximumResponseBytes else {
                    throw WeiBeiWebResearchError.responseTooLarge
                }
                data.append(byte)
            }
        } catch let error as WeiBeiWebResearchError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WeiBeiWebResearchError.unavailable
        }

        guard let decoded = decodedString(data, encodingName: http.textEncodingName) else {
            throw WeiBeiWebResearchError.unsupportedContent
        }
        let rawText = mimeType == "text/plain" ? decoded : visibleText(fromHTML: decoded)
        let cleaned = normalizedText(rawText)
        guard !cleaned.isEmpty else { throw WeiBeiWebResearchError.emptyContent }
        let boundedCharacters = min(max(maximumCharacters, 1_000), 20_000)
        let isTruncated = cleaned.count > boundedCharacters
        let title = mimeType == "text/plain"
            ? finalURL.host ?? finalURL.absoluteString
            : htmlTitle(from: decoded) ?? finalURL.host ?? finalURL.absoluteString
        return StudyAgentWebPage(
            url: finalURL.absoluteString,
            title: String(title.prefix(300)),
            text: String(cleaned.prefix(boundedCharacters)),
            isTruncated: isTruncated
        )
    }

    private static func decodedString(_ data: Data, encodingName: String?) -> String? {
        if encodingName?.lowercased() == "iso-8859-1",
           let value = String(data: data, encoding: .isoLatin1) {
            return value
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }

    private static func htmlTitle(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<title\b[^>]*>(.*?)</title>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ), let match = regex.firstMatch(
            in: html,
            range: NSRange(html.startIndex..., in: html)
        ), let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let title = normalizedText(decodeHTMLEntities(String(html[range])))
        return title.isEmpty ? nil : title
    }

    private static func visibleText(fromHTML html: String) -> String {
        var text = replacing(
            in: html,
            pattern: #"(?is)<(?:script|style|noscript|svg)\b[^>]*>.*?</(?:script|style|noscript|svg)>"#,
            with: " "
        )
        text = replacing(in: text, pattern: #"(?s)<!--.*?-->"#, with: " ")
        text = replacing(
            in: text,
            pattern: #"(?i)<(?:br|/p|/div|/li|/h[1-6]|/tr)\b[^>]*>"#,
            with: "\n"
        )
        text = replacing(in: text, pattern: #"<[^>]+>"#, with: " ")
        return decodeHTMLEntities(text)
    }

    private static func replacing(in value: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        return regex.stringByReplacingMatches(
            in: value,
            range: NSRange(value.startIndex..., in: value),
            withTemplate: replacement
        )
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        var decoded = value
        for (entity, character) in [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"),
        ] {
            decoded = decoded.replacingOccurrences(of: entity, with: character)
        }
        guard let regex = try? NSRegularExpression(pattern: #"&#(x[0-9A-Fa-f]+|[0-9]+);"#) else {
            return decoded
        }
        let matches = regex.matches(
            in: decoded,
            range: NSRange(decoded.startIndex..., in: decoded)
        )
        for match in matches.reversed() {
            guard let wholeRange = Range(match.range(at: 0), in: decoded),
                  let valueRange = Range(match.range(at: 1), in: decoded) else { continue }
            let token = String(decoded[valueRange])
            let scalarValue = token.lowercased().hasPrefix("x")
                ? UInt32(token.dropFirst(), radix: 16)
                : UInt32(token, radix: 10)
            guard let scalarValue, let scalar = UnicodeScalar(scalarValue) else { continue }
            decoded.replaceSubrange(wholeRange, with: String(scalar))
        }
        return decoded
    }

    private static func normalizedText(_ value: String) -> String {
        replacing(in: value, pattern: #"[\t\r ]+"#, with: " ")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

private final class WebResearchRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let maximumRedirects: Int
    private var redirectCount = 0
    private let lock = NSLock()

    init(maximumRedirects: Int) {
        self.maximumRedirects = maximumRedirects
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        lock.lock()
        redirectCount += 1
        let permitsAnotherRedirect = redirectCount <= maximumRedirects
        lock.unlock()
        guard permitsAnotherRedirect,
              let rawURL = request.url?.absoluteString,
              let validated = try? WeiBeiWebResearchURLPolicy.validatedPublicHTTPSURL(rawURL) else {
            completionHandler(nil)
            return
        }
        var sanitized = request
        sanitized.url = validated
        sanitized.setValue(nil, forHTTPHeaderField: "Authorization")
        sanitized.setValue(nil, forHTTPHeaderField: "Cookie")
        sanitized.setValue(nil, forHTTPHeaderField: "Referer")
        completionHandler(sanitized)
    }
}
