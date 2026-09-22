import AppKit
import Combine
import Darwin
import CLibProc

/// Polls system-wide CPU/RAM usage and per-application resource usage,
/// and exposes the ability to pause (SIGSTOP) / resume (SIGCONT) an app
/// via NSRunningApplication, the same mechanism the Dock uses.
@MainActor
final class SystemMonitor: ObservableObject {

    @Published private(set) var systemCPUPercent: Double = 0
    @Published private(set) var usedMemoryBytes: UInt64 = 0
    @Published private(set) var totalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    @Published private(set) var apps: [AppInfo] = []

    private var previousCPUTicks: host_cpu_load_info?
    private var previousAppCPU: [pid_t: (cpuNanoseconds: UInt64, timestamp: Date)] = [:]
    private var timer: Timer?

    var usedMemoryFraction: Double {
        guard totalMemoryBytes > 0 else { return 0 }
        return Double(usedMemoryBytes) / Double(totalMemoryBytes)
    }

    func start(interval: TimeInterval = 2.0) {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        refreshSystemCPU()
        refreshSystemMemory()
        refreshApps()
    }

    // MARK: - System-wide CPU

    private func refreshSystemCPU() {
        var cpuLoadInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &cpuLoadInfo) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return }

        if let previous = previousCPUTicks {
            let userDelta = Double(cpuLoadInfo.cpu_ticks.0 &- previous.cpu_ticks.0)
            let systemDelta = Double(cpuLoadInfo.cpu_ticks.1 &- previous.cpu_ticks.1)
            let idleDelta = Double(cpuLoadInfo.cpu_ticks.2 &- previous.cpu_ticks.2)
            let niceDelta = Double(cpuLoadInfo.cpu_ticks.3 &- previous.cpu_ticks.3)
            let totalDelta = userDelta + systemDelta + idleDelta + niceDelta
            if totalDelta > 0 {
                systemCPUPercent = ((userDelta + systemDelta + niceDelta) / totalDelta) * 100
            }
        }
        previousCPUTicks = cpuLoadInfo
    }

    // MARK: - System-wide memory

    private func refreshSystemMemory() {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &vmStats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        let used = UInt64(vmStats.active_count + vmStats.wire_count + vmStats.compressor_page_count) * UInt64(pageSize)
        usedMemoryBytes = used
    }

    // MARK: - Per-app resource usage

    private func refreshApps() {
        let now = Date()
        let selfPid = ProcessInfo.processInfo.processIdentifier
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != selfPid
        }

        var updated: [AppInfo] = []
        updated.reserveCapacity(running.count)

        for app in running {
            let pid = app.processIdentifier
            guard pid > 0 else { continue }

            var rusage = rusage_info_v4()
            let rc = withUnsafeMutablePointer(to: &rusage) { ptr -> Int32 in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reboundPtr in
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, reboundPtr)
                }
            }

            var memoryBytes: UInt64 = 0
            var cpuPercent: Double = 0

            if rc == 0 {
                memoryBytes = rusage.ri_phys_footprint
                let cpuNs = rusage.ri_user_time + rusage.ri_system_time

                if let previous = previousAppCPU[pid] {
                    let elapsed = now.timeIntervalSince(previous.timestamp)
                    if elapsed > 0, cpuNs >= previous.cpuNanoseconds {
                        let deltaNs = Double(cpuNs - previous.cpuNanoseconds)
                        cpuPercent = (deltaNs / (elapsed * 1_000_000_000)) * 100
                    }
                }
                previousAppCPU[pid] = (cpuNs, now)
            }

            let name = app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent ?? "Unknown"

            updated.append(
                AppInfo(
                    id: pid,
                    bundleIdentifier: app.bundleIdentifier,
                    name: name,
                    icon: app.icon,
                    memoryBytes: memoryBytes,
                    cpuPercent: max(0, cpuPercent),
                    isSuspended: app.isTerminated ? false : appIsSuspended(pid: pid),
                    runningApplication: app
                )
            )
        }

        let deadPids = Set(previousAppCPU.keys).subtracting(updated.map { $0.id })
        for pid in deadPids { previousAppCPU.removeValue(forKey: pid) }

        apps = updated.sorted { $0.memoryBytes > $1.memoryBytes }
    }

    private func appIsSuspended(pid: pid_t) -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard result == 0 else { return false }
        // SSTOP == 4 in <sys/proc.h>
        return info.kp_proc.p_stat == 4
    }

    // MARK: - Pause / resume
    //
    // NSRunningApplication.suspend()/resume() were removed from the SDK, so we
    // send the same signals they used to send under the hood: SIGSTOP freezes
    // every thread of the process (this is what the Dock/kernel do when a
    // background app is put to sleep under memory pressure), SIGCONT wakes it
    // back up. Both only work on processes owned by the current user.

    @discardableResult
    func toggleSuspend(_ app: AppInfo) -> Bool {
        guard app.id != ProcessInfo.processInfo.processIdentifier else { return false }
        if ProtectedApps.isProtected(app.runningApplication) {
            return false
        }
        let signal = app.isSuspended ? SIGCONT : SIGSTOP
        return kill(app.id, signal) == 0
    }
}
