import AppKit
import Foundation
import PDFKit
import WeiBeiCore

/**
 * 验证文档识别、PDF/OCR 和持久化搜索索引管线。
 */
enum DocumentPipelineSelfChecks {
    /**
     * 执行该领域的自检。
     */
    @MainActor
    static func run() async throws {

        expect(StudyItemKind.detect(from: URL(fileURLWithPath: "/tmp/a.pdf")) == .pdf, "pdf detection")
        expect(StudyItemKind.detect(from: URL(fileURLWithPath: "/tmp/a.html")) == .html, "html detection")
        expect(StudyItemKind.detect(from: URL(fileURLWithPath: "/tmp/a.md")) == .markdown, "markdown detection")
        expect(StudyItemKind.detect(from: URL(fileURLWithPath: "/tmp/a.txt")) == .text, "text detection")

        func makeSelectablePDF(at url: URL) {
            let data = NSMutableData()
            var mediaBox = CGRect(x: 0, y: 0, width: 420, height: 260)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
                expect(false, "create pdf context")
                return
            }
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            NSString(string: "PDF 可选文本层：利率是资金使用价格的表达。").draw(
                at: CGPoint(x: 42, y: 178),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 16),
                    .foregroundColor: NSColor.black
                ]
            )
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
            context.closePDF()
            expect(data.write(to: url, atomically: true), "write selectable pdf")
        }

        func makeImageOnlyPDF(at url: URL) {
            let image = NSImage(size: NSSize(width: 900, height: 260))
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: image.size).fill()
            NSString(string: "INTEREST RATE OCR PRICE").draw(
                at: CGPoint(x: 48, y: 96),
                withAttributes: [
                    .font: NSFont.boldSystemFont(ofSize: 54),
                    .foregroundColor: NSColor.black
                ]
            )
            image.unlockFocus()

            let document = PDFDocument()
            guard let page = PDFPage(image: image) else {
                expect(false, "create image-only pdf page")
                return
            }
            document.insert(page, at: 0)
            expect(document.write(to: url), "write image-only pdf")
        }

        func makeBlankImageOnlyPDF(at url: URL) {
            let image = NSImage(size: NSSize(width: 600, height: 300))
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: image.size).fill()
            image.unlockFocus()
            let document = PDFDocument()
            guard let page = PDFPage(image: image) else {
                expect(false, "create blank image-only pdf page")
                return
            }
            document.insert(page, at: 0)
            expect(document.write(to: url), "write blank image-only pdf")
        }

        let selectablePDFURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-selectable-pdf-check-\(UUID().uuidString).pdf")
        makeSelectablePDF(at: selectablePDFURL)
        defer { try? FileManager.default.removeItem(at: selectablePDFURL) }
        let selectablePDF = PDFDocument(url: selectablePDFURL)
        expect(selectablePDF?.string?.contains("利率是资金使用价格") == true, "PDFKit extracts text from selectable PDF text layer")
        let pdfSelections = selectablePDF?.findString("资金使用价格", withOptions: []) ?? []
        expect(pdfSelections.count == 1, "PDFKit finds selectable text in generated PDF")
        if let selection = pdfSelections.first, let page = selection.pages.first {
            expect(selection.string == "资金使用价格", "PDFSelection preserves selected text")
            let selectedPDFPageIndex = selectablePDF?.index(for: page)
            expect(selectedPDFPageIndex == 0, "PDFSelection resolves selected page index")
            expect(!selection.bounds(for: page).isEmpty, "PDFSelection exposes non-empty page bounds for floating agent anchor")
            let ownerTitle = "Mishkin 教材样例，第 \((selectedPDFPageIndex ?? 0) + 1) 页"
            let context = SelectionContext(text: selection.string ?? "", source: .document, ownerTitle: ownerTitle)
            let reference = SourceReferenceTitle.parse("来源：\(context.ownerTitle)")
            expect(context.label(language: .chinese) == "文档选区：Mishkin 教材样例，第 1 页", "PDF selection context carries the selected page label into the floating agent")
            expect(reference.title == "Mishkin 教材样例" && reference.pageIndex == 0, "PDF selection reference can jump back to the selected page")
        } else {
            expect(false, "PDFSelection contains page")
        }

        let imageOnlyPDFURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-image-only-pdf-check-\(UUID().uuidString).pdf")
        makeImageOnlyPDF(at: imageOnlyPDFURL)
        defer { try? FileManager.default.removeItem(at: imageOnlyPDFURL) }
        let imageOnlyPDF = PDFDocument(url: imageOnlyPDFURL)
        expect(imageOnlyPDF?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false, "image-only PDF has no native text layer")
        let ocrText = imageOnlyPDF.flatMap { PDFOCRTextExtractor.text(from: $0, maxPages: 1) }?.uppercased() ?? ""
        expect(ocrText.contains("INTEREST") && ocrText.contains("OCR") && ocrText.contains("PRICE"), "Vision OCR extracts text from image-only PDF pages")
        let ocrPages = imageOnlyPDF.map { PDFOCRTextExtractor.pages(from: $0, maxPages: 1) } ?? []
        expect(ocrPages.count == 1 && ocrPages[0].lines.contains { $0.text.uppercased().contains("INTEREST") && !$0.boundingBox.isEmpty }, "Vision OCR keeps page text bounds for scanned PDF selection overlays")
        let targetedOCRPages = imageOnlyPDF.map { PDFOCRTextExtractor.pages(from: $0, pageIndexes: [0]) } ?? []
        expect(targetedOCRPages.count == 1 && targetedOCRPages[0].pageIndex == 0, "Vision OCR can target a specific PDF page for mixed text and scanned documents")
        let outOfRangeOCRPages = imageOnlyPDF.map { PDFOCRTextExtractor.pages(from: $0, pageIndexes: [1]) } ?? []
        expect(outOfRangeOCRPages.isEmpty, "targeted OCR ignores pages outside the PDF")
        let blankImagePDFURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-blank-image-pdf-check-\(UUID().uuidString).pdf")
        makeBlankImageOnlyPDF(at: blankImagePDFURL)
        defer { try? FileManager.default.removeItem(at: blankImagePDFURL) }
        if let blankImagePDF = PDFDocument(url: blankImagePDFURL) {
            expect(
                PDFOCRTextExtractor.pageOutcome(from: blankImagePDF, pageIndex: 0) == .empty(pageIndex: 0),
                "Vision OCR distinguishes a successfully scanned blank page from an extraction failure"
            )
        } else {
            expect(false, "open blank image-only pdf")
        }

        func makeMixedLateOCRPDF(at url: URL) {
            let data = NSMutableData()
            var mediaBox = CGRect(x: 0, y: 0, width: 720, height: 420)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
                expect(false, "create mixed PDF context")
                return
            }

            for pageIndex in 0..<13 {
                context.beginPDFPage(nil)
                context.setFillColor(NSColor.white.cgColor)
                context.fill(mediaBox)
                if pageIndex < 12 {
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                    NSString(string: "Native text layer content for page \(pageIndex + 1) with enough characters").draw(
                        at: CGPoint(x: 48, y: 210),
                        withAttributes: [
                            .font: NSFont.systemFont(ofSize: 24),
                            .foregroundColor: NSColor.black,
                        ]
                    )
                    NSGraphicsContext.restoreGraphicsState()
                } else {
                    let image = NSImage(size: NSSize(width: 1_200, height: 500))
                    image.lockFocus()
                    NSColor.white.setFill()
                    NSRect(origin: .zero, size: image.size).fill()
                    NSString(string: "LATEPAGE OCR TARGET").draw(
                        at: CGPoint(x: 70, y: 190),
                        withAttributes: [
                            .font: NSFont.boldSystemFont(ofSize: 82),
                            .foregroundColor: NSColor.black,
                        ]
                    )
                    image.unlockFocus()
                    var imageRect = CGRect(origin: .zero, size: image.size)
                    if let cgImage = image.cgImage(forProposedRect: &imageRect, context: nil, hints: nil) {
                        context.draw(cgImage, in: CGRect(x: 35, y: 70, width: 650, height: 270))
                    }
                }
                context.endPDFPage()
            }
            context.closePDF()
            expect(data.write(to: url, atomically: true), "write mixed late-OCR PDF")
        }

        let courseIndexRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-course-index-check-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: courseIndexRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: courseIndexRoot) }
        let mixedPDFURL = courseIndexRoot.appendingPathComponent("mixed-late-ocr.pdf")
        makeMixedLateOCRPDF(at: mixedPDFURL)
        let mixedPDFItem = StudyItem(
            id: "file:\(mixedPDFURL.path)",
            title: "Mixed late OCR",
            subtitle: mixedPDFURL.lastPathComponent,
            kind: .pdf,
            urlPath: mixedPDFURL.path,
            isSample: false
        )
        let markdownIndexURL = courseIndexRoot.appendingPathComponent("late-section.md")
        let lateMarkdownToken = "PERSISTENT_LATE_INDEX_TOKEN"
        try? (String(repeating: "ordinary material\n\n", count: 1_500) + lateMarkdownToken)
            .write(to: markdownIndexURL, atomically: true, encoding: .utf8)
        let markdownIndexItem = StudyItem(
            id: "file:\(markdownIndexURL.path)",
            title: "Late markdown section",
            subtitle: markdownIndexURL.lastPathComponent,
            kind: .markdown,
            urlPath: markdownIndexURL.path,
            isSample: false
        )
        let stableHTMLURL = courseIndexRoot.appendingPathComponent("stable-sections.html")
        let stableHTMLOriginal = """
        <html><body>
        <h1>利率</h1><p>ORIGINAL_ALPHA_SECTION 资金价格。</p>
        <h2>利率</h2><p>ORIGINAL_BETA_SECTION 购买力变化。</p>
        </body></html>
        """
        try? stableHTMLOriginal.write(to: stableHTMLURL, atomically: true, encoding: .utf8)
        let stableHTMLItem = StudyItem(
            id: "file:\(stableHTMLURL.path)",
            title: "Stable duplicate sections",
            subtitle: stableHTMLURL.lastPathComponent,
            kind: .html,
            urlPath: stableHTMLURL.path,
            isSample: false
        )
        let blankPDFIndexItem = StudyItem(
            id: "file:\(blankImagePDFURL.path)",
            title: "Blank scanned page",
            subtitle: blankImagePDFURL.lastPathComponent,
            kind: .pdf,
            urlPath: blankImagePDFURL.path,
            isSample: false
        )
        let courseIndexDatabaseURL = courseIndexRoot.appendingPathComponent("course-search.sqlite3")
        let courseIndex = CourseDocumentSearchIndex(databaseURL: courseIndexDatabaseURL)
        expect(
            BoundedPDFTextExtractor.runSafetySelfCheck(),
            "bounded PDF worker passes normal execution, timeout, cancellation, memory, and output-overflow probes"
        )
        let boundedNativeProbe = BoundedPDFTextExtractor.pages(
            from: mixedPDFURL,
            pageIndexes: Array(0..<8),
            maximumCharactersPerPage: 128_000,
            timeout: 3.5
        )
        if boundedNativeProbe?[0]?.text.contains("Native text layer content for page 1") != true {
            fputs("bounded native PDF diagnostic: \(String(describing: boundedNativeProbe))\n", stderr)
        }
        expect(
            boundedNativeProbe?[0]?.text.contains("Native text layer content for page 1") == true,
            "bounded PDF worker returns native text for a generated multi-page PDF"
        )
        courseIndex.schedule([mixedPDFItem, markdownIndexItem, stableHTMLItem, blankPDFIndexItem])
        var mixedIndexResult: CourseDocumentIndexResult?
        var markdownIndexResult: CourseDocumentIndexResult?
        var blankPDFIndexResult: CourseDocumentIndexResult?
        var stableHTMLIndexResult: CourseDocumentIndexResult?
        for _ in 0..<600 {
            mixedIndexResult = courseIndex.lookup(items: [mixedPDFItem], query: "LATEPAGE OCR TARGET")[mixedPDFItem.id]
            markdownIndexResult = courseIndex.lookup(items: [markdownIndexItem], query: lateMarkdownToken)[markdownIndexItem.id]
            blankPDFIndexResult = courseIndex.lookup(items: [blankPDFIndexItem], query: "blank page")[blankPDFIndexItem.id]
            stableHTMLIndexResult = courseIndex.lookup(items: [stableHTMLItem], query: "ORIGINAL_ALPHA_SECTION ORIGINAL_BETA_SECTION")[stableHTMLItem.id]
            if mixedIndexResult?.text?.uppercased().contains("LATEPAGE") == true,
               markdownIndexResult?.text?.contains(lateMarkdownToken) == true,
               stableHTMLIndexResult?.text?.contains("ORIGINAL_ALPHA_SECTION") == true,
               blankPDFIndexResult?.isTruncated == false {
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        expect(
            mixedIndexResult?.isTruncated == true
                && mixedIndexResult?.text?.uppercased().contains("LATEPAGE") == true
                && mixedIndexResult?.text?.contains("第 13 页（OCR）") == true,
            "persistent course index OCRs a scanned page beyond page twelve, keeps its page location, and marks the returned excerpt partial"
        )
        let nativePDFIndexResult = courseIndex.lookup(
            items: [mixedPDFItem],
            query: "Native text layer content for page 1"
        )[mixedPDFItem.id]
        if nativePDFIndexResult?.text?.contains("Native text layer content for page 1") != true
            || nativePDFIndexResult?.text?.contains("第 1 页（OCR）") == true {
            fputs("native PDF index diagnostic: \(nativePDFIndexResult?.text ?? "<nil>")\n", stderr)
        }
        expect(
            nativePDFIndexResult?.text?.contains("Native text layer content for page 1") == true
                && nativePDFIndexResult?.text?.contains("第 1 页（OCR）") != true,
            "persistent course index executes the bounded worker and preserves a real native PDF text-layer result"
        )
        let indexedPDFCourseContext = CourseKnowledgeIndex.build(
            title: "Indexed PDF",
            sources: [
                CourseKnowledgeSource(
                    id: mixedPDFItem.id,
                    title: mixedPDFItem.title,
                    subtitle: mixedPDFItem.subtitle,
                    kind: mixedPDFItem.kind.rawValue,
                    role: "material",
                    text: mixedIndexResult?.text ?? "",
                    isTruncated: mixedIndexResult?.isTruncated ?? true
                ),
            ],
            links: [],
            query: "LATEPAGE OCR TARGET",
            currentMaterialID: nil,
            currentNoteID: nil
        )
        expect(
            indexedPDFCourseContext.items.first?.headings.contains("第 13 页（OCR）") == true,
            "course search preserves confirmed OCR page locations for exact PDF jumps"
        )
        if blankPDFIndexResult?.isTruncated != false || blankPDFIndexResult?.text != nil {
            fputs("blank PDF index diagnostic: \(String(describing: blankPDFIndexResult))\n", stderr)
        }
        expect(
            blankPDFIndexResult?.isTruncated == false && blankPDFIndexResult?.text == nil,
            "persistent course index records a successfully scanned blank PDF page without retrying it forever"
        )
        expect(
            markdownIndexResult?.isTruncated == true
                && markdownIndexResult?.text?.contains(lateMarkdownToken) == true,
            "persistent course index finds a late text-file section without per-question rescanning and marks the excerpt partial"
        )
        func stableHTMLSectionIDs(in text: String) -> Set<String> {
            guard let regex = try? NSRegularExpression(pattern: #"\[(html-section-[A-Za-z0-9-]+)\]"#) else {
                return []
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return Set(regex.matches(in: text, range: range).compactMap { match in
                guard match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: text) else { return nil }
                return String(text[range])
            })
        }
        let originalStableSectionIDs = stableHTMLSectionIDs(in: stableHTMLIndexResult?.text ?? "")
        let stableHTMLWithInsertedDuplicate = """
        <html><body>
        <h1>利率</h1><p>NEW_INSERTED_SECTION 新增解释。</p>
        <h1>利率</h1><p>ORIGINAL_ALPHA_SECTION 资金价格。</p>
        <h2>利率</h2><p>ORIGINAL_BETA_SECTION 购买力变化。</p>
        </body></html>
        """
        try? stableHTMLWithInsertedDuplicate.write(to: stableHTMLURL, atomically: true, encoding: .utf8)
        let refreshedStableHTML = courseIndex.lookup(
            items: [stableHTMLItem],
            query: "ORIGINAL_ALPHA_SECTION ORIGINAL_BETA_SECTION"
        )[stableHTMLItem.id]
        let refreshedStableSectionIDs = stableHTMLSectionIDs(in: refreshedStableHTML?.text ?? "")
        expect(
            originalStableSectionIDs.count == 2
                && originalStableSectionIDs.isSubset(of: refreshedStableSectionIDs)
                && refreshedStableSectionIDs.count == 3,
            "HTML section content fingerprints survive insertion of a new same-title section before existing sections"
        )
        let reopenedCourseIndex = CourseDocumentSearchIndex(databaseURL: courseIndexDatabaseURL)
        reopenedCourseIndex.schedule([mixedPDFItem])
        let reopenedResult = reopenedCourseIndex.lookup(
            items: [mixedPDFItem],
            query: "LATEPAGE OCR TARGET"
        )[mixedPDFItem.id]
        expect(
            reopenedResult?.isTruncated == true
                && reopenedResult?.text?.uppercased().contains("LATEPAGE") == true,
            "course full-text index survives reopening without rebuilding the PDF"
        )

        let splitFailureIndex = CourseDocumentSearchIndex(
            databaseURL: courseIndexRoot.appendingPathComponent("course-search-split-failure.sqlite3"),
            nativePDFTextLoader: { _, pageIndexes, _, _ in
                guard pageIndexes.count == 1, let pageIndex = pageIndexes.first else { return nil }
                let text = pageIndex < 12
                    ? "SPLIT_NATIVE_LAYER_PAGE_\(pageIndex + 1) remains native after a failed batch extraction"
                    : ""
                return [pageIndex: BoundedPDFTextPage(text: text, isPartial: false)]
            }
        )
        splitFailureIndex.schedule([mixedPDFItem])
        var splitFailureResult: CourseDocumentIndexResult?
        for _ in 0..<200 {
            splitFailureResult = splitFailureIndex.lookup(
                items: [mixedPDFItem],
                query: "SPLIT_NATIVE_LAYER_PAGE_1"
            )[mixedPDFItem.id]
            if splitFailureResult?.text?.contains("SPLIT_NATIVE_LAYER_PAGE_1") == true { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        expect(
            splitFailureResult?.text?.contains("SPLIT_NATIVE_LAYER_PAGE_1") == true
                && splitFailureResult?.text?.contains("第 1 页（OCR）") != true,
            "a failed native PDF batch is bisected to single pages instead of sending unattempted text pages to OCR"
        )
    }
}
