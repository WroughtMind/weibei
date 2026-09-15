import Foundation
import ZIPFoundation

/// Reads the source text used by course search; the reader displays the original package.
public enum OfficeDocumentText {
    /// Matches the reader component's total unpacked-size budget; media is not text.
    public static let maximumFileBytes = 256 * 1_024 * 1_024
    public struct Section: Sendable {
        public var location: String
        public var heading: String?
        public var text: String
    }

    public enum ReadError: Error {
        case missingPart(String)
        case invalidXML(String)
        case oversizedPart(String)
        case unsupportedEquation(String)
    }

    public static func sections(in data: Data, kind: StudyItemKind) throws -> [Section] {
        guard data.count <= maximumFileBytes else { throw ReadError.oversizedPart("document") }
        let archive = try Archive(data: data, accessMode: .read)
        var remainingBytes = UInt64(maximumFileBytes)
        for (index, entry) in archive.lazy.filter({ $0.type != .directory }).enumerated() {
            guard index < 4_000, entry.uncompressedSize <= remainingBytes else {
                throw ReadError.oversizedPart("document")
            }
            remainingBytes -= entry.uncompressedSize
        }
        func xml(_ path: String) throws -> OfficeXMLNode {
            guard let entry = archive[path] else { throw ReadError.missingPart(path) }
            let limit = 32 * 1_024 * 1_024
            guard entry.uncompressedSize <= limit else { throw ReadError.oversizedPart(path) }
            var bytes = Data()
            let checksum = try archive.extract(entry) { chunk in
                try Task.checkCancellation()
                guard bytes.count + chunk.count <= limit else { throw ReadError.oversizedPart(path) }
                bytes.append(chunk)
            }
            guard checksum == entry.checksum else { throw Archive.ArchiveError.invalidCRC32 }
            return try OfficeXMLParser.read(bytes, path: path)
        }
        func relationships(_ part: String) throws -> [(id: String, type: String, path: String)] {
            let directory = (part as NSString).deletingLastPathComponent
            let name = (part as NSString).lastPathComponent
            let path = part.isEmpty ? "_rels/.rels" : "\(directory)/_rels/\(name).rels"
            guard archive[path] != nil else { return [] }
            return try xml(path).descendants("Relationship").compactMap { node in
                guard node.attributes["TargetMode"] != "External",
                      let target = node.attributes["Target"],
                      let id = node.attributes["Id"], let type = node.attributes["Type"] else { return nil }
                let absolute = target.hasPrefix("/") ? target : "/\(directory)/\(target)"
                let normalized = (absolute as NSString).standardizingPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                return (id, type, normalized)
            }
        }
        guard let main = try relationships("").first(where: { $0.type.hasSuffix("/officeDocument") }) else {
            throw ReadError.missingPart("officeDocument")
        }
        func paragraphs(_ root: OfficeXMLNode, part: String, heading: String? = nil, notesOnly: Bool = false) throws -> [Section] {
            let excluded = Set(root.descendants("sp").filter {
                ["sldImg", "sldNum", "dt", "hdr", "ftr"].contains($0.descendants("ph").first?.attributes["type"] ?? "")
            }.flatMap { $0.descendants("p").map(ObjectIdentifier.init) })
            return try root.descendants("p").enumerated().filter { !notesOnly || !excluded.contains(ObjectIdentifier($0.element)) }.map { index, paragraph in
                let style = paragraph.child("pPr")?.child("pStyle")?.value ?? ""
                let text = try paragraph.readableText().trimmingCharacters(in: .whitespacesAndNewlines)
                let isHeading = style.lowercased().hasPrefix("heading") || style.hasPrefix("标题")
                return Section(location: "\(part)#p\(index)", heading: isHeading ? text : heading, text: text)
            }.filter { !$0.text.isEmpty }
        }
        let document = try xml(main.path)
        switch kind {
        case .docx:
            var result = try paragraphs(document, part: main.path)
            for relation in try relationships(main.path) {
                let label: String
                if relation.type.hasSuffix("/footnotes") { label = "脚注" }
                else if relation.type.hasSuffix("/endnotes") { label = "尾注" }
                else if relation.type.hasSuffix("/comments") { label = "原文批注" }
                else { continue }
                result += try paragraphs(xml(relation.path), part: relation.path, heading: label)
            }
            return result
        case .pptx:
            let rels = try relationships(main.path)
            var result: [Section] = []
            for (index, slide) in document.descendants("sldId").enumerated() {
                guard let id = slide.attributes.first(where: { $0.key.hasSuffix(":id") })?.value, let part = rels.first(where: { $0.id == id })?.path else {
                    throw ReadError.missingPart("slide \(index + 1)")
                }
                let title = "第 \(index + 1) 页"
                result += try paragraphs(xml(part), part: part, heading: title)
                for note in try relationships(part) where note.type.hasSuffix("/notesSlide") {
                    result += try paragraphs(xml(note.path), part: note.path, heading: "\(title) · 备注", notesOnly: true)
                }
            }
            return result
        default:
            preconditionFailure("Office text extraction requires a Word or PowerPoint file")
        }
    }
}

