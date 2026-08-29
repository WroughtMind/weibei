import { readFile } from "node:fs/promises";
import type { StudyItemKind } from "../../shared/contracts";
import type { ProcessedPageInput, SearchTextChunk, UpsertTextChunksInput } from "./search-index";

const targetChunkCharacters = 1_600;
const chunkOverlapCharacters = 180;

export async function extractSearchDocument(options: {
  itemId: string;
  signature: string;
  kind: StudyItemKind;
  filePath: string;
}): Promise<UpsertTextChunksInput> {
  if (options.kind === "pdf") return extractPDF({ ...options, kind: "pdf" });
  const content = await readFile(options.filePath, "utf8");
  const normalized = options.kind === "html" ? htmlToText(content) : content;
  return {
    itemId: options.itemId,
    signature: options.signature,
    kind: options.kind,
    chunks: chunkText(normalized, options.kind === "markdown" ? "Markdown" : "正文"),
    pageCount: 1,
    isComplete: true,
  };
}

async function extractPDF(options: {
  itemId: string;
  signature: string;
  kind: "pdf";
  filePath: string;
}): Promise<UpsertTextChunksInput> {
  const pdfjs = await import("pdfjs-dist/legacy/build/pdf.mjs");
  const bytes = new Uint8Array(await readFile(options.filePath));
  const task = pdfjs.getDocument({
    data: bytes,
    useSystemFonts: false,
  });
  const chunks: SearchTextChunk[] = [];
  const processedPages: ProcessedPageInput[] = [];
  const nativeAttemptedPageIndexes: number[] = [];
  let pageCount = 0;
  try {
    const document = await task.promise;
    pageCount = document.numPages;
    for (let pageIndex = 0; pageIndex < document.numPages; pageIndex += 1) {
      nativeAttemptedPageIndexes.push(pageIndex);
      try {
        const page = await document.getPage(pageIndex + 1);
        const textContent = await page.getTextContent();
        const text = textContent.items
          .map((item) => "str" in item && typeof item.str === "string" ? item.str : "")
          .join(" ")
          .replace(/\s+/gu, " ")
          .trim();
        if (!text) {
          // Truthful incomplete coverage: bundled OCR may later replace this
          // marker. Never report an image-only page as successfully indexed.
          processedPages.push({ pageIndex, extractionKind: "ocr-failed-unavailable" });
          continue;
        }
        processedPages.push({ pageIndex, extractionKind: "text" });
        chunks.push(...chunkText(text, `第 ${pageIndex + 1} 页`, chunks.length));
      } catch {
        processedPages.push({ pageIndex, extractionKind: "ocr-failed-pdf-read" });
      }
    }
    await document.cleanup();
  } finally {
    await task.destroy();
  }
  const failed = processedPages.some((page) => page.extractionKind.startsWith("ocr-failed-"));
  return {
    itemId: options.itemId,
    signature: options.signature,
    kind: "pdf",
    chunks,
    pageCount,
    processedPages,
    nativeAttemptedPageIndexes,
    isComplete: !failed && processedPages.length === pageCount,
  };
}

function chunkText(source: string, location: string, startingOrder = 0): SearchTextChunk[] {
  const text = source.replace(/\r\n?/gu, "\n").trim();
  if (!text) return [];
  const chunks: SearchTextChunk[] = [];
  let offset = 0;
  while (offset < text.length) {
    let end = Math.min(text.length, offset + targetChunkCharacters);
    if (end < text.length) {
      const boundary = Math.max(text.lastIndexOf("\n", end), text.lastIndexOf("。", end), text.lastIndexOf(" ", end));
      if (boundary > offset + targetChunkCharacters / 2) end = boundary + 1;
    }
    const value = text.slice(offset, end).trim();
    if (value) chunks.push({ text: value, location, sortOrder: startingOrder + chunks.length });
    if (end >= text.length) break;
    offset = Math.max(offset + 1, end - chunkOverlapCharacters);
  }
  return chunks;
}

function htmlToText(html: string): string {
  return html
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/giu, " ")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/giu, " ")
    .replace(/<\/(?:p|div|section|article|h[1-6]|li|blockquote|tr)>/giu, "\n")
    .replace(/<br\s*\/?>/giu, "\n")
    .replace(/<[^>]+>/gu, " ")
    .replace(/&nbsp;/giu, " ")
    .replace(/&amp;/giu, "&")
    .replace(/&lt;/giu, "<")
    .replace(/&gt;/giu, ">")
    .replace(/&quot;/giu, '"')
    .replace(/&#39;/giu, "'")
    .replace(/[ \t]+/gu, " ")
    .replace(/\n{3,}/gu, "\n\n");
}
