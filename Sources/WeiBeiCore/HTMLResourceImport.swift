import Foundation
import CryptoKit
import libxml2

/// A portable HTML copy: local dependencies travel inside the document, so all
/// existing file transactions, exports and external moves remain single-file operations.
public enum HTMLResourceImport {
    public static let missingResourcesMetaName = "weibei-import-missing-resources"

    public static func dataIfHTML(at url: URL) throws -> Data? {
        guard ["html", "htm"].contains(url.pathExtension.lowercased()) else { return nil }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        // Foundation preserves macOS aliases such as /var and /tmp even after
        // resolvingSymlinksInPath. Start from the selected file's real path so
        // those system aliases aren't mistaken for a linked dependency.
        guard let path = realpath(url.path, nil) else { throw CocoaError(.fileReadUnknown) }
        defer { free(path) }
        return Collector().html(data, at: URL(fileURLWithPath: String(cString: path)), depth: 0)
    }

    private final class Collector {
        // Do not depend on Launch Services registration: these must also work in
        // Catalyst and in a fresh, headless import process.
        static let mediaMIMEs = [
            "png": "image/png", "apng": "image/apng", "jpg": "image/jpeg", "jpeg": "image/jpeg",
            "gif": "image/gif", "svg": "image/svg+xml", "webp": "image/webp", "avif": "image/avif",
            "ico": "image/x-icon", "bmp": "image/bmp", "tif": "image/tiff", "tiff": "image/tiff",
            "heic": "image/heic", "woff": "font/woff", "woff2": "font/woff2", "ttf": "font/ttf",
            "otf": "font/otf", "ttc": "font/collection", "mp3": "audio/mpeg", "wav": "audio/wav",
            "m4a": "audio/mp4", "ogg": "audio/ogg", "mp4": "video/mp4", "webm": "video/webm",
            "mov": "video/quicktime", "vtt": "text/vtt"
        ]
        var cached: [URL: (url: String, hashes: [String])] = [:]
        var reading = Set<URL>()
        var missing = Set<String>()
        var totalBytes = 0
        var embeddedBytes = 0

        // ponytail: in-memory data URLs use the reader's 32 MiB resource ceiling;
        // stream a resource package if large media documents need more than 128 MiB.
        let resourceLimit = 32 * 1024 * 1024
        let documentLimit = 128 * 1024 * 1024

