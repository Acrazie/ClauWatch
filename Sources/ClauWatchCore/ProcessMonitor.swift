import Foundation

public class ProcessMonitor {
    private let interval: TimeInterval
    private var timer: Timer?
    private var timerThread: Thread?
    private var timerRunLoop: RunLoop?
    public var knownPIDs: Set<Int32> = []
    public var onSessionEnd: ((Int32) -> Void)?

    public init(interval: TimeInterval = 10.0) {
        self.interval = interval
    }

    public func start() {
        if knownPIDs.isEmpty {
            knownPIDs = Set(claudePIDs())
        }
        let t = Thread {
            let runLoop = RunLoop.current
            self.timerRunLoop = runLoop
            self.timer = Timer.scheduledTimer(withTimeInterval: self.interval, repeats: true) { [weak self] _ in
                self?.tick()
            }
            runLoop.run()
        }
        t.start()
        timerThread = t
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        timerRunLoop?.perform {
            // drain the run loop
        }
        timerThread?.cancel()
        timerThread = nil
        timerRunLoop = nil
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
