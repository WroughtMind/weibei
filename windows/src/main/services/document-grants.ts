import { randomBytes } from "node:crypto";
import { open, realpath, stat, type FileHandle } from "node:fs/promises";
import path from "node:path";
import { Readable } from "node:stream";

export const documentGrantScheme = "weibei-document";
export const documentGrantHost = "grant";
export const documentGrantSchemePrivileges = Object.freeze({
  standard: true,
  secure: true,
  supportFetchAPI: true,
  stream: true,
  corsEnabled: true,
});

const tokenPattern = /^[A-Za-z0-9_-]{43}$/u;
const maximumScopeLength = 256;
const defaultTTLMS = 30 * 60 * 1000;
const maximumTTLMS = 24 * 60 * 60 * 1000;
const maximumActiveGrants = 4_096;
const maximumRangeHeaderLength = 256;
const maximumStreamableFileSize = BigInt(Number.MAX_SAFE_INTEGER);

export interface DocumentGrantServiceOptions {
  now?: () => number;
  defaultTTLMS?: number;
  maximumTTLMS?: number;
  maximumActiveGrants?: number;
}

export interface IssueDocumentGrantOptions {
  /** Directory capability within which the file must resolve. */
  rootPath: string;
  /** Absolute path or a path relative to rootPath. */
  filePath: string;
  /** Trusted owner, normally a renderer/session capability identifier. */
  scope: string;
  ttlMS?: number;
  mediaType?: string;
}

export interface IssuedDocumentGrant {
  url: string;
  expiresAtMS: number;
}

export type DocumentGrantErrorCode =
  | "invalid-path"
  | "outside-root"
  | "not-a-regular-file"
  | "invalid-scope"
  | "invalid-ttl"
  | "invalid-media-type"
  | "too-many-grants"
  | "file-too-large";

export class DocumentGrantError extends Error {
  readonly code: DocumentGrantErrorCode;

  constructor(code: DocumentGrantErrorCode, message: string, options?: ErrorOptions) {
    super(message, options);
    this.name = "DocumentGrantError";
    this.code = code;
  }
}

interface StoredGrant {
  token: string;
  scope: string;
  expiresAtMS: number;
  rootPath: string;
  candidatePath: string;
  canonicalRoot: string;
  canonicalTarget: string;
  mediaType: string;
}

interface OpenGrantedFile {
  handle: FileHandle;
  size: bigint;
}

/**
 * Ephemeral file capabilities for the `weibei-document://` protocol.
 *
 * The service deliberately returns no absolute path or file bytes. Protocol
 * consumers receive an opaque URL, and every request revalidates the real path
 * before a FileHandle-backed stream is created.
 */
export class DocumentGrantService {
  private readonly now: () => number;
  private readonly defaultTTLMS: number;
  private readonly maximumTTLMS: number;
  private readonly maximumActiveGrants: number;
  private readonly grants = new Map<string, StoredGrant>();

  constructor(options: DocumentGrantServiceOptions = {}) {
    this.now = options.now ?? Date.now;
    this.defaultTTLMS = validateTTL(options.defaultTTLMS ?? defaultTTLMS, maximumTTLMS);
    this.maximumTTLMS = validateTTL(options.maximumTTLMS ?? maximumTTLMS, maximumTTLMS);
    if (this.defaultTTLMS > this.maximumTTLMS) {
      throw new DocumentGrantError(
        "invalid-ttl",
        "Default document grant lifetime exceeds the configured maximum.",
      );
    }
    const grantLimit = options.maximumActiveGrants ?? maximumActiveGrants;
    if (!Number.isSafeInteger(grantLimit) || grantLimit < 1) {
      throw new DocumentGrantError(
        "too-many-grants",
        "Document grant capacity is invalid.",
      );
    }
    this.maximumActiveGrants = grantLimit;
  }

  async issue(options: IssueDocumentGrantOptions): Promise<IssuedDocumentGrant> {
    const scope = validateScope(options.scope);
    const ttlMS = validateTTL(options.ttlMS ?? this.defaultTTLMS, this.maximumTTLMS);
    const issuedAt = safeNow(this.now());
    if (issuedAt > Number.MAX_SAFE_INTEGER - ttlMS) {
      throw new DocumentGrantError("invalid-ttl", "Document grant lifetime overflows.");
    }

    const paths = await resolveGrantPaths(options.rootPath, options.filePath);
    const targetStats = await stat(paths.canonicalTarget, { bigint: true });
    if (!targetStats.isFile()) {
      throw new DocumentGrantError(
        "not-a-regular-file",
        "Document grant target is not a regular file.",
      );
    }
    if (targetStats.size > maximumStreamableFileSize) {
      throw new DocumentGrantError(
        "file-too-large",
        "Document grant target exceeds the stream size limit.",
      );
    }

    this.removeExpired(issuedAt);
    if (this.grants.size >= this.maximumActiveGrants) {
      throw new DocumentGrantError(
        "too-many-grants",
        "Document grant capacity has been reached.",
      );
    }

    const token = this.makeUniqueToken();
    const mediaType = validateMediaType(
      options.mediaType ?? inferMediaType(paths.canonicalTarget),
    );
    const grant: StoredGrant = {
      token,
      scope,
      expiresAtMS: issuedAt + ttlMS,
      ...paths,
      mediaType,
    };
    this.grants.set(token, grant);
    return Object.freeze({
      url: `${documentGrantScheme}://${documentGrantHost}/${token}`,
      expiresAtMS: grant.expiresAtMS,
    });
  }

