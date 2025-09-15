import OTClient
import CNCurses

struct NetworkInterfaceManagementView {
    @MainActor
    static func draw(screen: OpaquePointer?, startRow: Int32, startCol: Int32,
                    width: Int32, height: Int32, form: NetworkInterfaceManagementForm,
                    resourceNameCache: ResourceNameCache) async {

        guard let server = form.selectedServer else {
            wattron(screen, ViewUtils.colorPair(7))
            wmove(screen, startRow + 2, startCol + 2)
            waddstr(screen, "Error: No server selected")
            wattroff(screen, ViewUtils.colorPair(7))
            return
        }

        // Title
        wattron(screen, ViewUtils.colorPair(2))
        wmove(screen, startRow, startCol + 2)
        waddstr(screen, "* Manage Network Interfaces - \(server.name ?? "Unnamed Server")")
        wattroff(screen, ViewUtils.colorPair(2))

        var currentRow = startRow + 2

        // Operation selector
        wattron(screen, ViewUtils.colorPair(3))
        wmove(screen, currentRow, startCol + 2)
        waddstr(screen, "Operation: \(form.selectedOperation.title)")
        wattroff(screen, ViewUtils.colorPair(3))
        currentRow += 2

        // Instructions based on operation
        wmove(screen, currentRow, startCol + 2)
        wattron(screen, ViewUtils.colorPair(4))
        let instruction: String
        switch form.selectedOperation {
        case .view:
            instruction = "Viewing current network interfaces. Press TAB to switch modes."
        case .attach:
            instruction = "Select ports to attach. SPACE to toggle, ENTER to apply changes."
        case .detach:
            instruction = "Select ports to detach. SPACE to toggle, ENTER to apply changes."
        }
        waddstr(screen, instruction)
        wattroff(screen, ViewUtils.colorPair(4))
        currentRow += 2

        // Error message if present
        if let errorMessage = form.errorMessage {
            wattron(screen, ViewUtils.colorPair(7))
            wmove(screen, currentRow, startCol + 2)
            waddstr(screen, "Error: \(errorMessage)")
            wattroff(screen, ViewUtils.colorPair(7))
            currentRow += 2
        }

        // Loading indicator
        if form.isLoading {
            wattron(screen, ViewUtils.colorPair(2))
            wmove(screen, currentRow, startCol + 2)
            waddstr(screen, "Loading network interfaces...")
            wattroff(screen, ViewUtils.colorPair(2))
            return
        }

        // Network interfaces/ports list
        let ports: [Port]
        let listTitle: String

        switch form.selectedOperation {
        case .view:
            // For view, show the current interfaces with port info
            ports = form.serverInterfaces.compactMap { interface in
                form.getPortForInterface(interface)
            }
            listTitle = "Current Network Interfaces:"
        case .attach:
            ports = form.getAvailablePortsForAttach()
            listTitle = "Available Ports:"
        case .detach:
            ports = form.getPortsForDetach()
            listTitle = "Attached Ports:"
        }

        wattron(screen, ViewUtils.colorPair(3))
        wmove(screen, currentRow, startCol + 2)
        waddstr(screen, listTitle)
        wattroff(screen, ViewUtils.colorPair(3))
        currentRow += 1

        // List ports/interfaces
        let maxDisplayRows = Int(height - 15) // Leave space for header, instructions, and footer
        let startIndex = max(0, form.selectedPortIndex - maxDisplayRows + 1)
        let endIndex = min(ports.count, startIndex + maxDisplayRows)

        for i in startIndex..<endIndex {
            let port = ports[i]
            let row = currentRow + Int32(i - startIndex)
            let isSelected = i == form.selectedPortIndex
            let isToggled = form.isPortSelected(port.id)

            wmove(screen, row, startCol + 4)

            // Selection indicator
            if isSelected {
                wattron(screen, ViewUtils.colorPair(2))
                waddstr(screen, "> ")
                wattroff(screen, ViewUtils.colorPair(2))
            } else {
                waddstr(screen, "  ")
            }

            // Toggle indicator for attach/detach modes
            if form.selectedOperation != .view {
                let toggleChar = isToggled ? "[X]" : "[ ]"
                let toggleColor: Int32 = isToggled ? 5 : 6
                wattron(screen, ViewUtils.colorPair(toggleColor))
                waddstr(screen, toggleChar)
                wattroff(screen, ViewUtils.colorPair(toggleColor))
                waddstr(screen, " ")
            }

            // Port name and network info
            let nameColor: Int32 = isSelected ? 2 : 6
            wattron(screen, ViewUtils.colorPair(nameColor))

            // Port name (fallback to ID if no name)
            let portName = port.name ?? port.id
            let displayName = String(portName.prefix(20)) // Limit length
            waddstr(screen, displayName)

            // Network name
            let networkName = resolveNetworkName(port.networkID, cache: resourceNameCache)
            let networkInfo = " (Net: \(String(networkName.prefix(15))))"
            waddstr(screen, networkInfo)

            // IP address info if available
            if let firstIP = port.fixedIPs.first {
                let ipInfo = " IP: \(firstIP.ipAddress)"
                waddstr(screen, ipInfo)
            }

            wattroff(screen, ViewUtils.colorPair(nameColor))

            // Status indicator for current attachment
            if form.selectedOperation == .attach && form.isPortCurrentlyAttached(port.id) {
                wattron(screen, ViewUtils.colorPair(4))
                waddstr(screen, " (already attached)")
                wattroff(screen, ViewUtils.colorPair(4))
            }
        }

        // Scroll indicator
        if ports.count > maxDisplayRows {
            let scrollRow = startRow + height - 5
            wmove(screen, scrollRow, startCol + 2)
            wattron(screen, ViewUtils.colorPair(4))
            waddstr(screen, "(\(form.selectedPortIndex + 1)/\(ports.count)) Use UP/DOWN to scroll")
            wattroff(screen, ViewUtils.colorPair(4))
        }

        // Pending changes summary
        if form.hasPendingChanges() {
            let summaryRow = startRow + height - 4
            wmove(screen, summaryRow, startCol + 2)
            wattron(screen, ViewUtils.colorPair(3))
            waddstr(screen, "Pending: +\(form.pendingAttachments.count) -\(form.pendingDetachments.count)")
            wattroff(screen, ViewUtils.colorPair(3))
        }

        // Footer with controls
        let footerRow = startRow + height - 2
        wmove(screen, footerRow, startCol + 2)
        wattron(screen, ViewUtils.colorPair(4))
        let controls = "TAB: Switch mode | UP/DOWN: Navigate | SPACE: Toggle | ENTER: Apply | ESC: Cancel"
        waddstr(screen, controls)
        wattroff(screen, ViewUtils.colorPair(4))
    }

    @MainActor
    private static func resolveNetworkName(_ id: String, cache: ResourceNameCache) -> String {
        if let name = cache.getNetworkName(id) {
            return name
        }
        return id
    }
}