# ClauWatch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS menubar app that records Claude Code session time via bun hooks writing to SQLite, then displays daily/weekly/monthly stats in a native SwiftUI tray popover.

**Architecture:** Bun hook scripts (global in `~/.claude/settings.json`) write session events to `~/.clauwatch/data.db`. A Swift/SwiftUI executable reads that SQLite, polls for the `claude` process every 10s, and closes open sessions on process exit.

**Tech Stack:** bun + `bun:sqlite` (hooks), Swift 5.10 + SwiftUI + AppKit (menubar app), `SQLite.swift` 0.15+ (DB reads in Swift), PerpetuaMTPro-Regular + Geist + Geist Mono fonts, SF Symbols (Tabler equivalent in native Swift)

> **Note on project structure:** Plan uses SPM (`Package.swift`) instead of Xcode `.xcodeproj` — more scriptable, same result. Open `Package.swift` in Xcode for GUI if needed.

---

## File Map

### Bun (hooks)

| File | Responsibility |
|---|---|
| `hooks/db.ts` | `openDb()` — create dir + schema, export |
| `hooks/session-start.ts` | INSERT session on `SessionStart` |
| `hooks/heartbeat.ts` | UPDATE `last_seen_at` on `UserPromptSubmit` |
| `hooks/db.test.ts` | Schema creation tests |
| `hooks/session-start.test.ts` | Session insert tests |
| `hooks/heartbeat.test.ts` | Heartbeat update tests |
| `package.json` | bun workspace + test script |

### Swift (SPM)

| File | Responsibility |
|---|---|
| `Package.swift` | Two targets: `ClauWatchCore` (lib) + `ClauWatch` (executable) |
| `Sources/ClauWatchCore/SessionStore.swift` | SQLite reads, stats computation, session close |
| `Sources/ClauWatchCore/ProcessMonitor.swift` | Poll for `claude` PID, fire callback on exit |
| `Sources/ClauWatch/main.swift` | `NSApplication` run loop |
| `Sources/ClauWatch/AppDelegate.swift` | App lifecycle, crash recovery on launch |
| `Sources/ClauWatch/MenubarController.swift` | `NSStatusItem`, refresh timer |
| `Sources/ClauWatch/PopoverView.swift` | SwiftUI popover (stats + projects) |
| `Sources/ClauWatch/Resources/Fonts/PerpetuaMTPro-Regular.otf` | Bundled font |
| `Tests/ClauWatchTests/SessionStoreTests.swift` | Stats computation tests |
| `Tests/ClauWatchTests/ProcessMonitorTests.swift` | Process detection tests |

---

## Task 1: Project scaffold + DB module

**Files:**
- Create: `package.json`
- Create: `hooks/db.ts`
- Create: `hooks/db.test.ts`
- Modify: `.gitignore`

- [ ] **Step 1: Update `.gitignore`**

```
node_modules/
.build/
*.db
*.db-shm
*.db-wal
```

- [ ] **Step 2: Create `package.json`**

```json
{
  "name": "clauwatch-hooks",
  "version": "1.0.0",
  "scripts": {
    "test": "bun test hooks/"
  }
}
```

- [ ] **Step 3: Write the failing test for `openDb()`**

```typescript
// hooks/db.test.ts
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
```

- [ ] **Step 4: Run test — confirm failure**

```bash
bun test hooks/db.test.ts
```
Expected: `Cannot find module './db'`

- [ ] **Step 5: Implement `hooks/db.ts`**

```typescript
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
```

- [ ] **Step 6: Run tests — confirm pass**

```bash
bun test hooks/db.test.ts
```
Expected: `3 pass`

- [ ] **Step 7: Commit**

```bash
git add package.json hooks/db.ts hooks/db.test.ts .gitignore
git commit -m "feat(hooks): add SQLite schema and openDb utility"
```

---

## Task 2: SessionStart hook

**Files:**
- Create: `hooks/session-start.ts`
- Create: `hooks/session-start.test.ts`

- [ ] **Step 1: Write the failing test**

```typescript
// hooks/session-start.test.ts
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
```

- [ ] **Step 2: Run test — confirm failure**

```bash
bun test hooks/session-start.test.ts
```
Expected: `Cannot find module './session-start'`

