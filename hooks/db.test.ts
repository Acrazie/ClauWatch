import { test, expect, beforeEach, afterEach } from "bun:test";
import { mkdtempSync, rmSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";
import { openDb } from "./db";

let tmpDir: string;

beforeEach(() => {
  tmpDir = mkdtempSync(join(tmpdir(), "clauwatch-test-"));
  process.env.CLAUWATCH_DIR = tmpDir;
});

afterEach(() => {
  delete process.env.CLAUWATCH_DIR;
  rmSync(tmpDir, { recursive: true, force: true });
});

test("openDb creates sessions table", () => {
  const db = openDb();
  const row = db.query(
    "SELECT name FROM sqlite_master WHERE type='table' AND name='sessions'"
  ).get();
  expect(row).not.toBeNull();
  db.close();
});

test("openDb is idempotent — second call does not throw", () => {
  const db1 = openDb(); db1.close();
  const db2 = openDb(); db2.close();
});

test("openDb creates directory if missing", () => {
  const nested = join(tmpDir, "sub", "dir");
  process.env.CLAUWATCH_DIR = nested;
  const db = openDb();
  db.close();
});
