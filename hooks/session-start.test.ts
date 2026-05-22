import { test, expect, beforeEach, afterEach } from "bun:test";
import { mkdtempSync, rmSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";
import { openDb } from "./db";

let tmpDir: string;

beforeEach(() => {
  tmpDir = mkdtempSync(join(tmpdir(), "clauwatch-test-"));
  process.env.CLAUWATCH_DIR = tmpDir;
  process.env.CLAUWATCH_PROJECT_PATH = "/test/my-project";
});

afterEach(() => {
  delete process.env.CLAUWATCH_DIR;
  delete process.env.CLAUWATCH_PROJECT_PATH;
  rmSync(tmpDir, { recursive: true, force: true });
});

test("session-start inserts a row with correct project info", async () => {
  await import("./session-start");
  const db = openDb();
  const row = db
    .query("SELECT * FROM sessions ORDER BY id DESC LIMIT 1")
    .get() as any;
  expect(row).not.toBeNull();
  expect(row.project_name).toBe("my-project");
  expect(row.project_path).toBe("/test/my-project");
  expect(row.ended_at).toBeNull();
  expect(row.started_at).toBeGreaterThan(0);
  expect(row.last_seen_at).toBe(row.started_at);
  db.close();
});