- [ ] **Step 3: Implement `hooks/session-start.ts`**

```typescript
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
```

- [ ] **Step 4: Run tests — confirm pass**

```bash
bun test hooks/session-start.test.ts
```
Expected: `1 pass`

- [ ] **Step 5: Commit**

```bash
git add hooks/session-start.ts hooks/session-start.test.ts
git commit -m "feat(hooks): add session-start hook"
```

---

## Task 3: Heartbeat hook

**Files:**
- Create: `hooks/heartbeat.ts`
- Create: `hooks/heartbeat.test.ts`

- [ ] **Step 1: Write the failing test**

```typescript
// hooks/heartbeat.test.ts
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
```

- [ ] **Step 2: Run test — confirm failure**

```bash
bun test hooks/heartbeat.test.ts
```
Expected: `Cannot find module './heartbeat'`

- [ ] **Step 3: Implement `hooks/heartbeat.ts`**

```typescript
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
```

- [ ] **Step 4: Run tests — confirm pass**

```bash
bun test hooks/heartbeat.test.ts
```
Expected: `2 pass`

- [ ] **Step 5: Run full hook suite**

```bash
bun test hooks/
```
Expected: `6 pass`

- [ ] **Step 6: Commit**

```bash
git add hooks/heartbeat.ts hooks/heartbeat.test.ts
git commit -m "feat(hooks): add heartbeat hook"
```

---

## Task 4: Register hooks in Claude Code

**Files:**
- Modify: `~/.claude/settings.json`

- [ ] **Step 1: Read current settings**

```bash
cat ~/.claude/settings.json
```

- [ ] **Step 2: Add hooks — merge with existing entries**

Add to the `hooks` object. Do not overwrite existing hooks — merge the arrays.

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "CLAUWATCH_PROJECT_PATH=$(pwd) bun /Users/acrazie/Documents/ProjectPerso/ClauWatch/hooks/session-start.ts"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "CLAUWATCH_PROJECT_PATH=$(pwd) bun /Users/acrazie/Documents/ProjectPerso/ClauWatch/hooks/heartbeat.ts"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 3: Verify hooks fire**

Open a new Claude Code session in any project. After it loads, run:

```bash
bun --eval "
  import { Database } from 'bun:sqlite';
  const db = new Database(process.env.HOME + '/.clauwatch/data.db');
  console.table(db.query('SELECT * FROM sessions ORDER BY id DESC LIMIT 3').all());
"
```
Expected: at least one row with `ended_at = null` and `started_at` within the last few minutes.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit --allow-empty -m "chore: document hook registration step (settings in ~/.claude)"
```

---

## Task 5: Swift package scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/ClauWatchCore/` (empty)
- Create: `Sources/ClauWatch/Resources/Fonts/` (empty)
- Create: `Tests/ClauWatchTests/` (empty)

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClauWatch",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.3")
    ],
    targets: [
        .target(
            name: "ClauWatchCore",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift")
            ],
            path: "Sources/ClauWatchCore"
        ),
        .executableTarget(
            name: "ClauWatch",
            dependencies: ["ClauWatchCore"],
            path: "Sources/ClauWatch",
            resources: [
                .process("Resources/Fonts")
            ]
        ),
        .testTarget(
            name: "ClauWatchTests",
            dependencies: ["ClauWatchCore"],
            path: "Tests/ClauWatchTests"
        )
    ]
)
```

- [ ] **Step 2: Create directories**

```bash
mkdir -p Sources/ClauWatchCore Sources/ClauWatch/Resources/Fonts Tests/ClauWatchTests
```

- [ ] **Step 3: Add placeholder files so SPM sees the targets**

```swift
// Sources/ClauWatchCore/SessionStore.swift
import Foundation
```

```swift
// Sources/ClauWatch/main.swift
import Foundation
```

```swift
// Tests/ClauWatchTests/SessionStoreTests.swift
import XCTest
final class SessionStoreTests: XCTestCase {}
```

- [ ] **Step 4: Resolve + build**

```bash
swift package resolve
swift build
```
Expected: `SQLite.swift` downloaded, build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/ Tests/
git commit -m "chore(swift): scaffold SPM package with ClauWatchCore and ClauWatch targets"
```

---

## Task 6: SessionStore

