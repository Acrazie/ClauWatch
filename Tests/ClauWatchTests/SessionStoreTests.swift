import Testing
import Foundation
@testable import ClauWatchCore

@Suite struct SessionStoreTests {
    var store: SessionStore

    init() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        store = try SessionStore(dbPath: tmp.appendingPathComponent("data.db").path)
    }

    @Test func emptyStats() throws {
        let s = try store.stats()
        #expect(s.todayDuration == 0)
        #expect(s.weekDuration == 0)
        #expect(s.monthDuration == 0)
        #expect(s.projectsThisWeek.isEmpty)
        #expect(s.activeSession == nil)
    }

    @Test func todayDurationFromClosedSession() throws {
        let now = Int64(Date().timeIntervalSince1970)
        try store.insertTestSession(path: "/p", name: "p",
            startedAt: now - 3600, endedAt: now, duration: 3600)
        let s = try store.stats()
        #expect(abs(s.todayDuration - 3600) <= 2)
    }

    @Test func todayDurationFromOpenSession() throws {
        let now = Int64(Date().timeIntervalSince1970)
        try store.insertTestSession(path: "/p", name: "p",
            startedAt: now - 1800, endedAt: nil, duration: nil)
        let s = try store.stats()
        #expect(abs(s.todayDuration - 1800) <= 5)
    }

    @Test func activeSessionDetected() throws {
        let now = Int64(Date().timeIntervalSince1970)
        try store.insertTestSession(path: "/p", name: "MyProject",
            startedAt: now - 600, endedAt: nil, duration: nil)
        let s = try store.stats()
        #expect(s.activeSession?.projectName == "MyProject")
    }

    @Test func closeOpenSessions() throws {
        let now = Int64(Date().timeIntervalSince1970)
        try store.insertTestSession(path: "/p", name: "p",
            startedAt: now - 500, endedAt: nil, duration: nil)
        try store.closeOpenSessions(endedAtTime: now)
        let s = try store.stats()
        #expect(s.activeSession == nil)
        #expect(abs(s.todayDuration - 500) <= 2)
    }

    @Test func projectBreakdown() throws {
        let now = Int64(Date().timeIntervalSince1970)
        try store.insertTestSession(path: "/a", name: "alpha",
            startedAt: now - 7200, endedAt: now - 3600, duration: 3600)
        try store.insertTestSession(path: "/b", name: "beta",
            startedAt: now - 1800, endedAt: now, duration: 1800)
        let s = try store.stats()
        #expect(s.projectsThisWeek.map(\.name).contains("alpha"))
        #expect(s.projectsThisWeek.map(\.name).contains("beta"))
    }

    @Test func yesterdaySessionExcludedFromToday() throws {
        let cal = Calendar.current
        let todayStart = Int64(cal.startOfDay(for: Date()).timeIntervalSince1970)
        let yStart = todayStart - 7200
        let yEnd   = todayStart - 3600
        try store.insertTestSession(path: "/y", name: "y",
            startedAt: yStart, endedAt: yEnd, duration: yEnd - yStart)
        let s = try store.stats()
        #expect(s.todayDuration == 0)
    }

    @Test func lastWeekSessionExcludedFromWeek() throws {
        let eightDaysAgo = Int64(Date().timeIntervalSince1970) - 8 * 86400
        try store.insertTestSession(path: "/w", name: "w",
            startedAt: eightDaysAgo, endedAt: eightDaysAgo + 3600, duration: 3600)
        let s = try store.stats()
        #expect(s.weekDuration == 0)
        #expect(s.projectsThisWeek.isEmpty)
    }

    @Test func lastMonthSessionExcludedFromMonth() throws {
        let thirtyTwoDaysAgo = Int64(Date().timeIntervalSince1970) - 32 * 86400
        try store.insertTestSession(path: "/m", name: "m",
            startedAt: thirtyTwoDaysAgo, endedAt: thirtyTwoDaysAgo + 3600, duration: 3600)
        let s = try store.stats()
        #expect(s.monthDuration == 0)
    }

    @Test func weekDurationSumsMultipleSessions() throws {
        let now = Int64(Date().timeIntervalSince1970)
        try store.insertTestSession(path: "/a", name: "a",
            startedAt: now - 7200, endedAt: now - 3600, duration: 3600)
        try store.insertTestSession(path: "/b", name: "b",
            startedAt: now - 1800, endedAt: now, duration: 1800)
        let s = try store.stats()
        #expect(abs(s.weekDuration - 5400) <= 5)
    }

    @Test func projectsOrderedByDurationDesc() throws {
        let now = Int64(Date().timeIntervalSince1970)
        try store.insertTestSession(path: "/a", name: "alpha",
            startedAt: now - 1800, endedAt: now, duration: 1800)
        try store.insertTestSession(path: "/b", name: "beta",
            startedAt: now - 7200, endedAt: now, duration: 7200)
        let s = try store.stats()
        #expect(s.projectsThisWeek.first?.name == "beta")
        #expect(s.projectsThisWeek.last?.name == "alpha")
    }

    @Test func multipleSessionsSameProjectAccumulate() throws {
        let now = Int64(Date().timeIntervalSince1970)
        try store.insertTestSession(path: "/a", name: "alpha",
            startedAt: now - 7200, endedAt: now - 3600, duration: 3600)
        try store.insertTestSession(path: "/a", name: "alpha",
            startedAt: now - 1800, endedAt: now, duration: 1800)
        let s = try store.stats()
        let alpha = s.projectsThisWeek.first { $0.name == "alpha" }
        #expect(alpha?.duration == 5400)
    }

    @Test func activeSessionIsMostRecentWhenMultipleOpen() throws {
        let now = Int64(Date().timeIntervalSince1970)
        try store.insertTestSession(path: "/old", name: "OldProject",
            startedAt: now - 3600, endedAt: nil, duration: nil)
        try store.insertTestSession(path: "/new", name: "NewProject",
            startedAt: now - 600, endedAt: nil, duration: nil)
        let s = try store.stats()
        #expect(s.activeSession?.projectName == "NewProject")
    }

    @Test func closeOpenSessionsWritesComputedDuration() throws {
        let now = Int64(Date().timeIntervalSince1970)
        try store.insertTestSession(path: "/p", name: "p",
            startedAt: now - 1000, endedAt: nil, duration: nil)
        try store.closeOpenSessions(endedAtTime: now)
        let s = try store.stats()
        #expect(s.activeSession == nil)
        #expect(abs(s.todayDuration - 1000) <= 2)
    }

    @Test func closeStaleSessionsSparesFreshOnes() throws {
        let now = Int64(Date().timeIntervalSince1970)
        try store.insertTestSession(path: "/stale", name: "stale",
            startedAt: now - 3600, endedAt: nil, duration: nil)
        try store.db.execute(
            "UPDATE sessions SET last_seen_at = \(now - 1200) WHERE project_path = '/stale'")
        try store.insertTestSession(path: "/fresh", name: "fresh",
            startedAt: now - 120, endedAt: nil, duration: nil)
        try store.db.execute(
            "UPDATE sessions SET last_seen_at = \(now - 120) WHERE project_path = '/fresh'")

        try store.closeStaleSessions(before: now - 600, endedAtTime: now)

        let s = try store.stats()
        #expect(s.activeSession?.projectName == "fresh")
    }
}
