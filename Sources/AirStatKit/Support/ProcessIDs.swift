import Foundation

/// The pids `proc_listpids` would have given, read through `sysctl` instead, for when
/// `proc_listpids` is refused: the App Sandbox denies it but lets `kern.proc` through,
/// and `proc_pidinfo` on what it lists still works. Only the fallback, because it costs
/// several times as much: the kernel copies out a whole `kinfo_proc` per process rather
/// than a pid.
///
/// Takes `proc_listpids`'s own `filter` and `argument`, of which only `PROC_ALL_PIDS`
/// and `PROC_UID_ONLY` are used here; both match on the effective uid, as `kern.proc`
/// does. Fills `buffer`, growing it as needed, and returns how many entries are valid.
func kernProcPIDs(_ buffer: inout [pid_t], filter: UInt32, argument: UInt32) -> Int? {
    var mib: [Int32] = filter == UInt32(PROC_UID_ONLY)
        ? [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(bitPattern: argument)]
        : [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
    let stride = MemoryLayout<kinfo_proc>.stride
    // A process started between asking for the size and reading the table makes the
    // read fail with ENOMEM, so it is asked again, a few times at most.
    for _ in 0..<3 {
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0 else { return nil }
        var table = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 16)
        size = table.count * stride
        guard sysctl(&mib, u_int(mib.count), &table, &size, nil, 0) == 0 else {
            if errno == ENOMEM { continue }
            return nil
        }
        let count = size / stride
        if buffer.count < count { buffer = [pid_t](repeating: 0, count: count) }
        for index in 0..<count { buffer[index] = table[index].kp_proc.p_pid }
        return count
    }
    return nil
}
