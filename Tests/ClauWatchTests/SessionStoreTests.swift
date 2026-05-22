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
}
