import { randomUUID } from "node:crypto";
import {
  mkdir,
  open,
  readFile,
  rename,
  rm,
} from "node:fs/promises";
import path from "node:path";

const vaultSchemaVersion = 1 as const;
const maximumVaultBytes = 16 * 1024 * 1024;
const maximumCredentialBytes = 1024 * 1024;
const credentialIDPattern = /^[^\u0000-\u001f\u007f]{1,256}$/u;
const canonicalBase64Pattern = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/u;

export interface SafeStorageAdapter {
  isAsyncEncryptionAvailable(): Promise<boolean>;
  encryptStringAsync(plainText: string): Promise<Buffer>;
  decryptStringAsync(encrypted: Buffer): Promise<{
    result: string;
    shouldReEncrypt: boolean;
  }>;
}

export type CredentialVaultErrorCode =
  | "invalid-credential-id"
  | "invalid-secret"
  | "encryption-unavailable"
  | "encryption-failed"
  | "decryption-failed"
  | "invalid-vault"
  | "vault-too-large"
  | "persistence-failed";

export class CredentialVaultError extends Error {
  readonly code: CredentialVaultErrorCode;

  constructor(
    code: CredentialVaultErrorCode,
    message: string,
    options?: ErrorOptions,
  ) {
    super(message, options);
    this.name = "CredentialVaultError";
    this.code = code;
  }
}

interface PersistedCredential {
  id: string;
  ciphertextBase64: string;
  updatedAtMS: number;
}

interface PersistedVault {
  schemaVersion: typeof vaultSchemaVersion;
  credentials: PersistedCredential[];
}

export interface CredentialVaultOptions {
  /** Absolute path to the encrypted JSON envelope. */
  vaultPath: string;
  safeStorage: SafeStorageAdapter;
  now?: () => number;
}

/**
 * Main-process-only credential storage.
 *
 * The file envelope never accepts or writes a plaintext representation. All
 * operations that can reveal or create a secret are serialized so a key
 * rotation cannot race a concurrent update and erase it.
 */
export class CredentialVault {
  private readonly vaultPath: string;
  private readonly safeStorage: SafeStorageAdapter;
  private readonly now: () => number;
  private records = new Map<string, PersistedCredential>();
  private operationQueue: Promise<void> = Promise.resolve();

  private constructor(options: CredentialVaultOptions) {
    this.vaultPath = options.vaultPath;
    this.safeStorage = options.safeStorage;
    this.now = options.now ?? Date.now;
  }

  static async open(options: CredentialVaultOptions): Promise<CredentialVault> {
    if (!path.isAbsolute(options.vaultPath)) {
      throw new CredentialVaultError(
        "persistence-failed",
        "Credential vault path must be absolute.",
      );
    }

    const vault = new CredentialVault(options);
    await vault.ensureEncryptionAvailable();
    vault.records = await loadVault(options.vaultPath);
    return vault;
  }

  async setSecret(credentialID: string, secret: string): Promise<void> {
    validateCredentialID(credentialID);
    validateSecret(secret);

    await this.runExclusive(async () => {
      await this.ensureEncryptionAvailable();
      const encrypted = await this.encrypt(secret);
      const next = new Map(this.records);
      next.set(credentialID, {
        id: credentialID,
        ciphertextBase64: encrypted.toString("base64"),
        updatedAtMS: safeTimestamp(this.now()),
      });
      await this.persist(next);
      this.records = next;
    });
  }

  async getSecret(credentialID: string): Promise<string | null> {
    validateCredentialID(credentialID);

    return this.runExclusive(async () => {
      const record = this.records.get(credentialID);
      if (!record) return null;

      await this.ensureEncryptionAvailable();
      const decrypted = await this.decrypt(decodeCiphertext(record.ciphertextBase64));
      if (!decrypted.shouldReEncrypt) return decrypted.result;

      // Rotation is part of the read transaction. Do not return the plaintext
      // until the replacement ciphertext has been durably installed.
      const rotated = await this.encrypt(decrypted.result);
      const next = new Map(this.records);
      next.set(credentialID, {
        id: credentialID,
        ciphertextBase64: rotated.toString("base64"),
        updatedAtMS: safeTimestamp(this.now()),
      });
      await this.persist(next);
      this.records = next;
      return decrypted.result;
    });
  }

