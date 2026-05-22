import { openDb } from "./db";

const projectPath = process.env.CLAUWATCH_PROJECT_PATH ?? process.cwd();
const now = Math.floor(Date.now() / 1000);

try {
  const db = openDb();
  db.run(
    `UPDATE sessions SET last_seen_at = ?
     WHERE id = (
       SELECT id FROM sessions
       WHERE project_path = ? AND ended_at IS NULL
       ORDER BY started_at DESC LIMIT 1
     )`,
    [now, projectPath]
  );
  db.close();
} catch (_) {
  // Silent — heartbeat failure must not disrupt Claude Code
}
