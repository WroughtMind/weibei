import Foundation

/**
 * Normalizes user and document text into the FTS terms used by the course index.
 */
enum CourseSearchQuery {
    /**
     * Produces stable, de-duplicated Latin tokens and Chinese bigrams.
     *
     * - Parameter text: User query or indexed document text.
     * - Returns: Terms in first-seen order.
     */
    static func terms(in text: String) -> [String] {
        let lower = text.lowercased()
        var terms = lower
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).inverted)
            .filter { $0.count >= 2 }
        var run = ""
        for scalar in lower.unicodeScalars {
            if (0x4E00...0x9FFF).contains(Int(scalar.value)) {
                run.unicodeScalars.append(scalar)
            } else if !run.isEmpty {
                appendChineseTerms(from: run, to: &terms)
                run = ""
            }
        }
        if !run.isEmpty { appendChineseTerms(from: run, to: &terms) }
        var seen: Set<String> = []
        return terms.filter { term in
            seen.insert(term).inserted
        }
    }

    private static func appendChineseTerms(from run: String, to terms: inout [String]) {
        if run.count <= 20 { terms.append(run) }
        let characters = Array(run)
        guard characters.count >= 2 else { return }
        for index in 0..<(characters.count - 1) {
            terms.append(String(characters[index...index + 1]))
        }
    }
}
