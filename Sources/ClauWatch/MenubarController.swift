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
        if let url = Bundle.module.url(forResource: "product_logo", withExtension: "svg"),
           let logo = NSImage(contentsOf: url) {
            logo.size = NSSize(width: 18, height: 18)
            button.image = logo
        }
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
