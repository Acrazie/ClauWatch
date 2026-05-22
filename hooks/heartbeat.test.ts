import { test, expect, beforeEach, afterEach } from "bun:test";
import { mkdtempSync, rmSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";
import { openDb } from "./db";

let tmpDir: string;

beforeEach(() => {
  tmpDir = mkdtempSync(join(tmpdir(), "clauwatch-test-"));
  process.env.CLAUWATCH_DIR = tmpDir;
  process.env.CLAUWATCH_PROJECT_PATH = "/test/project-x";
  const db = openDb();
  db.run(
    `INSERT INTO sessions (project_path, project_name, started_at, last_seen_at)
     VALUES (?, ?, ?, ?)`,
    ["/test/project-x", "project-x", 1000, 1000]
  );
  db.close();
});

afterEach(() => {
  delete process.env.CLAUWATCH_DIR;
  delete process.env.CLAUWATCH_PROJECT_PATH;
  rmSync(tmpDir, { recursive: true, force: true });
});

test("heartbeat updates last_seen_at on open session", async () => {
  await import("./heartbeat");
  const db = openDb();
  const row = db
    .query("SELECT last_seen_at FROM sessions WHERE project_path = ?")
    .get("/test/project-x") as any;
  expect(row.last_seen_at).toBeGreaterThan(1000);
  db.close();
});

test("heartbeat does not touch closed sessions", async () => {
  const db = openDb();
  db.run(
    "UPDATE sessions SET ended_at = 2000, duration = 1000 WHERE project_path = ?",
    ["/test/project-x"]
  );
  db.close();

  await import("./heartbeat");

  const db2 = openDb();
  const row = db2
    .query("SELECT last_seen_at FROM sessions WHERE project_path = ?")
    .get("/test/project-x") as any;
  expect(row.last_seen_at).toBe(1000);
  db2.close();
});
