interface CourseCatalogItem {
  id: string;
  role: string;
  title: string;
}

interface CourseSearchItem extends CourseCatalogItem {
  subtitle: string;
  headings: string[];
  tags: string[];
  searchText: string;
  isCurrentMaterial: boolean;
  isCurrentNote: boolean;
}

interface CourseSnapshot<Item extends CourseCatalogItem = CourseCatalogItem> {
  catalog: Item[];
}

/**
 * Tokenizes mixed Chinese and Latin queries for the bounded local course search.
 */
export function courseSearchTerms(query: string): string[] {
  const lower = query.toLowerCase();
  const terms: string[] = lower.match(/[\p{L}\p{N}_-]{2,}/gu) ?? [];
  const chineseRuns: string[] = lower.match(/[\u4e00-\u9fff]{2,}/g) ?? [];
  for (const run of chineseRuns) {
    if (run.length <= 20) terms.push(run);
    for (let index = 0; index < run.length - 1; index += 1) {
      terms.push(run.slice(index, index + 2));
    }
  }
  return Array.from(new Set(terms)).sort((left, right) => right.length - left.length);
}

/**
 * Ranks the in-memory course excerpts without exposing filesystem search.
 */
export function searchCourse<Item extends CourseSearchItem>(
  course: { items: Item[] },
  query: string,
  limit: number,
): Item[] {
  const terms = courseSearchTerms(query);
  return course.items
    .map((item, index) => {
      const title = `${item.title} ${item.subtitle} ${item.headings.join(" ")} ${item.tags.join(" ")}`.toLowerCase();
      const body = item.searchText.toLowerCase();
      const score = terms.reduce((total, term) => {
        const titleMatches = title.split(term).length - 1;
        const bodyMatches = Math.min(body.split(term).length - 1, 8);
        return total + titleMatches * 8 + bodyMatches;
      }, item.isCurrentMaterial || item.isCurrentNote ? 1 : 0);
      return { item, index, score };
    })
    .filter((entry) => entry.score > 0 || terms.length === 0)
    .sort((left, right) => right.score - left.score || left.index - right.index)
    .slice(0, limit)
    .map((entry) => entry.item);
}

/**
 * Parses a stored course heading into stable navigation fields.
 */
export function courseHeading(rawHeading: string): { title: string; ordinal?: number; locationID?: string } {
  const stableMatch = rawHeading.match(/^\[(html-section-[A-Za-z0-9-]+)\]\[html-heading-(\d+)\]\s+(.+)$/);
  if (stableMatch) {
    return {
      title: stableMatch[3],
      ordinal: Number(stableMatch[2]) + 1,
      locationID: stableMatch[1],
    };
  }
  const stableOnlyMatch = rawHeading.match(/^\[(html-section-[A-Za-z0-9-]+)\]\s+(.+)$/);
  if (stableOnlyMatch) return { title: stableOnlyMatch[2], locationID: stableOnlyMatch[1] };
  const legacyMatch = rawHeading.match(/^\[html-heading-(\d+)\]\s+(.+)$/);
  if (!legacyMatch) return { title: rawHeading };
  return { title: legacyMatch[2], ordinal: Number(legacyMatch[1]) + 1 };
}

/**
 * Parses the persisted PDF heading convention into a one-based page.
 */
export function coursePage(rawHeading: string): number | undefined {
  const match = rawHeading.match(/^第\s*(\d+)\s*页(?:（OCR）)?$/);
  if (!match) return undefined;
  const page = Number(match[1]);
  return Number.isInteger(page) && page > 0 ? page : undefined;
}

/**
 * Builds the host-readable jump reference used by course results.
 */
export function courseJumpReference<Item extends CourseCatalogItem>(
  course: CourseSnapshot<Item>,
  item: Item,
  rawHeading?: string,
): string {
  const duplicateTitle = course.catalog.filter((candidate) => candidate.title === item.title).length > 1;
  const ordinal = course.catalog.findIndex((candidate) => candidate.id === item.id) + 1;
  const ordinalSuffix = duplicateTitle && ordinal > 0 ? `，条目：${ordinal}` : "";
  const page = rawHeading ? coursePage(rawHeading) : undefined;
  const heading = rawHeading && !page ? courseHeading(rawHeading) : undefined;
  const pageSuffix = page ? `，第 ${page} 页` : "";
  const sectionLocationSuffix = heading?.locationID ? `，章节标识：${heading.locationID}` : "";
  const sectionOrdinalSuffix = heading?.ordinal ? `，章节序号：${heading.ordinal}` : "";
  const sectionSuffix = heading?.title ? `，章节：${heading.title}` : "";
  return `来源：${item.title}${ordinalSuffix}${pageSuffix}${sectionLocationSuffix}${sectionOrdinalSuffix}${sectionSuffix}`;
}

/**
 * Builds a stable evidence label and disambiguates duplicate course titles.
 */
export function courseEvidenceLabel<Item extends CourseCatalogItem>(
  course: CourseSnapshot<Item>,
  item: Item,
): string {
  const duplicateTitle = course.catalog.filter((candidate) => candidate.title === item.title).length > 1;
  const ordinal = course.catalog.findIndex((candidate) => candidate.id === item.id) + 1;
  const ordinalSuffix = duplicateTitle && ordinal > 0 ? `，条目：${ordinal}` : "";
  return item.role === "note"
    ? `[笔记：${item.title}${ordinalSuffix}]`
    : `[材料：${item.title}${ordinalSuffix}]`;
}

/**
 * Resolves the last study location into the same jump-reference contract.
 */
export function learningLocationJumpReference<Item extends CourseCatalogItem>(snapshot: {
  course: CourseSnapshot<Item>;
  learning: {
    lastLocation?: {
      itemID: string;
      pageIndex?: number;
      locationID?: string;
      locationTitle?: string;
    };
  };
}): string | undefined {
  const location = snapshot.learning.lastLocation;
  if (!location) return undefined;
  const item = snapshot.course.catalog.find((candidate) => candidate.id === location.itemID);
  if (!item) return undefined;
  if (location.pageIndex && location.pageIndex > 0) {
    return courseJumpReference(snapshot.course, item, `第 ${location.pageIndex} 页`);
  }
  if (
    (location.locationID?.startsWith("html-section-") ||
      location.locationID?.startsWith("html-heading-")) &&
    location.locationTitle
  ) {
    return courseJumpReference(snapshot.course, item, `[${location.locationID}] ${location.locationTitle}`);
  }
  return courseJumpReference(snapshot.course, item);
}
