import Foundation

enum Formatting {
    /// Manual MB/GB formatting with one decimal place so small changes stay
    /// visible cycle to cycle — ByteCountFormatter's default MB rounding
    /// hides sub-megabyte drift, which made per-app memory look frozen.
    static func bytes(_ value: UInt64) -> String {
        let mb = Double(value) / 1_048_576
        if mb >= 1024 {
            return String(format: "%.2f GB", mb / 1024)
        }
        return String(format: "%.1f MB", mb)
    }

    /// System-wide percent (0-100), whole number is fine here since it
    /// swings by several points a second.
    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    /// Per-app CPU percent: idle apps typically sit well under 1%, so a
    /// whole-number format always reads "0%". One decimal keeps it visible.
    static func appCPUPercent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }
}