**Files:**
- Modify: `Sources/ClauWatchCore/SessionStore.swift`
- Modify: `Tests/ClauWatchTests/SessionStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/ClauWatchTests/SessionStoreTests.swift
import XCTest
import Foundation
@testable import ClauWatchCore

final class SessionStoreTests: XCTestCase {
    var store: SessionStore!

    override func setUp() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        store = try! SessionStore(dbPath: tmp.appendingPathComponent("data.db").path)
    }

    func testEmptyStats() throws {
        let s = try store.stats()
        XCTAssertEqual(s.todayDuration, 0)
        XCTAssertEqual(s.weekDuration, 0)
        XCTAssertEqual(s.monthDuration, 0)
        XCTAssertTrue(s.projectsThisWeek.isEmpty)
        XCTAssertNil(s.activeSession)
    }

    func testTodayDurationFromClosedSession() throws {
        let now = Int64(Date().timeIntervalSince1970)
        try store.insertTestSession(path: "/p", name: "p",
            startedAt: now - 3600, endedAt: now, duration: 3600)
        let s = try store.stats()
        XCTAssertEqual(s.todayDuration, 3600, accuracy: 2)
    }

    func testTodayDurationFromOpenSession() throws {
        let now = Int64(Date().timeIntervalSince1970)
        try store.insertTestSession(path: "/p", name: "p",
            startedAt: now - 1800, endedAt: nil, duration: nil)
        let s = try store.stats()
        XCTAssertEqual(s.todayDuration, 1800, accuracy: 5)
    }

    func testActiveSessionDetected() throws {
        let now = Int64(Date().timeIntervalSince1970)
        try store.insertTestSession(path: "/p", name: "MyProject",
            startedAt: now - 600, endedAt: nil, duration: nil)
        let s = try store.stats()
        XCTAssertEqual(s.activeSession?.projectName, "MyProject")
    }

    func testCloseOpenSessions() throws {
        let now = Int64(Date().timeIntervalSince1970)
        try store.insertTestSession(path: "/p", name: "p",
            startedAt: now - 500, endedAt: nil, duration: nil)
        try store.closeOpenSessions(endedAtTime: now)
        let s = try store.stats()
        XCTAssertNil(s.activeSession)
        XCTAssertEqual(s.todayDuration, 500, accuracy: 2)
    }

    func testProjectBreakdown() throws {
        let now = Int64(Date().timeIntervalSince1970)
        try store.insertTestSession(path: "/a", name: "alpha",
            startedAt: now - 7200, endedAt: now - 3600, duration: 3600)
        try store.insertTestSession(path: "/b", name: "beta",
            startedAt: now - 1800, endedAt: now, duration: 1800)
        let s = try store.stats()
        XCTAssertTrue(s.projectsThisWeek.map(\.name).contains("alpha"))
        XCTAssertTrue(s.projectsThisWeek.map(\.name).contains("beta"))
    }
}
```

- [ ] **Step 2: Run — confirm failure**

```bash
swift test --filter SessionStoreTests
```
Expected: compile error — `SessionStore` undefined.

- [ ] **Step 3: Implement `Sources/ClauWatchCore/SessionStore.swift`**