  async deleteSecret(credentialID: string): Promise<boolean> {
    validateCredentialID(credentialID);

    return this.runExclusive(async () => {
      if (!this.records.has(credentialID)) return false;
      const next = new Map(this.records);
      next.delete(credentialID);
      await this.persist(next);
      this.records = next;
      return true;
    });
  }

  async hasSecret(credentialID: string): Promise<boolean> {
    validateCredentialID(credentialID);
    return this.runExclusive(async () => this.records.has(credentialID));
  }

  async listCredentialIDs(): Promise<string[]> {
    return this.runExclusive(async () => [...this.records.keys()].sort());
  }

  private async ensureEncryptionAvailable(): Promise<void> {
    let available = false;
    try {
      available = await this.safeStorage.isAsyncEncryptionAvailable();
    } catch (error) {
      throw new CredentialVaultError(
        "encryption-unavailable",
        "OS credential encryption is temporarily unavailable.",
        { cause: error },
      );
    }
    if (!available) {
      throw new CredentialVaultError(
        "encryption-unavailable",
        "OS credential encryption is unavailable; plaintext storage is disabled.",
      );
    }
  }

  private async encrypt(secret: string): Promise<Buffer> {
    try {
      const result = Buffer.from(await this.safeStorage.encryptStringAsync(secret));
      if (result.byteLength === 0) throw new Error("empty ciphertext");
      return result;
    } catch {
      throw new CredentialVaultError(
        "encryption-failed",
        "Credential encryption failed.",
      );
    }
  }

  private async decrypt(ciphertext: Buffer): Promise<{
    result: string;
    shouldReEncrypt: boolean;
  }> {
    try {
      const result = await this.safeStorage.decryptStringAsync(ciphertext);
      if (
        !result ||
        typeof result.result !== "string" ||
        typeof result.shouldReEncrypt !== "boolean"
      ) {
        throw new Error("invalid safeStorage response");
      }
      return result;
    } catch {
      throw new CredentialVaultError(
        "decryption-failed",
        "Credential decryption failed.",
      );
    }
  }

  private async persist(records: Map<string, PersistedCredential>): Promise<void> {
    const payload: PersistedVault = {
      schemaVersion: vaultSchemaVersion,
      credentials: [...records.values()]
        .sort((left, right) => (left.id < right.id ? -1 : left.id > right.id ? 1 : 0))
        .map((record) => ({ ...record })),
    };
    const serialized = `${JSON.stringify(payload, null, 2)}\n`;
    const contents = Buffer.from(serialized, "utf8");
    if (contents.byteLength > maximumVaultBytes) {
      throw new CredentialVaultError(
        "vault-too-large",
        "Encrypted credential vault exceeds the size limit.",
      );
    }
    try {
      await atomicWrite(this.vaultPath, contents);
    } catch (error) {
      throw new CredentialVaultError(
        "persistence-failed",
        "Encrypted credential vault could not be persisted.",
        { cause: error },
      );
    }
  }

  private runExclusive<T>(operation: () => Promise<T>): Promise<T> {
    const result = this.operationQueue.then(operation);
    this.operationQueue = result.then(
      () => undefined,
      () => undefined,
    );
    return result;
  }
}