  revoke(urlOrToken: string, scope: string): boolean {
    const token = tokenFromInput(urlOrToken);
    if (!token) return false;
    const expectedScope = validateScope(scope);
    const grant = this.grants.get(token);
    if (!grant || grant.scope !== expectedScope) return false;
    return this.grants.delete(token);
  }

  revokeScope(scope: string): number {
    const expected = validateScope(scope);
    let revoked = 0;
    for (const [token, grant] of this.grants) {
      if (grant.scope !== expected) continue;
      this.grants.delete(token);
      revoked += 1;
    }
    return revoked;
  }

  /**
   * Handler suitable for `session.protocol.handle`. The registration site must
   * bind `expectedScope` from trusted main-process state, never from a query
   * parameter or renderer-provided header.
   */
  async handleRequest(request: Request, expectedScope: string): Promise<Response> {
    const token = parseDocumentGrantURL(request.url);
    if (!token) return responseWithSecurityHeaders(400);

    const method = request.method.toUpperCase();
    if (method !== "GET" && method !== "HEAD") {
      return responseWithSecurityHeaders(405, { Allow: "GET, HEAD" });
    }

    let scope: string;
    try {
      scope = validateScope(expectedScope);
    } catch {
      return responseWithSecurityHeaders(404);
    }

    const now = safeNow(this.now());
    const grant = this.grants.get(token);
    if (!grant || grant.scope !== scope || grant.expiresAtMS <= now) {
      if (grant?.expiresAtMS !== undefined && grant.expiresAtMS <= now) {
        this.grants.delete(token);
      }
      return responseWithSecurityHeaders(404);
    }

    let opened: OpenGrantedFile;
    try {
      opened = await openAndRevalidate(grant);
    } catch {
      // Missing, replaced, inaccessible, or escaped files all fail closed and
      // deliberately reveal no host path or filesystem error to the renderer.
      return responseWithSecurityHeaders(404);
    }

    const commonHeaders: Record<string, string> = {
      "Accept-Ranges": "bytes",
      "Access-Control-Allow-Headers": "Range",
      "Access-Control-Allow-Methods": "GET, HEAD",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Expose-Headers": "Accept-Ranges, Content-Length, Content-Range",
      "Cache-Control": "no-store",
      "Content-Type": grant.mediaType,
      "Cross-Origin-Resource-Policy": "cross-origin",
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
    };

    const rangeHeader = request.headers.get("range");
    const range = rangeHeader === null ? null : parseRange(rangeHeader, opened.size);
    if (rangeHeader !== null && range === null) {
      await opened.handle.close();
      return responseWithSecurityHeaders(416, {
        ...commonHeaders,
        "Content-Range": `bytes */${opened.size.toString()}`,
        "Content-Length": "0",
      });
    }

    if (range) {
      const contentLength = range.end - range.start + 1n;
      const headers = {
        ...commonHeaders,
        "Content-Length": contentLength.toString(),
        "Content-Range": `bytes ${range.start.toString()}-${range.end.toString()}/${opened.size.toString()}`,
      };
      if (method === "HEAD") {
        await opened.handle.close();
        return responseWithSecurityHeaders(206, headers);
      }
      return streamResponse(opened.handle, 206, headers, range);
    }

    const headers = {
      ...commonHeaders,
      "Content-Length": opened.size.toString(),
    };
    if (method === "HEAD") {
      await opened.handle.close();
      return responseWithSecurityHeaders(200, headers);
    }
    if (opened.size === 0n) {
      await opened.handle.close();
      return responseWithSecurityHeaders(200, headers);
    }
    return streamResponse(opened.handle, 200, headers, {
      start: 0n,
      end: opened.size - 1n,
    });
  }

  private removeExpired(now: number): void {
    for (const [token, grant] of this.grants) {
      if (grant.expiresAtMS <= now) this.grants.delete(token);
    }
  }

