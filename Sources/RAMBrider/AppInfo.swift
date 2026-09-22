import AppKit

struct AppInfo: Identifiable, Equatable {
    let id: pid_t
    let bundleIdentifier: String?
    let name: String
    let icon: NSImage?
    var memoryBytes: UInt64
    var cpuPercent: Double
    var isSuspended: Bool
    let runningApplication: NSRunningApplication

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.id == rhs.id
    }
}

enum ProtectedApps {
    /// Bundle identifiers we refuse to suspend because doing so could
    /// break the session (Finder, Dock, window server, ourselves, etc).
    static let excludedBundleIdentifiers: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.WindowManager",
        "com.apple.loginwindow",
        Bundle.main.bundleIdentifier ?? "com.ilianhg.RAMBrider"
    ]

    static func isProtected(_ app: NSRunningApplication) -> Bool {
        guard let bundleId = app.bundleIdentifier else { return false }
        return excludedBundleIdentifiers.contains(bundleId)
    }
}
