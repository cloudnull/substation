import Foundation
import OTClient

struct FormatUtils {
    static func formatImageSize(_ size: Int?) -> String {
        guard let size = size else { return "unknown   " }
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

    static func wrapText(_ text: String, maxWidth: Int) -> [String] {
        guard maxWidth > 0 else { return [text] }

        var lines: [String] = []
        var currentIndex = text.startIndex

        while currentIndex < text.endIndex {
            let endIndex = text.index(currentIndex, offsetBy: maxWidth, limitedBy: text.endIndex) ?? text.endIndex
            let line = String(text[currentIndex..<endIndex])
            lines.append(line)
            currentIndex = endIndex
        }

        return lines.isEmpty ? [""] : lines
    }
}