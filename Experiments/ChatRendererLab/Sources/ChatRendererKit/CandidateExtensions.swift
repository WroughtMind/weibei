import Foundation
import MarkdownParser

public enum CandidateAttachment: Hashable, Sendable {
    case image(source: String, alt: String)
    case visualization(id: String)
    case mermaid(source: String)
    case math(source: String, identifier: String)
}

/// Rewrites only the extensions the upstream renderer does not display.
/// Fenced code and inline code never enter the wiki-link rewrite.
struct CandidateExtensions {
    var attachments: [Int: CandidateAttachment] = [:]
    var calloutIndex = 0
    let toggledCallouts: Set<Int>
    let displayMath: Set<String>

    mutating func blocks(_ input: [MarkdownBlockNode]) -> [MarkdownBlockNode] {
        input.flatMap { block -> [MarkdownBlockNode] in
            switch block {
            case let .codeBlock(language, source) where language?.lowercased() == "mermaid":
                return [.paragraph(content: [attachment(.mermaid(source: source))])]
            case let .blockquote(children):
                if let first = children.first, case let .paragraph(content) = first,
                   let header = calloutHeader(content) {
                    let id = calloutIndex; calloutIndex += 1
                    let collapsed = (header.fold == "-") != toggledCallouts.contains(id)
                    let title: MarkdownInlineNode = header.fold.isEmpty
                        ? .strong(children: [.text(header.title)])
                        : .link(destination: "weibei-callout:\(id)",
                                children: [.text((collapsed ? "▸ " : "▾ ") + header.title)])
                    var result: [MarkdownBlockNode] = [.paragraph(content: [title])]
                    if header.fold.isEmpty || !collapsed {
                        if !header.body.isEmpty { result += blocks([.paragraph(content: header.body)]) }
                        result += blocks(Array(children.dropFirst()))
                    }
                    return [.blockquote(children: result)]
                }
                return [.blockquote(children: blocks(children))]
            case let .bulletedList(tight, items):
                return [.bulletedList(isTight: tight, items: items.map { .init(children: blocks($0.children)) })]
            case let .numberedList(tight, start, items):
                return [.numberedList(isTight: tight, start: start, items: items.map { .init(children: blocks($0.children)) })]
            case let .taskList(tight, items):
                return [.taskList(isTight: tight, items: items.map { .init(isCompleted: $0.isCompleted, children: blocks($0.children)) })]
            default:
                return block.rewrite { (node: MarkdownInlineNode) in inline(node) }
            }
        }
    }

    private mutating func attachment(_ value: CandidateAttachment) -> MarkdownInlineNode {
        let index = attachments.count
        attachments[index] = value
        return .text("\u{F0000}\(index)\u{F0001}")
    }

    private mutating func inline(_ node: MarkdownInlineNode) -> [MarkdownInlineNode] {
        switch node {
        case let .math(source, identifier) where displayMath.contains(identifier):
            return [attachment(.math(source: source, identifier: identifier))]
        case let .image(source, children):
            if source.hasPrefix("weibei-visualization:") {
                return [attachment(.visualization(id: String(source.dropFirst("weibei-visualization:".count))))]
            }
            return [attachment(.image(source: source, alt: plain(children)))]
        case let .text(value):
            let expression = /(!?)\[\[([^\]\n]+)\]\]/
            var result: [MarkdownInlineNode] = []
            var cursor = value.startIndex
            for match in value.matches(of: expression) {
                result.append(.text(String(value[cursor..<match.range.lowerBound])))
                let parts = match.2.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                let source = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let label = String(parts.last!).trimmingCharacters(in: .whitespaces)
                let target = source.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? source
                if match.1 == "!", source.range(of: #"\.(png|jpe?g|gif|webp|svg|heic)(?:[?#].*)?$"#, options: .regularExpression) != nil {
                    result.append(attachment(.image(source: source, alt: label)))
                } else {
                    result.append(.link(destination: "weibei-note:\(target)", children: [.text(label)]))
                }
                cursor = match.range.upperBound
            }
            result.append(.text(String(value[cursor...])))
            return result
        default: return [node]
        }
    }

    private func plain(_ nodes: [MarkdownInlineNode]) -> String {
        nodes.map { node in
            switch node {
            case let .text(value), let .code(value): return value
            case .softBreak, .lineBreak: return "\n"
            default: return plain(node.children)
            }
        }.joined()
    }

    private func calloutHeader(_ nodes: [MarkdownInlineNode]) -> (title: String, fold: String, body: [MarkdownInlineNode])? {
        let split = nodes.firstIndex { $0 == .softBreak || $0 == .lineBreak } ?? nodes.endIndex
        let header = plain(Array(nodes[..<split]))
        guard let match = header.wholeMatch(of: /\[!([A-Za-z][A-Za-z0-9_-]*)\]([+-]?)(?:[ \t]+(.*))?/) else { return nil }
        let names = ["note": "札记", "tip": "提示", "warning": "留心", "important": "重点", "question": "问题", "info": "信息"]
        let title = match.3.map(String.init) ?? names[String(match.1).lowercased()] ?? String(match.1)
        return (title, String(match.2), split < nodes.endIndex ? Array(nodes[(split + 1)...]) : [])
    }
}
