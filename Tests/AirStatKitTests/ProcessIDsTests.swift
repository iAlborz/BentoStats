import Testing
import Foundation
@testable import AirStatKit

@Suite("Listing processes through sysctl, as the App Sandbox allows")
struct ProcessIDsTests {

    @Test("lists every process, this one among them, as proc_listpids does")
    func listsEveryProcess() throws {
        var pids: [pid_t] = []
        let count = try #require(kernProcPIDs(&pids, filter: UInt32(PROC_ALL_PIDS), argument: 0))
        #expect(pids.prefix(count).contains(getpid()))

        var listed = [pid_t](repeating: 0, count: 8192)
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &listed, Int32(listed.count * MemoryLayout<pid_t>.size))
        let expected = Int(bytes) / MemoryLayout<pid_t>.size
        // Processes come and go between the two reads.
        #expect(abs(count - expected) <= max(10, expected / 20), "sysctl \(count), proc_listpids \(expected)")
    }

    @Test("lists only this user's processes when asked for them")
    func listsOneUser() throws {
        var all: [pid_t] = []
        let total = try #require(kernProcPIDs(&all, filter: UInt32(PROC_ALL_PIDS), argument: 0))
        var mine: [pid_t] = []
        let own = try #require(kernProcPIDs(&mine, filter: UInt32(PROC_UID_ONLY), argument: geteuid()))
        #expect(own > 0 && own < total)
        #expect(mine.prefix(own).contains(getpid()))
    }
}