        func html(_ data: Data, at source: URL, depth: Int) -> Data {
            guard data.count <= Int(Int32.max),
                  let doc = data.withUnsafeBytes({ bytes in
                      htmlReadMemory(bytes.baseAddress?.assumingMemoryBound(to: CChar.self),
                                     Int32(bytes.count), nil, String(data: data, encoding: .utf8) == nil ? nil : "utf-8",
                                     Int32(HTML_PARSE_RECOVER.rawValue | HTML_PARSE_NONET.rawValue
                                           | HTML_PARSE_NOERROR.rawValue | HTML_PARSE_NOWARNING.rawValue))
                  }) else { return data }
            defer { xmlFreeDoc(doc) }
            let root = xmlDocGetRootElement(doc)
            var nodes: [xmlNodePtr] = []
            func collect(_ first: xmlNodePtr?) {
                var current = first
                while let node = current {
                    if node.pointee.type == XML_ELEMENT_NODE { nodes.append(node) }
                    collect(node.pointee.children)
                    current = node.pointee.next
                }
            }
            collect(root)
            let baseNode = nodes.first { name($0) == "base" && attribute($0, "href") != nil }
            let base = baseNode.flatMap { attribute($0, "href") }
                .flatMap { URL(string: $0, relativeTo: source)?.absoluteURL } ?? source
            var changed = false
            for node in nodes {
                let tag = name(node)
                if tag == "meta", attribute(node, "name") == HTMLResourceImport.missingResourcesMetaName,
                   let content = attribute(node, "content"), let bytes = content.data(using: .utf8),
                   let previous = try? JSONDecoder().decode([String].self, from: bytes) {
                    missing.formUnion(previous)
                    continue
                }
                func replace(_ key: String, kind: String) {
                    guard let old = attribute(node, key) else { return }
                    let integrity = attribute(node, "integrity")
                    let value = resource(old, relativeTo: base, kind: kind, depth: depth, integrity: integrity)
                    guard value != old else { return }
                    set(node, key, value)
                    // Verify the original first, then retain integrity for the rewritten bytes.
                    if integrity != nil, value.hasPrefix("data:"),
                       let comma = value.firstIndex(of: ","),
                       let bytes = Data(base64Encoded: String(value[value.index(after: comma)...].prefix { $0 != "#" })) {
                        set(node, "integrity", "sha256-" + Data(SHA256.hash(data: bytes)).base64EncodedString())
                    }
                    changed = true
                }
                switch tag {
                case "link":
                    let rel = attribute(node, "rel")?.lowercased().split(separator: " ") ?? []
                    if rel.contains("stylesheet") { replace("href", kind: "css") }
                    else if rel.contains("icon") { replace("href", kind: "image") }
                case "script": replace("src", kind: "script")
                case "img", "input": replace("src", kind: "image")
                case "image", "use":
                    replace("href", kind: "image")
                    replace("xlink:href", kind: "image")
                case "audio", "video", "source", "track":
                    replace("src", kind: "media")
                    replace("poster", kind: "image")
                case "iframe": replace("src", kind: "html")
                default: break
                }
                if ["img", "source"].contains(tag), let old = attribute(node, "srcset") {
                    let value = srcset(old, relativeTo: base, depth: depth)
                    if old != value { set(node, "srcset", value); changed = true }
                }
                if tag == "style", let pointer = xmlNodeGetContent(node) {
                    let old = String(cString: pointer)
                    xmlFree(pointer)
                    let value = css(old, relativeTo: base, depth: depth)
                    if value != old { xmlNodeSetContent(node, value); changed = true }
                }
                if tag == "script", attribute(node, "type")?.lowercased() == "module",
                   attribute(node, "src") == nil, let pointer = xmlNodeGetContent(node) {
                    let old = String(cString: pointer)
                    xmlFree(pointer)
                    let value = javaScript(old, relativeTo: base, depth: depth)
                    if value != old { xmlNodeSetContent(node, value); changed = true }
                }
                if let old = attribute(node, "style") {
                    let value = css(old, relativeTo: base, depth: depth)
                    if value != old { set(node, "style", value); changed = true }
                }
            }
            guard changed || !missing.isEmpty else { return data }
            if !missing.isEmpty, let root {
                let head: xmlNodePtr
                if let existing = nodes.first(where: { name($0) == "head" }) {
                    head = existing
                } else {
                    head = xmlNewNode(nil, "head")!
                    if let first = root.pointee.children { xmlAddPrevSibling(first, head) }
                    else { xmlAddChild(root, head) }
                }
                let meta = nodes.first(where: {
                    name($0) == "meta" && attribute($0, "name") == HTMLResourceImport.missingResourcesMetaName
                }) ?? xmlNewChild(head, nil, "meta", nil)!
                set(meta, "name", HTMLResourceImport.missingResourcesMetaName)
                let issues = try! JSONEncoder().encode(missing.sorted())
                set(meta, "content", String(decoding: issues, as: UTF8.self))
            }
            var output: UnsafeMutablePointer<xmlChar>?
            var length: Int32 = 0
            htmlDocDumpMemoryFormat(doc, &output, &length, 0)
            guard let output, length > 0 else { return data }
            defer { xmlFree(output) }
            return Data(bytes: output, count: Int(length))
        }

