import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, readdir, rm, stat, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
  CredentialVault,
  CredentialVaultError,
  type SafeStorageAdapter,
} from "../src/main/services/credential-vault.ts";

class FakeSafeStorage implements SafeStorageAdapter {
  available = true;
  generation = 1;
  encryptFailure: Error | null = null;
  decryptFailure: Error | null = null;
  encryptCalls = 0;
  decryptCalls = 0;

  async isAsyncEncryptionAvailable(): Promise<boolean> {
    return this.available;
  }

  async encryptStringAsync(plainText: string): Promise<Buffer> {
    this.encryptCalls += 1;
    if (this.encryptFailure) throw this.encryptFailure;
    const source = Buffer.from(plainText, "utf8");
    const encrypted = Buffer.alloc(source.byteLength + 1);
    encrypted[0] = this.generation;
    for (let index = 0; index < source.byteLength; index += 1) {
      encrypted[index + 1] = source[index] ^ 0xa5;
    }
    return encrypted;
  }

  async decryptStringAsync(encrypted: Buffer): Promise<{
    result: string;
    shouldReEncrypt: boolean;
  }> {
    this.decryptCalls += 1;
    if (this.decryptFailure) throw this.decryptFailure;
    const source = Buffer.from(encrypted);
    if (source.byteLength < 1) throw new Error("corrupt fake ciphertext");
    const decrypted = Buffer.alloc(source.byteLength - 1);
    for (let index = 1; index < source.byteLength; index += 1) {
      decrypted[index - 1] = source[index] ^ 0xa5;
    }
    return {
      result: decrypted.toString("utf8"),
      shouldReEncrypt: source[0] < this.generation,
    };
  }
}

test("credential vault persists only ciphertext and round-trips secrets", async (t) => {
  const directory = await temporaryDirectory(t);
  const vaultPath = path.join(directory, "credentials.v2.json");
  const safeStorage = new FakeSafeStorage();
  const vault = await CredentialVault.open({ vaultPath, safeStorage, now: () => 1_000 });

  const secret = "sk-sensitive-明文-never-on-disk";
  await vault.setSecret("provider-profile", secret);

  const raw = await readFile(vaultPath, "utf8");
  assert.equal(raw.includes(secret), false);
  assert.equal(raw.includes("plainText"), false);
  assert.match(raw, /"ciphertextBase64"/u);
  assert.equal(await vault.getSecret("provider-profile"), secret);
  assert.deepEqual(await vault.listCredentialIDs(), ["provider-profile"]);
  // Windows does not expose the POSIX mode requested by open() as ACLs in
  // stat(). Keep the mode assertion where those bits have their documented
  // permission meaning; ciphertext and round-trip assertions cover the
  // platform-independent vault contract above and below.
  if (process.platform !== "win32") {
    assert.equal((await stat(vaultPath)).mode & 0o777, 0o600);
  }

  const reopened = await CredentialVault.open({ vaultPath, safeStorage });
  assert.equal(await reopened.getSecret("provider-profile"), secret);
});

test("credential vault refuses unavailable encryption and never falls back", async (t) => {
  const directory = await temporaryDirectory(t);
  const vaultPath = path.join(directory, "credentials.v2.json");
  const safeStorage = new FakeSafeStorage();
  safeStorage.available = false;

  await assert.rejects(
    CredentialVault.open({ vaultPath, safeStorage }),
    isVaultError("encryption-unavailable"),
  );
  assert.deepEqual(await readdir(directory), []);

  safeStorage.available = true;
  const vault = await CredentialVault.open({ vaultPath, safeStorage });
  safeStorage.encryptFailure = new Error("DPAPI failed");
  await assert.rejects(
    vault.setSecret("provider-profile", "must-not-fallback"),
    isVaultError("encryption-failed"),
  );
  assert.deepEqual(await readdir(directory), []);
});

test("credential vault re-encrypts rotated ciphertext before returning it", async (t) => {
  const directory = await temporaryDirectory(t);
  const vaultPath = path.join(directory, "credentials.v2.json");
  const safeStorage = new FakeSafeStorage();
  let now = 10;
  const vault = await CredentialVault.open({
    vaultPath,
    safeStorage,
    now: () => now,
  });
  await vault.setSecret("oauth", "refresh-token");
  const before = JSON.parse(await readFile(vaultPath, "utf8"));

  safeStorage.generation = 2;
  now = 20;
  assert.equal(await vault.getSecret("oauth"), "refresh-token");
  const after = JSON.parse(await readFile(vaultPath, "utf8"));
  assert.notEqual(
    after.credentials[0].ciphertextBase64,
    before.credentials[0].ciphertextBase64,
  );
  assert.equal(after.credentials[0].updatedAtMS, 20);

  const encryptionCallsAfterRotation = safeStorage.encryptCalls;
  assert.equal(await vault.getSecret("oauth"), "refresh-token");
  assert.equal(safeStorage.encryptCalls, encryptionCallsAfterRotation);
});

test("credential vault does not return a rotated secret unless re-encryption persists", async (t) => {
  const directory = await temporaryDirectory(t);
  const vaultPath = path.join(directory, "credentials.v2.json");
  const safeStorage = new FakeSafeStorage();
  const vault = await CredentialVault.open({ vaultPath, safeStorage });
  await vault.setSecret("oauth", "do-not-return-on-write-failure");

  safeStorage.generation = 2;
  await rm(vaultPath);
  await mkdir(vaultPath);
  await assert.rejects(
    vault.getSecret("oauth"),
    isVaultError("persistence-failed"),
  );
  assert.equal(safeStorage.decryptCalls, 1);
});

test("credential vault serializes concurrent atomic updates without staging debris", async (t) => {
  const directory = await temporaryDirectory(t);
  const vaultPath = path.join(directory, "credentials.v2.json");
  const vault = await CredentialVault.open({
    vaultPath,
    safeStorage: new FakeSafeStorage(),
  });

  await Promise.all(
    Array.from({ length: 24 }, (_, index) =>
      vault.setSecret(`profile-${index.toString().padStart(2, "0")}`, `secret-${index}`),
    ),
  );

  const persisted = JSON.parse(await readFile(vaultPath, "utf8"));
  assert.equal(persisted.credentials.length, 24);
  assert.equal((await vault.listCredentialIDs()).length, 24);
  assert.deepEqual(await readdir(directory), ["credentials.v2.json"]);
});

test("credential vault fails closed on malformed envelopes without overwriting them", async (t) => {
  const directory = await temporaryDirectory(t);
  const vaultPath = path.join(directory, "credentials.v2.json");
  const malformed = '{"schemaVersion":1,"credentials":[{"id":"x","ciphertextBase64":"not base64"}]}';
  await writeFile(vaultPath, malformed, { mode: 0o600 });

  await assert.rejects(
    CredentialVault.open({ vaultPath, safeStorage: new FakeSafeStorage() }),
    isVaultError("invalid-vault"),
  );
  assert.equal(await readFile(vaultPath, "utf8"), malformed);
});

function isVaultError(code: CredentialVaultError["code"]): (error: unknown) => boolean {
  return (error) => error instanceof CredentialVaultError && error.code === code;
}

async function temporaryDirectory(t: { after(callback: () => unknown): void }): Promise<string> {
  const directory = await mkdtemp(path.join(os.tmpdir(), "weibei-vault-test-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  return directory;
}
