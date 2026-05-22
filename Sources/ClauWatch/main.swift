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