```swift
import Foundation
import SQLite

public struct SessionStats {
    public let todayDuration: Int
    public let weekDuration: Int
    public let monthDuration: Int
    public let projectsThisWeek: [ProjectStat]
    public let activeSession: ActiveSession?
}

public struct ProjectStat {
    public let name: String
    public let path: String
    public let duration: Int
}

public struct ActiveSession {
    public let projectName: String
    public let startedAt: Date
}

public class SessionStore {
    let db: Connection
    let sessions = Table("sessions")

    let colId          = Expression<Int64>("id")
    let colProjectPath = Expression<String>("project_path")
    let colProjectName = Expression<String>("project_name")
    let colStartedAt   = Expression<Int64>("started_at")
    let colEndedAt     = Expression<Int64?>("ended_at")
    let colLastSeenAt  = Expression<Int64?>("last_seen_at")
    let colDuration    = Expression<Int64?>("duration")

    public init(dbPath: String) throws {
        db = try Connection(dbPath)
        try db.run(sessions.create(ifNotExists: true) { t in
            t.column(colId, primaryKey: .autoincrement)
            t.column(colProjectPath)
            t.column(colProjectName)
            t.column(colStartedAt)
            t.column(colEndedAt)
            t.column(colLastSeenAt)
            t.column(colDuration)
        })
    }

    public func stats() throws -> SessionStats {
        let now = Int64(Date().timeIntervalSince1970)
        let cal = Calendar.current

        let todayStart = Int64(cal.startOfDay(for: Date()).timeIntervalSince1970)
        let weekStart  = Int64((cal.date(from: cal.dateComponents(
            [.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()).timeIntervalSince1970)
        let monthStart = Int64((cal.date(from: cal.dateComponents(
            [.year, .month], from: Date())) ?? Date()).timeIntervalSince1970)

        return SessionStats(
            todayDuration: try totalDuration(from: todayStart, now: now),
            weekDuration:  try totalDuration(from: weekStart,  now: now),
            monthDuration: try totalDuration(from: monthStart, now: now),
            projectsThisWeek: try projectBreakdown(from: weekStart, now: now),
            activeSession: try currentActive()
        )
    }

    func totalDuration(from start: Int64, now: Int64) throws -> Int {
        var total: Int64 = 0
        for row in try db.prepare(sessions.filter(colStartedAt >= start)) {
            if let dur = row[colDuration] {
                total += dur
            } else {
                total += now - row[colStartedAt]
            }
        }
        return Int(total)
    }

    func projectBreakdown(from start: Int64, now: Int64) throws -> [ProjectStat] {
        var map: [String: (String, Int64)] = [:]
        for row in try db.prepare(sessions.filter(colStartedAt >= start)) {
            let path = row[colProjectPath]
            let name = row[colProjectName]
            let dur  = row[colDuration] ?? (now - row[colStartedAt])
            map[path] = (name, (map[path]?.1 ?? 0) + dur)
        }
        return map.map { path, pair in
            ProjectStat(name: pair.0, path: path, duration: Int(pair.1))
        }.sorted { $0.duration > $1.duration }
    }

    func currentActive() throws -> ActiveSession? {
        let q = sessions.filter(colEndedAt == nil).order(colStartedAt.desc).limit(1)
        guard let row = try db.pluck(q) else { return nil }
        return ActiveSession(
            projectName: row[colProjectName],
            startedAt:   Date(timeIntervalSince1970: TimeInterval(row[colStartedAt]))
        )
    }

    public func closeOpenSessions(endedAtTime: Int64) throws {
        try db.execute("""
            UPDATE sessions
            SET ended_at = \(endedAtTime),
                duration = \(endedAtTime) - started_at
            WHERE ended_at IS NULL
        """)
    }

    public func closeStaleSessions(before threshold: Int64, endedAtTime: Int64) throws {
        try db.execute("""
            UPDATE sessions
            SET ended_at = \(endedAtTime),
                duration = \(endedAtTime) - started_at
            WHERE ended_at IS NULL
              AND (last_seen_at IS NULL OR last_seen_at < \(threshold))
        """)
    }

    // Test helper — not used in production code
    func insertTestSession(path: String, name: String,
                           startedAt: Int64, endedAt: Int64?, duration: Int64?) throws {
        try db.run(sessions.insert(
            colProjectPath <- path,
            colProjectName <- name,
            colStartedAt   <- startedAt,
            colEndedAt     <- endedAt,
            colLastSeenAt  <- startedAt,
            colDuration    <- duration
        ))
    }
}
```

- [ ] **Step 4: Run tests — confirm pass**

```bash
swift test --filter SessionStoreTests
```
Expected: `6 tests passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/ClauWatchCore/SessionStore.swift Tests/ClauWatchTests/SessionStoreTests.swift
git commit -m "feat(core): add SessionStore with stats computation"
```

---

## Task 7: ProcessMonitor

