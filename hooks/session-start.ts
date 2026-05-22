import { basename } from "path";
import { openDb } from "./db";

const projectPath = process.env.CLAUWATCH_PROJECT_PATH ?? process.cwd();
const projectName = basename(projectPath);
const now = Math.floor(Date.now() / 1000);

try {
  const db = openDb();
  db.run(
    `INSERT INTO sessions (project_path, project_name, started_at, last_seen_at)
     VALUES (?, ?, ?, ?)`,
    [projectPath, projectName, now, now]
  );
  db.close();
} catch (err) {
  import("fs").then(({ appendFileSync }) => {
    import("os").then(({ homedir }) => {
      import("path").then(({ join }) => {
        const log = process.env.CLAUWATCH_DIR
          ? join(process.env.CLAUWATCH_DIR, "errors.log")
          : join(homedir(), ".clauwatch", "errors.log");
        appendFileSync(log, `[${new Date().toISOString()}] session-start: ${err}\n`);
      });
    });
  });
}