async function loadVault(vaultPath: string): Promise<Map<string, PersistedCredential>> {
  let bytes: Buffer;
  try {
    bytes = await readFile(vaultPath);
  } catch (error) {
    if (isErrno(error, "ENOENT")) return new Map();
    throw new CredentialVaultError(
      "invalid-vault",
      "Encrypted credential vault could not be read.",
      { cause: error },
    );
  }

  if (bytes.byteLength > maximumVaultBytes) {
    throw new CredentialVaultError(
      "vault-too-large",
      "Encrypted credential vault exceeds the size limit.",
    );
  }

  let decoded: unknown;
  try {
    decoded = JSON.parse(bytes.toString("utf8"));
  } catch (error) {
    throw new CredentialVaultError(
      "invalid-vault",
      "Encrypted credential vault is not valid JSON.",
      { cause: error },
    );
  }

  if (!isRecord(decoded) || decoded.schemaVersion !== vaultSchemaVersion) {
    throw new CredentialVaultError(
      "invalid-vault",
      "Encrypted credential vault schema is unsupported.",
    );
  }
  if (!Array.isArray(decoded.credentials)) {
    throw new CredentialVaultError(
      "invalid-vault",
      "Encrypted credential vault has no credential list.",
    );
  }

  const records = new Map<string, PersistedCredential>();
  for (const value of decoded.credentials) {
    if (!isPersistedCredential(value) || records.has(value.id)) {
      throw new CredentialVaultError(
        "invalid-vault",
        "Encrypted credential vault contains an invalid record.",
      );
    }
    records.set(value.id, { ...value });
  }
  return records;
}

function isPersistedCredential(value: unknown): value is PersistedCredential {
  if (!isRecord(value)) return false;
  if (
    typeof value.id !== "string" ||
    typeof value.ciphertextBase64 !== "string" ||
    typeof value.updatedAtMS !== "number"
  ) {
    return false;
  }
  try {
    validateCredentialID(value.id);
    decodeCiphertext(value.ciphertextBase64);
    safeTimestamp(value.updatedAtMS);
    return true;
  } catch {
    return false;
  }
}

function decodeCiphertext(value: string): Buffer {
  if (!value || !canonicalBase64Pattern.test(value)) {
    throw new CredentialVaultError(
      "invalid-vault",
      "Encrypted credential record has invalid ciphertext.",
    );
  }
  const decoded = Buffer.from(value, "base64");
  if (decoded.byteLength === 0 || decoded.toString("base64") !== value) {
    throw new CredentialVaultError(
      "invalid-vault",
      "Encrypted credential record has invalid ciphertext.",
    );
  }
  return decoded;
}

function validateCredentialID(value: string): void {
  if (
    typeof value !== "string" ||
    value !== value.trim() ||
    !credentialIDPattern.test(value)
  ) {
    throw new CredentialVaultError(
      "invalid-credential-id",
      "Credential identifier is invalid.",
    );
  }
}

function validateSecret(value: string): void {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    Buffer.byteLength(value, "utf8") > maximumCredentialBytes
  ) {
    throw new CredentialVaultError("invalid-secret", "Credential secret is invalid.");
  }
}

function safeTimestamp(value: number): number {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new CredentialVaultError(
      "invalid-vault",
      "Encrypted credential record has an invalid timestamp.",
    );
  }
  return value;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function isErrno(error: unknown, code: string): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    (error as NodeJS.ErrnoException).code === code
  );
}

async function atomicWrite(targetPath: string, contents: Buffer): Promise<void> {
  const parent = path.dirname(targetPath);
  await mkdir(parent, { recursive: true, mode: 0o700 });
  const stagedPath = path.join(
    parent,
    `.${path.basename(targetPath)}.weibei-vault-${randomUUID()}`,
  );
  let staged = true;
  try {
    const handle = await open(stagedPath, "wx", 0o600);
    try {
      await handle.writeFile(contents);
      await handle.sync();
    } finally {
      await handle.close();
    }
    await rename(stagedPath, targetPath);
    staged = false;

    const installed = await readFile(targetPath);
    if (!installed.equals(contents)) {
      throw new Error("vault write verification failed");
    }
  } finally {
    if (staged) await rm(stagedPath, { force: true });
  }
}