**Files:**
- Create: `Sources/ClauWatchCore/ProcessMonitor.swift`
- Create: `Tests/ClauWatchTests/ProcessMonitorTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/ClauWatchTests/ProcessMonitorTests.swift
import XCTest
@testable import ClauWatchCore

final class ProcessMonitorTests: XCTestCase {
    func testClaudePIDsReturnsArray() {
        let monitor = ProcessMonitor(interval: 1)
        let pids = monitor.claudePIDs()
        XCTAssertNotNil(pids) // may be empty, must not throw
    }

    func testExitCallbackFiresForVanishedPID() {
        let expectation = expectation(description: "exit callback fires")
        var firedPID: Int32?

        let monitor = ProcessMonitor(interval: 0.1)
        monitor.knownPIDs = [Int32.max] // fake PID that won't appear in ps
        monitor.onSessionEnd = { pid in
            firedPID = pid
            expectation.fulfill()
        }
        monitor.start()
        waitForExpectations(timeout: 2.0)
        monitor.stop()
        XCTAssertEqual(firedPID, Int32.max)
    }
}
```

- [ ] **Step 2: Run — confirm failure**

```bash
swift test --filter ProcessMonitorTests
```
Expected: compile error — `ProcessMonitor` undefined.

- [ ] **Step 3: Implement `Sources/ClauWatchCore/ProcessMonitor.swift`**

```swift
import Foundation

public class ProcessMonitor {
    private let interval: TimeInterval
    private var timer: Timer?
    public var knownPIDs: Set<Int32> = []
    public var onSessionEnd: ((Int32) -> Void)?

    public init(interval: TimeInterval = 10.0) {
        self.interval = interval
    }

    public func start() {
        knownPIDs = Set(claudePIDs())
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    func tick() {
        let current = Set(claudePIDs())
        knownPIDs.subtracting(current).forEach { onSessionEnd?($0) }
        knownPIDs = current
    }

    public func claudePIDs() -> [Int32] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-A", "-o", "pid=,comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        guard (try? task.run()) != nil else { return [] }
        task.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8) ?? ""
        return out.components(separatedBy: "\n").compactMap { line -> Int32? in
            let parts = line.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 2 else { return nil }
            let comm = parts[1]
            guard comm == "claude" || comm.hasSuffix("/claude") else { return nil }
            return Int32(parts[0])
        }
    }
}
```

- [ ] **Step 4: Run full test suite**

```bash
swift test
```
Expected: `8 tests passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/ClauWatchCore/ProcessMonitor.swift Tests/ClauWatchTests/ProcessMonitorTests.swift
git commit -m "feat(core): add ProcessMonitor for claude process detection"
```

---

## Task 8: PopoverView (SwiftUI)

**Files:**
- Create: `Sources/ClauWatch/PopoverView.swift`
- Add: `Sources/ClauWatch/Resources/Fonts/PerpetuaMTPro-Regular.otf`

- [ ] **Step 1: Copy font file into project**

Place `PerpetuaMTPro-Regular.otf` at:
```
Sources/ClauWatch/Resources/Fonts/PerpetuaMTPro-Regular.otf
```

- [ ] **Step 2: Create `PopoverView.swift`**

