import { Database } from "bun:sqlite";
import { mkdirSync } from "fs";
import { homedir } from "os";
import { join } from "path";

const SCHEMA = `
  CREATE TABLE IF NOT EXISTS sessions (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    project_path TEXT    NOT NULL,
    project_name TEXT    NOT NULL,
    started_at   INTEGER NOT NULL,
    ended_at     INTEGER,
    last_seen_at INTEGER,
    duration     INTEGER
  )
`;

export function openDb(): Database {
  const dir = process.env.CLAUWATCH_DIR ?? join(homedir(), ".clauwatch");
  mkdirSync(dir, { recursive: true });
  const db = new Database(join(dir, "data.db"));
  db.run(SCHEMA);
  return db;
}
