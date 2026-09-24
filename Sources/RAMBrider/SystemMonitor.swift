import AppKit
import Combine
import Darwin
import CLibProc

/// Polls system-wide CPU/RAM usage and per-application resource usage,
/// and exposes the ability to pause (SIGSTOP) / resume (SIGCONT) an app
/// via NSRunningApplication, the same mechanism the Dock uses.
@MainActor
final class SystemMonitor: ObservableObject {

    static let shared = SystemMonitor()

    @Published private(set) var systemCPUPercent: Double = 0
    @Published private(set) var usedMemoryBytes: UInt64 = 0
    @Published private(set) var totalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    @Published private(set) var apps: [AppInfo] = []

    private var previousCPUTicks: host_cpu_load_info?
    private var previousAppCPU: [pid_t: (cpuNanoseconds: UInt64, timestamp: Date)] = [:]
    private var lastRefreshDate: Date?
    private var timer: Timer?

    /// Source of truth for pause/resume: apps *we* have suspended. Driven
    /// directly by our own toggle instead of re-derived from `sysctl` each
    /// refresh, so the button state is deterministic and never races the
    /// kernel actually finishing the stop.
    private var suspendedPids: Set<pid_t> = []

    var usedMemoryFraction: Double {
        guard totalMemoryBytes > 0 else { return 0 }
        return Double(usedMemoryBytes) / Double(totalMemoryBytes)
    }

    func start(interval: TimeInterval = 1.0) {
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

    // MARK: - Process tree
    //
    // Electron/Chromium-based apps (Discord, Chrome, Slack, VS Code...) split
    // themselves into a main process plus several helpers (renderer, GPU,
    // network, audio...). Reading only the main pid was undercounting CPU/RAM
    // by a lot and, worse, "pausing" left the helpers running. We walk the
    // whole descendant tree per app instead.

    private func directChildPids(of pid: pid_t) -> [pid_t] {
        let neededBytes = proc_listchildpids(pid, nil, 0)
        guard neededBytes > 0 else { return [] }
        let capacity = Int(neededBytes) / MemoryLayout<pid_t>.size
        var buffer = [pid_t](repeating: 0, count: capacity)
        let filledBytes = buffer.withUnsafeMutableBytes { raw in
            proc_listchildpids(pid, raw.baseAddress, Int32(raw.count))
        }
        guard filledBytes > 0 else { return [] }
        let count = min(capacity, Int(filledBytes) / MemoryLayout<pid_t>.size)
        return Array(buffer[0..<count])
    }

    /// Root pid plus every descendant, breadth-first. Capped defensively —
    /// real app trees are a handful of processes.
    private func processTree(rootPid: pid_t) -> [pid_t] {
        var tree = [rootPid]
        var frontier = [rootPid]
        var visited: Set<pid_t> = [rootPid]

        while !frontier.isEmpty, tree.count < 256 {
            var next: [pid_t] = []
            for pid in frontier {
                for child in directChildPids(of: pid) where !visited.contains(child) {
                    visited.insert(child)
                    next.append(child)
                }
            }
            tree.append(contentsOf: next)
            frontier = next
        }
        return tree
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
        var touchedPids: Set<pid_t> = []

        for app in running {
            let pid = app.processIdentifier
            guard pid > 0 else { continue }

            var totalMemory: UInt64 = 0
            var totalCPUDeltaNs: Double = 0

            for memberPid in processTree(rootPid: pid) {
                touchedPids.insert(memberPid)

                var rusage = rusage_info_v4()
                let rc = withUnsafeMutablePointer(to: &rusage) { ptr -> Int32 in
                    ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reboundPtr in
                        proc_pid_rusage(memberPid, RUSAGE_INFO_V4, reboundPtr)
                    }
                }
                guard rc == 0 else { continue }

                totalMemory += rusage.ri_phys_footprint
                let cpuNs = rusage.ri_user_time + rusage.ri_system_time

                if let previous = previousAppCPU[memberPid] {
                    let elapsed = now.timeIntervalSince(previous.timestamp)
                    if elapsed > 0, cpuNs >= previous.cpuNanoseconds {
                        totalCPUDeltaNs += Double(cpuNs - previous.cpuNanoseconds)
                    }
                }
                previousAppCPU[memberPid] = (cpuNs, now)
            }

            let elapsedSinceLastRefresh = now.timeIntervalSince(lastRefreshDate ?? now)
            let cpuPercent = elapsedSinceLastRefresh > 0
                ? (totalCPUDeltaNs / (elapsedSinceLastRefresh * 1_000_000_000)) * 100
                : 0

            let name = app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent ?? "Unknown"

            updated.append(
                AppInfo(
                    id: pid,
                    bundleIdentifier: app.bundleIdentifier,
                    name: name,
                    icon: app.icon,
                    memoryBytes: totalMemory,
                    cpuPercent: max(0, cpuPercent),
                    isSuspended: suspendedPids.contains(pid),
                    runningApplication: app
                )
            )
        }
        lastRefreshDate = now

        let deadPids = Set(previousAppCPU.keys).subtracting(touchedPids)
        for pid in deadPids { previousAppCPU.removeValue(forKey: pid) }
        suspendedPids.formIntersection(Set(updated.map { $0.id }))

        apps = updated.sorted { $0.memoryBytes > $1.memoryBytes }
    }