```swift
import SwiftUI
import ClauWatchCore

struct PopoverView: View {
    let stats: SessionStats
    @State private var elapsed: Int = 0
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            divider
            sessionSection
            divider
            cumulSection
            divider
            projectsSection
            divider
            footerRow
        }
        .frame(width: 288)
        .background(Color(hex: 0x171B26))
        .onReceive(ticker) { _ in if stats.activeSession != nil { elapsed += 1 } }
        .onAppear {
            elapsed = stats.activeSession.map {
                Int(Date().timeIntervalSince($0.startedAt))
            } ?? 0
        }
    }

    private var divider: some View {
        Rectangle().fill(Color(hex: 0x2A3042)).frame(height: 1)
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: 0x6B7280))
            Text("ClauWatch")
                .font(.custom("PerpetuaMTPro-Regular", size: 14))
                .kerning(1.8)
                .foregroundColor(Color(hex: 0xF0F0F5))
            Spacer()
            if stats.activeSession != nil {
                HStack(spacing: 4) {
                    Circle().fill(Color(hex: 0x34C759))
                        .frame(width: 5, height: 5)
                        .shadow(color: Color(hex: 0x34C759), radius: 3)
                    Text("LIVE")
                        .font(.system(size: 10, weight: .medium))
                        .kerning(0.6)
                        .foregroundColor(Color(hex: 0x34C759))
                }
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 12)
    }

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            label("Session active")
            if let active = stats.activeSession {
                HStack {
                    Label(active.projectName, systemImage: "folder.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: 0xF0F0F5))
                        .lineLimit(1)
                    Spacer()
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill").font(.system(size: 9))
                        Text(hms(elapsed))
                            .font(.custom("GeistMono", size: 12).weight(.semibold))
                            .monospacedDigit()
                    }
                    .foregroundColor(Color(hex: 0x34C759))
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Color(hex: 0x34C759).opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(hex: 0x34C759).opacity(0.22)))
                    .cornerRadius(6)
                }
            } else {
                Text("Aucune session active")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: 0x6B7280))
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 11)
    }

    private var cumulSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            label("Temps cumulé")
            HStack(spacing: 6) {
                cell("Auj.",  icon: "sun.min",           value: stats.todayDuration, accent: true)
                cell("Sem.",  icon: "calendar.badge.clock", value: stats.weekDuration)
                cell("Mois",  icon: "calendar",           value: stats.monthDuration)
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 11)
    }

    private func cell(_ title: String, icon: String, value: Int, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10))
                    .foregroundColor(Color(hex: 0x6B7280))
                Text(title).font(.system(size: 10))
                    .foregroundColor(Color(hex: 0x6B7280))
            }
            Text(hm(value))
                .font(.custom("PerpetuaMTPro-Regular", size: 17))
                .kerning(2.0)
                .foregroundColor(accent ? Color(hex: 0x34C759) : Color(hex: 0xF0F0F5))
                .lineLimit(1).minimumScaleFactor(0.7)
            Text("heures")
                .font(.system(size: 9)).kerning(0.9)
                .foregroundColor(Color(hex: 0x6B7280))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9).padding(.vertical, 8)
        .background(Color(hex: 0x1E2436))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0x2A3042)))
        .cornerRadius(8)
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            label("Projets · cette semaine")
            let maxDur = stats.projectsThisWeek.first?.duration ?? 1
            let activePath = stats.activeSession.map { _ in
                stats.projectsThisWeek.first?.path ?? ""
            }
            ForEach(stats.projectsThisWeek.prefix(4), id: \.path) { proj in
                HStack(spacing: 6) {
                    Image(systemName: proj.path == activePath ? "folder.fill" : "folder")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: 0x6B7280))
                    Text(proj.name)
                        .font(.system(size: 11.5,
                            weight: proj.path == activePath ? .medium : .regular))
                        .foregroundColor(proj.path == activePath
                            ? Color(hex: 0xF0F0F5) : Color(hex: 0x8B95A8))
                        .lineLimit(1)
                    Spacer()
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x1E2436))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(proj.path == activePath
                                    ? Color(hex: 0x34C759) : Color(hex: 0x2A3042))
                                .frame(width: g.size.width * CGFloat(proj.duration)
                                    / CGFloat(maxDur))
                        }
                    }
                    .frame(width: 48, height: 2)
                    Text(hm(proj.duration))
                        .font(.custom("GeistMono", size: 10.5)).monospacedDigit()
                        .foregroundColor(proj.path == activePath
                            ? Color(hex: 0x34C759) : Color(hex: 0x6B7280))
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 11)
    }

    private var footerRow: some View {
        HStack {
            Button(action: {}) {
                Label("Vue complète", systemImage: "square.grid.2x2")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: 0x6B7280))
            }.buttonStyle(.plain)
            Spacer()
            Button(action: {}) {
                Label("Paramètres", systemImage: "gearshape")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: 0x6B7280))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 15).padding(.vertical, 9)
        .background(Color(hex: 0x131720))
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .medium)).kerning(1.1)
            .foregroundColor(Color(hex: 0x6B7280))
    }

    private func hms(_ s: Int) -> String {
        String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    private func hm(_ s: Int) -> String {
        String(format: "%d:%02d", s / 3600, (s % 3600) / 60)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
            red:     Double((hex >> 16) & 0xFF) / 255,
            green:   Double((hex >> 8)  & 0xFF) / 255,
            blue:    Double( hex        & 0xFF) / 255,
            opacity: alpha)
    }
}

#Preview {
    PopoverView(stats: SessionStats(
        todayDuration: 9240, weekDuration: 51120, monthDuration: 169680,
        projectsThisWeek: [
            ProjectStat(name: "ClauWatch", path: "/ClauWatch", duration: 9240),
            ProjectStat(name: "ProjectAPI", path: "/ProjectAPI", duration: 30060),
            ProjectStat(name: "Dashboard",  path: "/Dashboard",  duration: 11820)
        ],
        activeSession: ActiveSession(projectName: "ClauWatch",
                                     startedAt: Date().addingTimeInterval(-4324))
    ))
}
```