private final class OfficeXMLNode {
    let name: String
    let attributes: [String: String]
    var text = ""
    var children: [OfficeXMLNode] = []
    init(_ name: String, _ attributes: [String: String]) {
        self.name = name.split(separator: ":").last.map(String.init) ?? name
        self.attributes = attributes
    }
    var value: String? { attributes["m:val"] ?? attributes["w:val"] ?? attributes["val"] }
    var enabled: Bool { !["0", "false", "off"].contains(value ?? "1") }
    func child(_ name: String) -> OfficeXMLNode? { children.first { $0.name == name } }
    var contentChildren: [OfficeXMLNode] {
        guard name == "AlternateContent" else { return children }
        return (children.first { $0.name == "Choice" && !$0.descendants("oMath").isEmpty }
            ?? child("Fallback"))?.children ?? []
    }
    func descendants(_ name: String) -> [OfficeXMLNode] {
        (self.name == name ? [self] : []) + contentChildren.flatMap { $0.descendants(name) }
    }
    func readableText() throws -> String {
        switch name {
        case "t": return text
        case "tab": return "\t"
        case "br", "cr": return "\n"
        case "del", "delText", "instrText", "txBodyPr": return ""
        case "oMath": return "$\(try mathSource())$"
        default: return try contentChildren.filter { $0.name != "p" }.map { try $0.readableText() }.joined()
        }
    }

    /// Keep equation structure in search/AI source text instead of flattening exponents and fractions.
    func mathSource() throws -> String {
        func part(_ name: String) throws -> String { try child(name)?.mathSource() ?? "" }
        func all() throws -> String { try children.filter { !$0.name.hasSuffix("Pr") }.map { try $0.mathSource() }.joined() }
        switch name {
        case "t": return text
        case "oMath", "e", "num", "den", "deg", "sub", "sup", "lim", "fName", "box", "borderBox": return try all()
        case "r":
            let source = try all()
            switch child("rPr")?.child("sty")?.value {
            case "b": return "\\mathbf{\(source)}"
            case "bi": return "\\boldsymbol{\(source)}"
            default: return source
            }
        case "f": return "\\frac{\(try part("num"))}{\(try part("den"))}"
        case "rad":
            let degree = child("radPr")?.child("degHide")?.enabled == true ? "" : try part("deg")
            return "\\sqrt\(degree.isEmpty ? "" : "[\(degree)]"){\(try part("e"))}"
        case "sSup": return "{\(try part("e"))}^{\(try part("sup"))}"
        case "sSub": return "{\(try part("e"))}_{\(try part("sub"))}"
        case "sSubSup": return "{\(try part("e"))}_{\(try part("sub"))}^{\(try part("sup"))}"
        case "sPre": return "{}_{\(try part("sub"))}^{\(try part("sup"))}{\(try part("e"))}"
        case "nary":
            let symbol = child("naryPr")?.child("chr")?.value ?? "∫"
            let sub = child("naryPr")?.child("subHide")?.enabled == true ? "" : try part("sub")
            let sup = child("naryPr")?.child("supHide")?.enabled == true ? "" : try part("sup")
            return "\(symbol)\(sub.isEmpty ? "" : "_{\(sub)}")\(sup.isEmpty ? "" : "^{\(sup)}") \(try part("e"))"
        case "d":
            let properties = child("dPr")
            let left = properties?.child("begChr")?.value ?? "("
            let right = properties?.child("endChr")?.value ?? ")"
            let separator = properties?.child("sepChr")?.value ?? "|"
            return left + (try children.filter { $0.name == "e" }.map { try $0.mathSource() }.joined(separator: separator)) + right
        case "m": return "\\begin{matrix}" + (try children.filter { $0.name == "mr" }.map { try $0.mathSource() }.joined(separator: " \\\\ ")) + "\\end{matrix}"
        case "mr": return try children.filter { $0.name == "e" }.map { try $0.mathSource() }.joined(separator: " & ")
        case "eqArr": return "\\begin{aligned}" + (try children.filter { $0.name == "e" }.map { try $0.mathSource() }.joined(separator: " \\\\ ")) + "\\end{aligned}"
        case "func": return "\(try part("fName")) \(try part("e"))"
        case "limLow": return "{\(try part("e"))}_{\(try part("lim"))}"
        case "limUpp": return "{\(try part("e"))}^{\(try part("lim"))}"
        case "acc": return "\\overset{\(child("accPr")?.child("chr")?.value ?? "ˆ")}{\(try part("e"))}"
        case "bar": return "\\\(child("barPr")?.child("pos")?.value == "bot" ? "underline" : "overline"){\(try part("e"))}"
        case "phant":
            return child("phantPr")?.child("show")?.enabled == true ? try part("e") : "\\phantom{\(try part("e"))}"
        case "groupChr":
            let properties = child("groupChrPr")
            return "\\\(properties?.child("pos")?.value == "top" ? "overset" : "underset"){\(properties?.child("chr")?.value ?? "⏟")}{\(try part("e"))}"
        default: throw OfficeDocumentText.ReadError.unsupportedEquation(name)
        }
    }
}

private final class OfficeXMLParser: NSObject, XMLParserDelegate {
    var root: OfficeXMLNode?
    var stack: [OfficeXMLNode] = []
    static func read(_ data: Data, path: String) throws -> OfficeXMLNode {
        let delegate = OfficeXMLParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else { throw OfficeDocumentText.ReadError.invalidXML(path) }
        return root
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        let node = OfficeXMLNode(name, attributes)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) { stack.removeLast() }
}
