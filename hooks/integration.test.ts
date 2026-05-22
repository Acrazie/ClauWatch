import { test, expect, beforeEach, afterEach } from "bun:test";
import { mkdtempSync, rmSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";
import { openDb } from "./db";

let tmpDir: string;
const projectRoot = join(import.meta.dir, "..");

async function runHook(script: string, env: Record<string, string>) {
  const proc = Bun.spawn(["bun", "run", join("hooks", script)], {
    cwd: projectRoot,
    env: { ...process.env, CLAUWATCH_DIR: tmpDir, ...env },
  });
  await proc.exited;
}

beforeEach(() => {
  tmpDir = mkdtempSync(join(tmpdir(), "clauwatch-integ-"));
  process.env.CLAUWATCH_DIR = tmpDir;
});

afterEach(() => {
  delete process.env.CLAUWATCH_DIR;
  rmSync(tmpDir, { recursive: true, force: true });
});

// --- session-start ---

test("session-start: project_name is basename of deep path", async () => {
  await runHook("session-start.ts", { CLAUWATCH_PROJECT_PATH: "/a/b/c/deep-project" });
  const db = openDb();
  const row = db.query("SELECT project_name FROM sessions LIMIT 1").get() as { project_name: string };
  expect(row.project_name).toBe("deep-project");
  db.close();
});

test("session-start: two calls create two independent rows", async () => {
  await runHook("session-start.ts", { CLAUWATCH_PROJECT_PATH: "/a/my-project" });
  await runHook("session-start.ts", { CLAUWATCH_PROJECT_PATH: "/a/my-project" });
  const db = openDb();
  const rows = db.query("SELECT * FROM sessions").all();
  expect(rows.length).toBe(2);
  db.close();
});

test("session-start: row has ended_at NULL and valid timestamps", async () => {
  const before = Math.floor(Date.now() / 1000);
  await runHook("session-start.ts", { CLAUWATCH_PROJECT_PATH: "/p/proj" });
  const after = Math.floor(Date.now() / 1000);
  const db = openDb();
  const row = db.query("SELECT * FROM sessions LIMIT 1").get() as any;
  expect(row.ended_at).toBeNull();
  expect(row.started_at).toBeGreaterThanOrEqual(before);
  expect(row.started_at).toBeLessThanOrEqual(after);
  expect(row.last_seen_at).toBe(row.started_at);
  db.close();
});

// --- heartbeat ---

test("heartbeat: no open session is a silent no-op", async () => {
  await runHook("heartbeat.ts", { CLAUWATCH_PROJECT_PATH: "/a/my-project" });
  const db = openDb();
  const count = db.query("SELECT COUNT(*) as n FROM sessions").get() as { n: number };
  expect(count.n).toBe(0);
  db.close();
});

test("heartbeat: only updates matching project, not others", async () => {
  const db = openDb();
  db.run(
    `INSERT INTO sessions (project_path, project_name, started_at, last_seen_at)
     VALUES (?, ?, ?, ?)`,
    ["/a/target", "target", 1000, 1000]
  );
  db.run(
    `INSERT INTO sessions (project_path, project_name, started_at, last_seen_at)
     VALUES (?, ?, ?, ?)`,
    ["/b/other", "other", 1000, 1000]
  );
  db.close();

  await runHook("heartbeat.ts", { CLAUWATCH_PROJECT_PATH: "/a/target" });

  const db2 = openDb();
  const target = db2.query("SELECT last_seen_at FROM sessions WHERE project_path = ?")
    .get("/a/target") as { last_seen_at: number };
  const other = db2.query("SELECT last_seen_at FROM sessions WHERE project_path = ?")
    .get("/b/other") as { last_seen_at: number };
  expect(target.last_seen_at).toBeGreaterThan(1000);
  expect(other.last_seen_at).toBe(1000);
  db2.close();
});

test("heartbeat: does not update a closed session for the same project", async () => {
  const db = openDb();
  db.run(
    `INSERT INTO sessions (project_path, project_name, started_at, last_seen_at, ended_at, duration)
     VALUES (?, ?, ?, ?, ?, ?)`,
    ["/a/proj", "proj", 1000, 1000, 2000, 1000]
  );
  db.close();

  await runHook("heartbeat.ts", { CLAUWATCH_PROJECT_PATH: "/a/proj" });

  const db2 = openDb();
  const row = db2.query("SELECT last_seen_at FROM sessions WHERE project_path = ?")
    .get("/a/proj") as { last_seen_at: number };
  expect(row.last_seen_at).toBe(1000);
  db2.close();
});