- [ ] **Step 3: Build**

```bash
swift build
```
Expected: no errors. Open `Package.swift` in Xcode to verify the Preview renders.

- [ ] **Step 4: Commit**

```bash
git add Sources/ClauWatch/PopoverView.swift Sources/ClauWatch/Resources/
git commit -m "feat(ui): add PopoverView with OKLCH palette and PerpetuaMTPro font"
```

---

## Task 9: MenubarController

**Files:**
- Create: `Sources/ClauWatch/MenubarController.swift`

- [ ] **Step 1: Create `MenubarController.swift`**

```swift
import AppKit
import SwiftUI
import ClauWatchCore

@MainActor
class MenubarController {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let store: SessionStore
    private let monitor: ProcessMonitor
    private var refreshTimer: Timer?

    init(store: SessionStore, monitor: ProcessMonitor) {
        self.store = store
        self.monitor = monitor
        setupStatusItem()
        setupPopover()
        wireProcessMonitor()
        startRefreshTimer()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "timer",
                               accessibilityDescription: "ClauWatch")
        button.imagePosition = .imageLeft
        button.action = #selector(togglePopover)
        button.target = self
        updateTitle()
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(stats: emptyStats()))
    }

    private func wireProcessMonitor() {
        monitor.onSessionEnd = { [weak self] _ in
            Task { @MainActor [weak self] in
                let now = Int64(Date().timeIntervalSince1970)
                try? self?.store.closeOpenSessions(endedAtTime: now)
                self?.refresh()
            }
        }
        monitor.start()
    }

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        refresh()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func refresh() {
        let stats = (try? store.stats()) ?? emptyStats()
        updateTitle(stats)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(stats: stats))
    }

    private func updateTitle(_ stats: SessionStats? = nil) {
        let d = stats?.todayDuration ?? 0
        statusItem.button?.title = " \(d / 3600):\(String(format: "%02d", (d % 3600) / 60))"
    }

    private func emptyStats() -> SessionStats {
        SessionStats(todayDuration: 0, weekDuration: 0, monthDuration: 0,
                     projectsThisWeek: [], activeSession: nil)
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/ClauWatch/MenubarController.swift
git commit -m "feat(ui): add MenubarController with NSStatusItem"
```

---

## Task 10: App entry point

**Files:**
- Modify: `Sources/ClauWatch/main.swift`
- Create: `Sources/ClauWatch/AppDelegate.swift`
- Create: `Sources/ClauWatch/Resources/Info.plist`

- [ ] **Step 1: Add `Info.plist` (hides dock icon)**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key><true/>
    <key>CFBundleName</key><string>ClauWatch</string>
    <key>CFBundleIdentifier</key><string>com.clauwatch.app</string>
</dict>
</plist>
```

Add to `Package.swift` in the `executableTarget` resources array:

```swift
.process("Resources/Info.plist")
```

- [ ] **Step 2: Create `AppDelegate.swift`**

```swift
import AppKit
import ClauWatchCore

class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MenubarController?
    private let store: SessionStore
    private let monitor: ProcessMonitor

    init(store: SessionStore, monitor: ProcessMonitor) {
        self.store = store
        self.monitor = monitor
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Close sessions orphaned by a previous crash
        let now = Int64(Date().timeIntervalSince1970)
        try? store.closeStaleSessions(before: now - 600, endedAtTime: now)

        Task { @MainActor in
            self.controller = MenubarController(store: self.store, monitor: self.monitor)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }
}
```

- [ ] **Step 3: Replace `main.swift`**

```swift
import AppKit
import ClauWatchCore

let dbDir = ProcessInfo.processInfo.environment["CLAUWATCH_DIR"]
    ?? (NSHomeDirectory() + "/.clauwatch")
let dbPath = dbDir + "/data.db"

try? FileManager.default.createDirectory(
    atPath: dbDir, withIntermediateDirectories: true, attributes: nil)

