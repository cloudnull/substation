import Foundation
import CNCurses
import OTClient

struct NetworkViews {
    @MainActor
    static func drawDetailedNetworkList(screen: OpaquePointer?, startRow: Int32, startCol: Int32,
                                      width: Int32, height: Int32, cachedNetworks: [Network],
                                      searchQuery: String?, scrollOffset: Int, selectedIndex: Int) async {
        wattron(screen, ViewUtils.colorPair(2))
        wmove(screen, startRow, startCol + 2)
        let searchInfo = searchQuery != nil ? " (filtered: \(searchQuery!))" : ""
        waddstr(screen, "* Networks\(searchInfo)")
        wattroff(screen, ViewUtils.colorPair(2))

        let networks = FilterUtils.filterNetworks(cachedNetworks, query: searchQuery)
        let visibleHeight = Int(height) - 4 // Account for header and borders

        for i in 0..<visibleHeight {
            let networkIndex = scrollOffset + i
            let row = startRow + Int32(i) + 2

            if networkIndex >= networks.count {
                // Clear remaining lines
                wmove(screen, row, startCol + 2)
                wclrtoeol(screen)
                continue
            }

            let network = networks[networkIndex]
            wmove(screen, row, startCol + 2)

            // Clear the line first
            wclrtoeol(screen)

            // Highlight selected item
            if networkIndex == selectedIndex {
                wattron(screen, ViewUtils.colorPair(3))
                waddstr(screen, "> ")
            } else {
                waddstr(screen, "  ")
            }

            // Network name (truncated if necessary)
            let maxNameWidth = Int(width) - 25 // Leave space for status
            let networkName = network.name
            let truncatedName = networkName.count > maxNameWidth ?
                String(networkName.prefix(maxNameWidth - 3)) + "..." : networkName
            waddstr(screen, truncatedName)

            // Status column
            let statusCol = startCol + Int32(maxNameWidth) + 5
            wmove(screen, row, statusCol)

            if let status = network.status {
                let statusColor: Int32 = status.lowercased() == "active" ? 5 :
                                      (status.lowercased().contains("down") ? 7 : 2)
                wattron(screen, ViewUtils.colorPair(statusColor))
                waddstr(screen, status)
                wattroff(screen, ViewUtils.colorPair(statusColor))
            } else {
                wattron(screen, ViewUtils.colorPair(4))
                waddstr(screen, "Unknown")
                wattroff(screen, ViewUtils.colorPair(4))
            }

            if networkIndex == selectedIndex {
                wattroff(screen, ViewUtils.colorPair(3))
            }
        }

        // Instructions
        wmove(screen, startRow + height - 2, startCol + 2)
        wattron(screen, ViewUtils.colorPair(4))
        wattroff(screen, ViewUtils.colorPair(4))
    }

    @MainActor
    static func drawNetworkDetail(screen: OpaquePointer?, startRow: Int32, startCol: Int32,
                                width: Int32, height: Int32, network: Network) async {
        // Title
        wattron(screen, ViewUtils.colorPair(2))
        wmove(screen, startRow, startCol + 2)
        waddstr(screen, "* Network Details: \(network.name)")
        wattroff(screen, ViewUtils.colorPair(2))

        var currentRow = startRow + 2

        // Basic Information
        wattron(screen, ViewUtils.colorPair(3))
        wmove(screen, currentRow, startCol + 2)
        waddstr(screen, "Basic Information")
        wattroff(screen, ViewUtils.colorPair(3))
        currentRow += 1

        wmove(screen, currentRow, startCol + 4)
        wattron(screen, ViewUtils.colorPair(6))
        waddstr(screen, "ID: \(network.id)")
        wattroff(screen, ViewUtils.colorPair(6))
        currentRow += 1

        wmove(screen, currentRow, startCol + 4)
        wattron(screen, ViewUtils.colorPair(6))
        waddstr(screen, "Name: \(network.name)")
        wattroff(screen, ViewUtils.colorPair(6))
        currentRow += 1

        wmove(screen, currentRow, startCol + 4)
        wattron(screen, ViewUtils.colorPair(6))
        let status = network.status ?? "Unknown"
        let statusColor: Int32 = status.lowercased() == "active" ? 5 :
                              (status.lowercased().contains("down") ? 7 : 2)
        waddstr(screen, "Status: ")
        wattron(screen, ViewUtils.colorPair(statusColor))
        waddstr(screen, status)
        wattroff(screen, ViewUtils.colorPair(statusColor))
        wattroff(screen, ViewUtils.colorPair(6))
        currentRow += 1

        if let adminStateUp = network.adminStateUp {
            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "Admin State: \(adminStateUp ? "UP" : "DOWN")")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1
        }

        currentRow += 1

        // Network Configuration
        wattron(screen, ViewUtils.colorPair(3))
        wmove(screen, currentRow, startCol + 2)
        waddstr(screen, "Configuration")
        wattroff(screen, ViewUtils.colorPair(3))
        currentRow += 1

        if let shared = network.shared {
            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "Shared: \(shared ? "Yes" : "No")")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1
        }

        if let external = network.external {
            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "External: \(external ? "Yes" : "No")")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1
        }

        currentRow += 1

        // Subnets
        if let subnets = network.subnets, !subnets.isEmpty {
            wattron(screen, ViewUtils.colorPair(3))
            wmove(screen, currentRow, startCol + 2)
            waddstr(screen, "Subnets")
            wattroff(screen, ViewUtils.colorPair(3))
            currentRow += 1

            for subnet in subnets {
                wmove(screen, currentRow, startCol + 4)
                wattron(screen, ViewUtils.colorPair(6))
                waddstr(screen, "• \(subnet)")
                wattroff(screen, ViewUtils.colorPair(6))
                currentRow += 1
            }
            currentRow += 1
        }

        // Instructions
        wmove(screen, startRow + height - 2, startCol + 2)
        wattron(screen, ViewUtils.colorPair(4))
        waddstr(screen, "Press ESC to return to network list")
        wattroff(screen, ViewUtils.colorPair(4))
    }
}