        func resource(_ reference: String, relativeTo base: URL, kind: String, depth: Int,
                      integrity: String? = nil) -> String {
            let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                  let resolved = URL(string: trimmed, relativeTo: base)?.absoluteURL else { return reference }
            guard resolved.isFileURL else {
                // A remote base still needs absolute resource URLs after a stylesheet is embedded.
                return ["http", "https"].contains(resolved.scheme) ? resolved.absoluteString : reference
            }
            // URL normalization removes dot segments without Foundation's
            // filesystem alias shortening (/private/var -> /var).
            let url = URL(fileURLWithPath: resolved.standardized.path)
            let fragment = resolved.fragment.map { "#" + $0 } ?? ""
            func unavailable() -> String {
                missing.insert(url.lastPathComponent)
                return reference
            }
            func include(_ value: String) -> String {
                guard embeddedBytes + value.utf8.count <= documentLimit else { return unavailable() }
                embeddedBytes += value.utf8.count
                return value + fragment
            }
            guard depth < 24, !reading.contains(url),
                  resolved.host == nil || resolved.host == "" || resolved.host == "localhost",
                  !url.pathComponents.contains(where: { $0.hasPrefix(".") }),
                  allowed(url, kind: kind) else { return unavailable() }
            if let value = cached[url] {
                return accepts(integrity, hashes: value.hashes) ? include(value.url) : unavailable()
            }
            reading.insert(url)
            defer { reading.remove(url) }
            do {
                var data = try readRegularFile(url)
                let hashes = ["sha512-" + Data(SHA512.hash(data: data)).base64EncodedString(),
                              "sha384-" + Data(SHA384.hash(data: data)).base64EncodedString(),
                              "sha256-" + Data(SHA256.hash(data: data)).base64EncodedString()]
                guard accepts(integrity, hashes: hashes) else { return unavailable() }
                totalBytes += data.count
                guard totalBytes <= documentLimit else { return unavailable() }
                let ext = url.pathExtension.lowercased()
                let mime: String
                if kind == "css" || ext == "css" {
                    guard let text = String(data: data, encoding: .utf8) else { return unavailable() }
                    data = Data(css(text, relativeTo: url, depth: depth + 1).utf8)
                    mime = "text/css;charset=utf-8"
                } else if kind == "script" || ["js", "mjs"].contains(ext) {
                    guard let text = String(data: data, encoding: .utf8) else { return unavailable() }
                    data = Data(javaScript(text, relativeTo: url, depth: depth + 1).utf8)
                    mime = "text/javascript;charset=utf-8"
                } else if kind == "html" {
                    data = html(data, at: url, depth: depth + 1)
                    mime = "text/html"
                } else {
                    mime = Self.mediaMIMEs[ext] ?? "application/octet-stream"
                }
                let value = "data:\(mime);base64,\(data.base64EncodedString())"
                cached[url] = (value, hashes)
                return include(value)
            } catch { return unavailable() }
        }

        func accepts(_ integrity: String?, hashes: [String]) -> Bool {
            guard let integrity else { return true }
            let tokens = integrity.split(whereSeparator: \.isWhitespace)
                .map { String($0.prefix { $0 != "?" }) }
            // SRI chooses the strongest supported algorithm present, not any weaker match.
            for hash in hashes {
                let algorithm = hash.prefix { $0 != "-" } + "-"
                if tokens.contains(where: { $0.hasPrefix(algorithm) }) { return tokens.contains(hash) }
            }
            return true
        }

        func allowed(_ url: URL, kind: String) -> Bool {
            let ext = url.pathExtension.lowercased()
            switch kind {
            case "css": return ext == "css"
            case "script": return ["js", "mjs"].contains(ext)
            case "html": return ["html", "htm"].contains(ext)
            default:
                if kind == "asset", ext == "css" { return true }
                guard let mime = Self.mediaMIMEs[ext] else { return false }
                return mime.hasPrefix("image/") || (kind == "asset" && mime.hasPrefix("font/")) || kind == "media"
            }
        }

        /// Walk only the explicitly referenced path, refusing symlinks in every component.
        func readRegularFile(_ url: URL) throws -> Data {
            var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            guard descriptor >= 0 else { throw CocoaError(.fileReadNoPermission) }
            defer { close(descriptor) }
            let components = url.pathComponents.dropFirst()
            for (index, component) in components.enumerated() {
                let directoryFlag = index == components.count - 1 ? 0 : O_DIRECTORY
                let next = openat(descriptor, component, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK | directoryFlag)
                guard next >= 0 else { throw CocoaError(.fileReadNoPermission) }
                close(descriptor)
                descriptor = next
            }
            var info = stat()
            guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
                  info.st_size <= resourceLimit else { throw CocoaError(.fileReadUnknown) }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
            let data = try handle.read(upToCount: resourceLimit + 1) ?? Data()
            var after = stat()
            guard data.count <= resourceLimit, data.count == info.st_size,
                  fstat(descriptor, &after) == 0, after.st_size == info.st_size,
                  after.st_mtimespec.tv_sec == info.st_mtimespec.tv_sec,
                  after.st_mtimespec.tv_nsec == info.st_mtimespec.tv_nsec else { throw CocoaError(.fileReadUnknown) }
            return data
        }

