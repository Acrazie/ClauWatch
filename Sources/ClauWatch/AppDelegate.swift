import AppKit
import CoreText
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
        if let url = Bundle.module.url(forResource: "PerpetuaMTRegular", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }

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