guard let store = try? SessionStore(dbPath: dbPath) else {
    fputs("ClauWatch: cannot open database at \(dbPath)\n", stderr)
    exit(1)
}

let monitor = ProcessMonitor(interval: 10)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate(store: store, monitor: monitor)
app.delegate = delegate
app.run()
```

- [ ] **Step 4: Build release binary**

```bash
swift build -c release
```
Expected: `.build/release/ClauWatch` produced.

- [ ] **Step 5: Launch and verify**

```bash
.build/release/ClauWatch &
```
Expected: timer icon appears in macOS menubar. Click it — popover opens with LIVE dot if a Claude Code session is active.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClauWatch/main.swift Sources/ClauWatch/AppDelegate.swift \
        Sources/ClauWatch/Resources/Info.plist Package.swift
git commit -m "feat: wire app entry point, AppDelegate, and crash recovery"
```

---

## Task 11: Crash recovery test + final verification

**Files:**
- Modify: `Tests/ClauWatchTests/SessionStoreTests.swift`

- [ ] **Step 1: Add crash recovery test**

Append to `SessionStoreTests`:

```swift
func testCloseStaleSessionsSparesFreshOnes() throws {
    let now = Int64(Date().timeIntervalSince1970)
    // Stale: last_seen 20 min ago
    try store.insertTestSession(path: "/stale", name: "stale",
        startedAt: now - 3600, endedAt: nil, duration: nil)
    try store.db.execute(
        "UPDATE sessions SET last_seen_at = \(now - 1200) WHERE project_path = '/stale'")
    // Fresh: last_seen 2 min ago
    try store.insertTestSession(path: "/fresh", name: "fresh",
        startedAt: now - 120, endedAt: nil, duration: nil)
    try store.db.execute(
        "UPDATE sessions SET last_seen_at = \(now - 120) WHERE project_path = '/fresh'")

    try store.closeStaleSessions(before: now - 600, endedAtTime: now)

    let s = try store.stats()
    XCTAssertEqual(s.activeSession?.projectName, "fresh")
}
```

- [ ] **Step 2: Run full test suite**

```bash
swift test
```
Expected: `9 tests passed, 0 failed`

- [ ] **Step 3: Run full bun test suite**

```bash
bun test hooks/
```
Expected: `6 pass`

- [ ] **Step 4: Commit**

```bash
git add Tests/ClauWatchTests/SessionStoreTests.swift
git commit -m "test: add crash recovery test for closeStaleSessions"
```

---

## Self-Review

**Spec coverage:**
| Requirement | Task |
|---|---|
| SessionStart hook inserts session | Task 2 |
| UserPromptSubmit heartbeat | Task 3 |
| Global hooks registered | Task 4 |
| SQLite schema at `~/.clauwatch/data.db` | Task 1 |
| Stats: today / week / month | Task 6 `totalDuration` |
| Per-project breakdown | Task 6 `projectBreakdown` |
| Process monitor 10s poll | Task 7 |
| Session close on process exit | Task 9 `wireProcessMonitor` |
| Crash recovery on launch | Task 10 `AppDelegate` + Task 11 test |
| Menubar icon + time display | Task 9 `updateTitle` |
| Popover with OKLCH palette | Task 8 |
| PerpetuaMTPro-Regular font | Task 8 |
| LSUIElement (no dock icon) | Task 10 `Info.plist` |
| Error logging to `.log` | Task 2 (session-start catches + logs) |
| `macOS only` scope | Package.swift `.macOS(.v14)` |

**Tabler Icons note:** Tabler is a web library — unavailable natively in SwiftUI. Equivalent SF Symbols used (`clock`, `folder`, `folder.fill`, `sun.min`, `calendar`, `timer`, `play.fill`, `square.grid.2x2`, `gearshape`). To use actual Tabler SVGs in v2: add as PDF assets in `Resources/Icons/`.

**Placeholder scan:** No TBD, no "similar to Task N", no vague error handling steps — all catch blocks show exact code.

**Type consistency:** `SessionStats`, `ProjectStat`, `ActiveSession` defined Task 6, used Tasks 8–10. `closeStaleSessions(before:endedAtTime:)` defined Task 6, called Task 10, tested Task 11. `insertTestSession` defined Task 6 helper, reused Task 11. `hm()` / `hms()` defined Task 8, self-contained.