  private makeUniqueToken(): string {
    for (let attempt = 0; attempt < 8; attempt += 1) {
      const token = randomBytes(32).toString("base64url");
      if (!this.grants.has(token)) return token;
    }
    throw new DocumentGrantError(
      "too-many-grants",
      "A unique document grant could not be generated.",
    );
  }
}

export function parseDocumentGrantURL(input: string): string | null {
  if (typeof input !== "string" || input.length > 128) return null;
  let parsed: URL;
  try {
    parsed = new URL(input);
  } catch {
    return null;
  }
  if (
    parsed.protocol !== `${documentGrantScheme}:` ||
    parsed.hostname !== documentGrantHost ||
    parsed.username !== "" ||
    parsed.password !== "" ||
    parsed.port !== "" ||
    parsed.search !== "" ||
    parsed.hash !== ""
  ) {
    return null;
  }
  const match = /^\/([A-Za-z0-9_-]{43})$/u.exec(parsed.pathname);
  return match?.[1] ?? null;
}

function tokenFromInput(input: string): string | null {
  if (tokenPattern.test(input)) return input;
  return parseDocumentGrantURL(input);
}

async function resolveGrantPaths(
  rootPath: string,
  filePath: string,
): Promise<Pick<StoredGrant, "rootPath" | "candidatePath" | "canonicalRoot" | "canonicalTarget">> {
  if (
    typeof rootPath !== "string" ||
    typeof filePath !== "string" ||
    !rootPath ||
    !filePath ||
    rootPath.includes("\u0000") ||
    filePath.includes("\u0000")
  ) {
    throw new DocumentGrantError("invalid-path", "Document grant path is invalid.");
  }

  const resolvedRoot = path.resolve(rootPath);
  const candidatePath = path.isAbsolute(filePath)
    ? path.resolve(filePath)
    : path.resolve(resolvedRoot, filePath);
  if (process.platform === "win32") {
    const relativeCandidate = path.relative(resolvedRoot, candidatePath);
    if (relativeCandidate.split(path.sep).some((component) => component.includes(":"))) {
      throw new DocumentGrantError(
        "invalid-path",
        "Windows alternate data streams are not valid document targets.",
      );
    }
  }

  let canonicalRoot: string;
  let canonicalTarget: string;
  try {
    [canonicalRoot, canonicalTarget] = await Promise.all([
      realpath(resolvedRoot),
      realpath(candidatePath),
    ]);
  } catch (error) {
    throw new DocumentGrantError(
      "invalid-path",
      "Document grant path could not be resolved.",
      { cause: error },
    );
  }

  const rootStats = await stat(canonicalRoot);
  if (!rootStats.isDirectory()) {
    throw new DocumentGrantError(
      "invalid-path",
      "Document grant root is not a directory.",
    );
  }
  await assertContained(canonicalRoot, canonicalTarget);
  return {
    rootPath: resolvedRoot,
    candidatePath,
    canonicalRoot,
    canonicalTarget,
  };
}

async function openAndRevalidate(grant: StoredGrant): Promise<OpenGrantedFile> {
  const handle = await open(grant.canonicalTarget, "r");
  try {
    const [currentRoot, currentTarget, handleStats] = await Promise.all([
      realpath(grant.rootPath),
      realpath(grant.candidatePath),
      handle.stat({ bigint: true }),
    ]);
    if (
      !samePath(currentRoot, grant.canonicalRoot) ||
      !samePath(currentTarget, grant.canonicalTarget)
    ) {
      throw new Error("document capability target changed");
    }
    await assertContained(currentRoot, currentTarget);
    if (!handleStats.isFile()) throw new Error("document target is not regular");
    if (handleStats.size > maximumStreamableFileSize) {
      throw new Error("document target is too large");
    }

    // Confirm that the path still names the same object as the already-open
    // handle. On filesystems that expose stable inode data this narrows the
    // realpath/open race without reopening the file for the response body.
    const currentStats = await stat(currentTarget, { bigint: true });
    if (
      !currentStats.isFile() ||
      currentStats.dev !== handleStats.dev ||
      (currentStats.ino !== 0n && handleStats.ino !== 0n && currentStats.ino !== handleStats.ino)
    ) {
      throw new Error("document capability identity changed");
    }
    return { handle, size: handleStats.size };
  } catch (error) {
    await handle.close();
    throw error;
  }
}