    // MARK: - Pause / resume
    //
    // NSRunningApplication.suspend()/resume() were removed from the SDK, so we
    // send the same signals they used to send under the hood: SIGSTOP freezes
    // every thread of the process (this is what the Dock/kernel do when a
    // background app is put to sleep under memory pressure), SIGCONT wakes it
    // back up. Both only work on processes owned by the current user.

    /// Pauses/resumes the app's whole process tree, not just the main pid —
    /// otherwise helper processes (Electron renderer/GPU/network...) keep
    /// running and the memory never actually gets freed.
    @discardableResult
    func toggleSuspend(_ app: AppInfo) -> Bool {
        guard app.id != ProcessInfo.processInfo.processIdentifier else { return false }
        if ProtectedApps.isProtected(app.runningApplication) {
            return false
        }
        let alreadySuspended = suspendedPids.contains(app.id)
        let signal = alreadySuspended ? SIGCONT : SIGSTOP
        var succeededAny = false
        for pid in processTree(rootPid: app.id) where kill(pid, signal) == 0 {
            succeededAny = true
        }
        guard succeededAny else { return false }
        if alreadySuspended {
            suspendedPids.remove(app.id)
        } else {
            suspendedPids.insert(app.id)
        }
        return true
    }

    /// Quits an app. If it's currently paused, its whole tree is resumed
    /// first — a frozen process can't process a quit request, so terminate()
    /// would silently do nothing on a suspended app.
    @discardableResult
    func terminate(_ app: AppInfo) -> Bool {
        guard app.id != ProcessInfo.processInfo.processIdentifier else { return false }
        if ProtectedApps.isProtected(app.runningApplication) {
            return false
        }
        if suspendedPids.remove(app.id) != nil {
            for pid in processTree(rootPid: app.id) { kill(pid, SIGCONT) }
        }
        return app.runningApplication.terminate()
    }

    /// Emergency escape hatch: resume every app we've suspended (whole tree
    /// each). Multi-process apps (Electron apps like Discord/Slack/VS Code)
    /// can make the whole app look hung and block relaunch through the Dock
    /// (single-instance lock can't respond while frozen) — this is the
    /// reliable way back.
    func resumeAll() {
        for rootPid in suspendedPids {
            for pid in processTree(rootPid: rootPid) { kill(pid, SIGCONT) }
        }
        suspendedPids.removeAll()
        refresh()
    }

    var suspendedCount: Int {
        suspendedPids.count
    }
}
