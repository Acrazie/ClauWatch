# ClauWatch — Design Spec

**Date:** 2026-05-22
**Status:** Approved

---

## Overview

macOS menubar app that tracks time spent in Claude Code sessions. While the `claude` process runs, time is counted. Stats are surfaced as a native SwiftUI tray popover with daily, weekly, and monthly totals, broken down by project.

---

## Architecture

Three layers with clear boundaries.

### 1. Hooks layer (bun)

Claude Code hooks write session events to SQLite. Two scripts registered in `~/.claude/settings.json`:

- **`SessionStart` hook** — inserts a new session record with `started_at` timestamp and `project_path` (working directory from hook context).
- **`UserPromptSubmit` hook** — updates `last_seen_at` on the current session (heartbeat). Used as fallback end-of-session signal.

Scripts live in `~/.clauwatch/hooks/` and are shared across all projects (global hooks, not per-repo).

### 2. Storage (SQLite)

Database at `~/.clauwatch/data.db`. Single table:

```sql
CREATE TABLE sessions (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  project_path TEXT    NOT NULL,
  project_name TEXT    NOT NULL,
  started_at   INTEGER NOT NULL,  -- unix timestamp
  ended_at     INTEGER,           -- null = session still open
  last_seen_at INTEGER,           -- updated by heartbeat hook
  duration     INTEGER            -- seconds, computed on close
);
```

`project_name` is derived from the basename of `project_path`.

### 3. Swift menubar app

Native macOS app (`NSStatusItem` + SwiftUI popover). Reads SQLite directly via the `SQLite.swift` package. No bun dependency at runtime.

**Session end detection:** The Swift app polls for the `claude` process every 10 seconds via `NSRunningApplication.runningApplications(withBundleIdentifier:)` or a `ps` query. When the process disappears, it closes any open session by writing `ended_at = now` and computing `duration`. This is more reliable than a `SessionStop` hook (which may not fire on crash or force-quit).

**Polling interval:** 10s for process check. SQLite reads on popover open + after each process-exit event.

---

## UI

### Menubar icon

`⏱ 2:34` — icon + today's total in hours:minutes. Updates every minute while a session is open.

### Popover (288px, dark, opens on click)

```
┌─────────────────────────────────┐
│ 🕓  ClauWatch          ● LIVE   │  ← PerpetuaMTPro, OKLCH slate
├─────────────────────────────────┤
│ SESSION ACTIVE                  │
│  📁 ClauWatch      ▶ 1:12:04   │  ← Geist Mono timer badge
├─────────────────────────────────┤
│ TEMPS CUMULÉ                    │
│  ┌────────┬────────┬────────┐   │
│  │ Auj.   │ Sem.   │ Mai    │   │
│  │ 2:34   │ 14:12  │ 47:08  │   │  ← PerpetuaMTPro values
│  │ heures │ heures │ heures │   │
│  └────────┴────────┴────────┘   │
├─────────────────────────────────┤
│ PROJETS · CETTE SEMAINE         │
│  📁 ClauWatch  ████████  2:34  │  ← accent color (active)
│  📁 ProjectAPI ██████░░  8:21  │
│  📁 Dashboard  ███░░░░░  3:17  │
├─────────────────────────────────┤
│  ⊞ Vue complète   ⚙ Paramètres │
└─────────────────────────────────┘
```

### Design tokens

| Token | Value |
|---|---|
| Background | `oklch(0.09 0.010 248)` |
| Surface | `oklch(0.12 0.008 248)` |
| Border | `oklch(0.22 0.006 248)` |
| Muted text | `oklch(0.46 0.006 248)` |
| Foreground | `oklch(0.94 0.004 248)` |
| Accent (emerald) | `oklch(0.72 0.16 145)` |
| Font serif | PerpetuaMTPro-Regular, letter-spacing 0.12em |
| Font sans | Geist |
| Font mono | Geist Mono |
| Icons | Tabler Icons |

---

## Data flow

```
Claude Code process starts
  → SessionStart hook (bun)
    → INSERT sessions (project_path, started_at)

User types message
  → UserPromptSubmit hook (bun)
    → UPDATE sessions SET last_seen_at = now WHERE ended_at IS NULL

Claude Code process exits
  → Swift app detects via 10s poll
    → UPDATE sessions SET ended_at = now, duration = ended_at - started_at
```

---

## Scope: v1

| In | Out |
|---|---|
| macOS only | Windows / Linux |
| Global + per-project daily/weekly/monthly | Yearly view |
| Session end via process monitor | SessionStop hook |
| SQLite local storage | Cloud sync |
| Menubar popover | Full window / web dashboard |
| Tabler + PerpetuaMTPro + Geist | Custom icon |

"Vue complète" footer link is present in UI but deferred: it opens a larger native window in v2.

---

## File layout

```
ClauWatch/
├── ClauWatch.xcodeproj
├── ClauWatch/               # Swift app
│   ├── App.swift
│   ├── MenubarController.swift
│   ├── PopoverView.swift
│   ├── SessionStore.swift   # SQLite reads
│   └── Resources/
│       └── Fonts/           # PerpetuaMTPro-Regular.otf
├── hooks/                   # bun scripts
│   ├── session-start.ts
│   └── heartbeat.ts
├── package.json             # bun workspace
└── docs/
    └── superpowers/specs/
        └── 2026-05-22-clauwatch-design.md
```

Hook scripts are symlinked or referenced from `~/.claude/settings.json` as global hooks.

---

## Error handling

- SQLite write failure in hook: log to `~/.clauwatch/errors.log`, do not crash Claude Code session.
- Process poll finds multiple `claude` instances: track each separately by PID, one session row per PID.
- Open session on app launch (crash recovery): if `ended_at IS NULL` and `last_seen_at < now - 10min`, close it with `ended_at = last_seen_at`.