async function assertContained(root: string, target: string): Promise<void> {
  const normalizedRoot = path.resolve(root);
  const normalizedTarget = path.resolve(target);
  if (normalizedRoot === normalizedTarget) return;

  if (process.platform !== "win32") {
    if (isLexicallyContained(normalizedRoot, normalizedTarget)) return;
    throw outsideRootError();
  }

  // Windows can opt individual NTFS directories into case-sensitive mode.
  // Lowercasing paths would therefore let a case-only sibling masquerade as
  // the capability root. Prefer directory identity while walking parents.
  const rootStats = await stat(normalizedRoot, { bigint: true });
  if (rootStats.ino !== 0n) {
    let current = path.dirname(normalizedTarget);
    while (true) {
      const currentStats = await stat(current, { bigint: true });
      if (currentStats.dev === rootStats.dev && currentStats.ino === rootStats.ino) {
        return;
      }
      const parent = path.dirname(current);
      if (parent === current) break;
      current = parent;
    }
    throw outsideRootError();
  }

  // Filesystems without stable inode data still benefit from realpath's
  // canonical spelling. Do not fold the full path and recreate the NTFS bug.
  if (isLexicallyContained(normalizedRoot, normalizedTarget)) return;
  throw outsideRootError();
}

function isLexicallyContained(root: string, target: string): boolean {
  const relative = path.relative(root, target);
  return (
    relative === "" ||
    (!path.isAbsolute(relative) && relative !== ".." && !relative.startsWith(`..${path.sep}`))
  );
}

function outsideRootError(): DocumentGrantError {
  return new DocumentGrantError(
    "outside-root",
    "Document grant target escapes its capability root.",
  );
}

function samePath(left: string, right: string): boolean {
  return path.resolve(left) === path.resolve(right);
}

interface ByteRange {
  start: bigint;
  end: bigint;
}

function parseRange(value: string, size: bigint): ByteRange | null {
  if (value.length > maximumRangeHeaderLength || size <= 0n) return null;
  const match = /^bytes=(\d*)-(\d*)$/u.exec(value.trim());
  if (!match || (!match[1] && !match[2])) return null;

  try {
    if (!match[1]) {
      const suffixLength = BigInt(match[2]);
      if (suffixLength <= 0n) return null;
      const length = suffixLength > size ? size : suffixLength;
      return { start: size - length, end: size - 1n };
    }

    const start = BigInt(match[1]);
    if (start >= size) return null;
    if (!match[2]) return { start, end: size - 1n };

    const requestedEnd = BigInt(match[2]);
    if (requestedEnd < start) return null;
    return {
      start,
      end: requestedEnd >= size ? size - 1n : requestedEnd,
    };
  } catch {
    return null;
  }
}

function streamResponse(
  handle: FileHandle,
  status: number,
  headers: Record<string, string>,
  range?: ByteRange,
): Response {
  try {
    const nodeStream = handle.createReadStream({
      autoClose: true,
      ...(range
        ? { start: Number(range.start), end: Number(range.end) }
        : {}),
    });
    const body = Readable.toWeb(nodeStream) as unknown as BodyInit;
    return responseWithSecurityHeaders(status, headers, body);
  } catch (error) {
    void handle.close();
    throw error;
  }
}

function responseWithSecurityHeaders(
  status: number,
  headers: Record<string, string> = {},
  body: BodyInit | null = null,
): Response {
  return new Response(body, {
    status,
    headers: {
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      ...headers,
    },
  });
}

function validateScope(value: string): string {
  if (
    typeof value !== "string" ||
    value.length < 1 ||
    value.length > maximumScopeLength ||
    value !== value.trim() ||
    /[\u0000-\u001f\u007f]/u.test(value)
  ) {
    throw new DocumentGrantError("invalid-scope", "Document grant scope is invalid.");
  }
  return value;
}

function validateTTL(value: number, maximum: number): number {
  if (!Number.isSafeInteger(value) || value < 1 || value > maximum) {
    throw new DocumentGrantError("invalid-ttl", "Document grant lifetime is invalid.");
  }
  return value;
}

function safeNow(value: number): number {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new DocumentGrantError("invalid-ttl", "Document grant clock is invalid.");
  }
  return value;
}

function validateMediaType(value: string): string {
  if (
    typeof value !== "string" ||
    value.length < 1 ||
    value.length > 128 ||
    !/^[a-z0-9!#$&^_.+-]+\/[a-z0-9!#$&^_.+-]+(?:; charset=utf-8)?$/iu.test(value)
  ) {
    throw new DocumentGrantError(
      "invalid-media-type",
      "Document grant media type is invalid.",
    );
  }
  return value;
}

function inferMediaType(filePath: string): string {
  switch (path.extname(filePath).toLocaleLowerCase("en-US")) {
    case ".pdf":
      return "application/pdf";
    case ".html":
    case ".htm":
      return "text/html; charset=utf-8";
    case ".md":
    case ".markdown":
      return "text/markdown; charset=utf-8";
    case ".txt":
      return "text/plain; charset=utf-8";
    case ".png":
      return "image/png";
    case ".jpg":
    case ".jpeg":
      return "image/jpeg";
    case ".gif":
      return "image/gif";
    case ".webp":
      return "image/webp";
    default:
      return "application/octet-stream";
  }
}
