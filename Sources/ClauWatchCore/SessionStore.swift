import Foundation
import SQLite

// MARK: - Public model types

public struct SessionStats {
    public let todayDuration: Int
    public let weekDuration: Int
    public let monthDuration: Int
    public let projectsThisWeek: [ProjectStat]
    public let activeSession: ActiveSession?
    public init(todayDuration: Int, weekDuration: Int, monthDuration: Int,
                projectsThisWeek: [ProjectStat], activeSession: ActiveSession?) {
        self.todayDuration = todayDuration; self.weekDuration = weekDuration
        self.monthDuration = monthDuration; self.projectsThisWeek = projectsThisWeek
        self.activeSession = activeSession
    }
}

public struct ProjectStat {
    public let name: String
    public let path: String
    public let duration: Int
    public init(name: String, path: String, duration: Int) {
        self.name = name; self.path = path; self.duration = duration
    }
}

public struct ActiveSession {
    public let projectName: String
    public let startedAt: Date
    public init(projectName: String, startedAt: Date) {
        self.projectName = projectName; self.startedAt = startedAt
    }
}

// MARK: - Column definitions

private let sessionTable    = Table("sessions")
private let colId           = SQLite.Expression<Int64>("id")
private let colProjectPath  = SQLite.Expression<String>("project_path")
private let colProjectName  = SQLite.Expression<String>("project_name")
private let colStartedAt    = SQLite.Expression<Int64>("started_at")
private let colEndedAt      = SQLite.Expression<Int64?>("ended_at")
private let colLastSeenAt   = SQLite.Expression<Int64?>("last_seen_at")
private let colDuration     = SQLite.Expression<Int64?>("duration")

// MARK: - SessionStore

public class SessionStore {
    let db: Connection

    public init(dbPath: String) throws {
        db = try Connection(dbPath)
        try db.run(sessionTable.create(ifNotExists: true) { t in
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
            todayDuration:    try totalDuration(from: todayStart, now: now),
            weekDuration:     try totalDuration(from: weekStart,  now: now),
            monthDuration:    try totalDuration(from: monthStart, now: now),
            projectsThisWeek: try projectBreakdown(from: weekStart, now: now),
            activeSession:    try currentActive()
        )
    }

    // MARK: - Internal helpers

    func totalDuration(from start: Int64, now: Int64) throws -> Int {
        var total: Int64 = 0
        for row in try db.prepare(sessionTable.filter(colStartedAt >= start)) {
            if let dur = row[colDuration] {
                total += dur
            } else {
                total += now - row[colStartedAt]
            }
        }
        return Int(total)
    }

    func projectBreakdown(from start: Int64, now: Int64) throws -> [ProjectStat] {
        var map: [String: (name: String, duration: Int64)] = [:]
        for row in try db.prepare(sessionTable.filter(colStartedAt >= start)) {
            let path = row[colProjectPath]
            let name = row[colProjectName]
            let dur  = row[colDuration] ?? (now - row[colStartedAt])
            let existing = map[path]?.duration ?? 0
            map[path] = (name: name, duration: existing + dur)
        }
        return map.map { path, pair in
            ProjectStat(name: pair.name, path: path, duration: Int(pair.duration))
        }.sorted { $0.duration > $1.duration }
    }

    func currentActive() throws -> ActiveSession? {
        let q = sessionTable
            .filter(colEndedAt == nil)
            .order(colStartedAt.desc)
            .limit(1)
        guard let row = try db.pluck(q) else { return nil }
        return ActiveSession(
            projectName: row[colProjectName],
            startedAt:   Date(timeIntervalSince1970: TimeInterval(row[colStartedAt]))
        )
    }

    // MARK: - Public mutation

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

    // MARK: - Test helpers (not called from production code)

    func insertTestSession(path: String, name: String,
                           startedAt: Int64, endedAt: Int64?, duration: Int64?) throws {
        try db.run(sessionTable.insert(
            colProjectPath <- path,
            colProjectName <- name,
            colStartedAt   <- startedAt,
            colEndedAt     <- endedAt,
            colLastSeenAt  <- startedAt,
            colDuration    <- duration
        ))
    }
}
