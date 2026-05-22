import Testing
import Foundation
@testable import ClauWatchCore

@Suite struct ProcessMonitorTests {
    @Test func claudePIDsReturnsArray() {
        let monitor = ProcessMonitor(interval: 1)
        let pids = monitor.claudePIDs()
        #expect(pids != nil)
    }

    @Test func exitCallbackFiresForVanishedPID() async {
        let monitor = ProcessMonitor(interval: 0.1)
        monitor.knownPIDs = [Int32.max] // fake PID guaranteed absent from ps

        var firedPID: Int32?

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            monitor.onSessionEnd = { pid in
                if !resumed {
                    resumed = true
                    firedPID = pid
                    continuation.resume()
                }
            }
            monitor.start()
        }
        monitor.stop()
        #expect(firedPID == Int32.max)
    }
}
