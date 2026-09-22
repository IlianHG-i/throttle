import Foundation

enum Formatting {
    static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        return f
    }()

    static func bytes(_ value: UInt64) -> String {
        byteFormatter.string(fromByteCount: Int64(value))
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }
}
