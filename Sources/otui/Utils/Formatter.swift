import Foundation

struct Formatter {
    static func formatImageSize(_ size: Int?) -> String {
        guard let size = size else {
            return "Unknown     ".padding(toLength: 12, withPad: " ", startingAt: 0)
        }

        if size < 1024 * 1024 * 1024 {
            return String(format: "%dMB     ", size / (1024 * 1024)).padding(toLength: 12, withPad: " ", startingAt: 0)
        } else {
            return String(format: "%.1fGB    ", Double(size) / (1024.0 * 1024.0 * 1024.0)).padding(toLength: 12, withPad: " ", startingAt: 0)
        }
    }

    static func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 * 1024 * 1024 {
            return String(format: "%dMB", bytes / (1024 * 1024))
        } else {
            return String(format: "%.1fGB", Double(bytes) / (1024.0 * 1024.0 * 1024.0))
        }
    }
}