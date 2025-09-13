import Foundation
import CNCurses
import OTClient

struct TopologyViews {

    // Clean up Unicode artifacts that don't display well in terminal
    private static func cleanUnicodeArtifacts(_ text: String) -> String {
        return text
            // Replace problematic Unicode emojis with ASCII alternatives
            .replacingOccurrences(of: "🟢", with: "[ACTIVE]")
            .replacingOccurrences(of: "🟡", with: "[WARN]")
            .replacingOccurrences(of: "🔴", with: "[ERROR]")
            .replacingOccurrences(of: "⚫", with: "[OFF]")
            .replacingOccurrences(of: "⚪", with: "[UNKNOWN]")
            .replacingOccurrences(of: "🔀", with: "[RTR]")
            .replacingOccurrences(of: "🌐", with: "[NET]")
            .replacingOccurrences(of: "💾", with: "[VOL]")
            .replacingOccurrences(of: "🖥", with: "[SRV]")
            .replacingOccurrences(of: "🖧", with: "[NET]")
            // Replace diamond symbol that might not display well
            .replacingOccurrences(of: "◆", with: "*")
            // Replace any remaining unknown Unicode characters with safe ASCII
            .replacingOccurrences(of: "�", with: "[?]")
            // Replace other potentially problematic characters
            .replacingOccurrences(of: "├", with: "|")
            .replacingOccurrences(of: "└", with: "`")
            .replacingOccurrences(of: "─", with: "-")
            .replacingOccurrences(of: "│", with: "|")
    }

    @MainActor
    static func drawTopologyView(screen: OpaquePointer?, startRow: Int32, startCol: Int32,
                                width: Int32, height: Int32, topology: TopologyGraph?) async {
        wattron(screen, ViewUtils.colorPair(2))
        wmove(screen, startRow, startCol + 2)
        waddstr(screen, "* Network Topology")
        wattroff(screen, ViewUtils.colorPair(2))

        guard let topology = topology else {
            wmove(screen, startRow + 2, startCol + 4)
            wattron(screen, ViewUtils.colorPair(4))
            waddstr(screen, "Topology data not available. Press R to refresh.")
            wattroff(screen, ViewUtils.colorPair(4))

            wmove(screen, startRow + height - 2, startCol + 2)
            wattron(screen, ViewUtils.colorPair(4))
            waddstr(screen, "Press R to refresh topology | ESC to return")
            wattroff(screen, ViewUtils.colorPair(4))
            return
        }

        var currentRow = startRow + 2
        let contentHeight = Int(height) - 4 // Leave space for header and instructions
        let maxRows = min(topology.asciiDiagram.count, contentHeight)

        // Display the ASCII diagram from TopologyGraph
        for i in 0..<maxRows {
            let line = cleanUnicodeArtifacts(topology.asciiDiagram[i])
            wmove(screen, currentRow, startCol + 2)

            // Colorize different parts of the diagram
            if line.contains("Network:") {
                wattron(screen, ViewUtils.colorPair(3))
                waddstr(screen, line)
                wattroff(screen, ViewUtils.colorPair(3))
            } else if line.contains("Server:") || line.contains("[ACTIVE]") || line.contains("[INACTIVE]") || line.contains("[ERROR]") || line.contains("[UNKNOWN]") {
                wattron(screen, ViewUtils.colorPair(6))
                waddstr(screen, line)
                wattroff(screen, ViewUtils.colorPair(6))
            } else if line.contains("Router:") || line.contains("[RTR]") {
                wattron(screen, ViewUtils.colorPair(5))
                waddstr(screen, line)
                wattroff(screen, ViewUtils.colorPair(5))
            } else if line.contains("Volume:") || line.contains("[VOL]") {
                wattron(screen, ViewUtils.colorPair(2))
                waddstr(screen, line)
                wattroff(screen, ViewUtils.colorPair(2))
            } else if line.contains("Floating IP:") || line.contains("Gateway IP:") || line.contains("[FIP]") {
                wattron(screen, ViewUtils.colorPair(7))
                waddstr(screen, line)
                wattroff(screen, ViewUtils.colorPair(7))
            } else if line.contains("====") || line.contains("----") {
                wattron(screen, ViewUtils.colorPair(4))
                waddstr(screen, line)
                wattroff(screen, ViewUtils.colorPair(4))
            } else {
                wattron(screen, ViewUtils.colorPair(6))
                waddstr(screen, line)
                wattroff(screen, ViewUtils.colorPair(6))
            }

            currentRow += 1
        }

        // Show scroll indicator if there's more content
        if topology.asciiDiagram.count > maxRows {
            wmove(screen, startRow + height - 3, startCol + Int32(width) - 25)
            wattron(screen, ViewUtils.colorPair(4))
            waddstr(screen, "... and \(topology.asciiDiagram.count - maxRows) more lines")
            wattroff(screen, ViewUtils.colorPair(4))
        }

        // Instructions
        wmove(screen, startRow + height - 2, startCol + 2)
        wattron(screen, ViewUtils.colorPair(4))
        waddstr(screen, "Press R to refresh topology | W to export | ESC to return")
        wattroff(screen, ViewUtils.colorPair(4))
    }
}