        func css(_ text: String, relativeTo base: URL, depth: Int) -> String {
            // Skip comments and ordinary strings, so examples containing url(...) stay text.
            let pattern = #"/\*[\s\S]*?\*/|@import\s+(["'])(.*?)\1|url\(\s*(?:"((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)'|((?:\\.|[^)\\])*))\s*\)|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#
            return replacing(text, pattern: pattern, options: [.caseInsensitive]) { match, source in
                let capture = (2...5).first { match.range(at: $0).location != NSNotFound }
                guard let capture else { return nil }
                let raw = source.substring(with: match.range(at: capture))
                let reference = cssUnescape(raw.trimmingCharacters(in: .whitespacesAndNewlines))
                let value = resource(reference, relativeTo: base, kind: capture == 2 ? "css" : "asset", depth: depth)
                guard value != reference else { return nil }
                return capture == 2 ? "@import url(\"\(value)\")" : "url(\"\(value)\")"
            }
        }

        func cssUnescape(_ value: String) -> String {
            replacing(value, pattern: #"\\([0-9a-fA-F]{1,6})[\t\n\r\f ]?|\\([^\r\n])|\\\r?\n"#) { match, source in
                if match.range(at: 1).location != NSNotFound,
                   let number = UInt32(source.substring(with: match.range(at: 1)), radix: 16),
                   let scalar = UnicodeScalar(number) { return String(scalar) }
                return match.range(at: 2).location == NSNotFound ? "" : source.substring(with: match.range(at: 2))
            }
        }

        func javaScript(_ text: String, relativeTo base: URL, depth: Int) -> String {
            // ponytail: capture literal module specifiers; computed import/fetch URLs need a
            // runtime resource package if interactive sites become an import requirement.
            let pattern = #"/\*[\s\S]*?\*/|//[^\r\n]*|\b(?:import|export)\s*(?:[^;"']*?\bfrom\s*)?(["'])([^"']+)\1|\bimport\s*\(\s*(["'])([^"']+)\3\s*\)|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`"#
            return replacing(text, pattern: pattern) { match, source in
                let capture = [2, 4].first { match.range(at: $0).location != NSNotFound }
                guard let capture else { return nil }
                let raw = source.substring(with: match.range(at: capture))
                guard raw.hasPrefix(".") || raw.hasPrefix("/") || raw.hasPrefix("file:") else { return nil }
                let value = resource(raw, relativeTo: base, kind: "script", depth: depth)
                let whole = source.substring(with: match.range) as NSString
                return whole.replacingCharacters(in: NSRange(location: match.range(at: capture).location - match.range.location,
                                                             length: match.range(at: capture).length), with: value)
            }
        }

        func srcset(_ text: String, relativeTo base: URL, depth: Int) -> String {
            var index = text.startIndex
            var edits: [(Range<String.Index>, String)] = []
            while index < text.endIndex {
                while index < text.endIndex, text[index].isWhitespace || text[index] == "," { index = text.index(after: index) }
                let start = index
                while index < text.endIndex, !text[index].isWhitespace { index = text.index(after: index) }
                var end = index
                while end > start, text[text.index(before: end)] == "," { end = text.index(before: end) }
                if end > start {
                    let raw = String(text[start..<end])
                    edits.append((start..<end, resource(raw, relativeTo: base, kind: "image", depth: depth)))
                }
                if end == index {
                    var parentheses = 0
                    while index < text.endIndex {
                        let char = text[index]
                        index = text.index(after: index)
                        if char == "(" { parentheses += 1 }
                        if char == ")" { parentheses = max(0, parentheses - 1) }
                        if char == ",", parentheses == 0 { break }
                    }
                }
            }
            var result = text
            for (range, replacement) in edits.reversed() { result.replaceSubrange(range, with: replacement) }
            return result
        }

        func replacing(_ value: String, pattern: String, options: NSRegularExpression.Options = [],
                       transform: (NSTextCheckingResult, NSString) -> String?) -> String {
            let expression = try! NSRegularExpression(pattern: pattern, options: options)
            let source = value as NSString
            let output = NSMutableString(string: value)
            for match in expression.matches(in: value, range: NSRange(location: 0, length: source.length)).reversed() {
                if let replacement = transform(match, source) { output.replaceCharacters(in: match.range, with: replacement) }
            }
            return output as String
        }

        func name(_ node: xmlNodePtr) -> String { String(cString: node.pointee.name).lowercased() }
        func attribute(_ node: xmlNodePtr, _ key: String) -> String? {
            guard let value = xmlGetProp(node, key) else { return nil }
            defer { xmlFree(value) }
            return String(cString: value)
        }
        func set(_ node: xmlNodePtr, _ key: String, _ value: String) { xmlSetProp(node, key, value) }
    }
}
