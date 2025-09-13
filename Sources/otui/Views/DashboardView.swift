import Foundation
import CNCurses
import OTClient

struct DashboardView {
    @MainActor
    static func draw(screen: OpaquePointer?, startRow: Int32, startCol: Int32, width: Int32, height: Int32,
                    resourceCounts: ResourceCounts, cachedServers: [Server], cachedNetworks: [Network],
                    cachedVolumes: [Volume], cachedComputeLimits: ComputeLimits?,
                    cachedNetworkQuotas: NetworkQuotas?, cachedVolumeQuotas: VolumeQuotas?) async {

        // Dashboard title
        wattron(screen, ViewUtils.colorPair(2))
        wmove(screen, startRow, startCol + 2)
        waddstr(screen, "* OpenStack Dashboard")
        wattroff(screen, ViewUtils.colorPair(2))

        let panelWidth = width / 3 - 2
        let panelHeight = height / 2 - 1

        // Top row - 3 panels
        // Top-left: Server Status Panel
        await drawDashboardPanel(screen: screen,
                          title: "Server Status",
                          startRow: startRow + 2,
                          startCol: startCol + 1,
                          width: panelWidth,
                          height: panelHeight) {
            await drawServerStatusPanel(screen: screen, startRow: startRow + 4, startCol: startCol + 3,
                                       width: panelWidth - 4, cachedServers: cachedServers)
        }

        // Top-center: Volume Status Panel
        await drawDashboardPanel(screen: screen,
                          title: "Volume Status",
                          startRow: startRow + 2,
                          startCol: startCol + panelWidth + 3,
                          width: panelWidth,
                          height: panelHeight) {
            await drawVolumeStatusPanel(screen: screen, startRow: startRow + 4,
                                       startCol: startCol + panelWidth + 5, width: panelWidth - 4,
                                       cachedVolumes: cachedVolumes)
        }

        // Top-right: Resource Utilization
        await drawDashboardPanel(screen: screen,
                          title: "Resource Overview",
                          startRow: startRow + 2,
                          startCol: startCol + (panelWidth + 3) * 2,
                          width: panelWidth,
                          height: panelHeight) {
            await drawResourceUtilizationPanel(screen: screen, startRow: startRow + 4,
                                             startCol: startCol + (panelWidth + 3) * 2 + 2, width: panelWidth - 4,
                                             resourceCounts: resourceCounts)
        }

        // Bottom row - 2 panels (wider)
        let bottomPanelWidth = width / 2 - 2

        // Bottom-left: Project Quotas
        await drawDashboardPanel(screen: screen,
                          title: "Project Quotas",
                          startRow: startRow + panelHeight + 4,
                          startCol: startCol + 1,
                          width: bottomPanelWidth,
                          height: panelHeight) {
            await drawProjectQuotasPanel(screen: screen, startRow: startRow + panelHeight + 6,
                                        startCol: startCol + 3, width: bottomPanelWidth - 4,
                                        cachedVolumes: cachedVolumes, cachedNetworks: cachedNetworks,
                                        cachedComputeLimits: cachedComputeLimits,
                                        cachedNetworkQuotas: cachedNetworkQuotas,
                                        cachedVolumeQuotas: cachedVolumeQuotas)
        }

        // Bottom-right: Network Overview
        await drawDashboardPanel(screen: screen,
                          title: "Network Status",
                          startRow: startRow + panelHeight + 4,
                          startCol: startCol + bottomPanelWidth + 3,
                          width: bottomPanelWidth,
                          height: panelHeight) {
            await drawNetworkStatusPanel(screen: screen, startRow: startRow + panelHeight + 6,
                                        startCol: startCol + bottomPanelWidth + 5, width: bottomPanelWidth - 4,
                                        cachedNetworks: cachedNetworks)
        }
    }

    @MainActor
    private static func drawDashboardPanel(screen: OpaquePointer?, title: String, startRow: Int32, startCol: Int32,
                                          width: Int32, height: Int32, content: () async -> Void) async {
        // Draw panel border
        wattron(screen, ViewUtils.colorPair(8))

        // Top border
        wmove(screen, startRow, startCol)
        waddch(screen, UInt32("+".utf8.first ?? 43))
        for _ in 1..<width-1 {
            waddch(screen, UInt32("-".utf8.first ?? 45))
        }
        waddch(screen, UInt32("+".utf8.first ?? 43))

        // Side borders
        for row in 1..<height-1 {
            wmove(screen, startRow + row, startCol)
            waddch(screen, UInt32("|".utf8.first ?? 124))
            wmove(screen, startRow + row, startCol + width - 1)
            waddch(screen, UInt32("|".utf8.first ?? 124))
        }

        // Bottom border
        wmove(screen, startRow + height - 1, startCol)
        waddch(screen, UInt32("+".utf8.first ?? 43))
        for _ in 1..<width-1 {
            waddch(screen, UInt32("-".utf8.first ?? 45))
        }
        waddch(screen, UInt32("+".utf8.first ?? 43))

        wattroff(screen, ViewUtils.colorPair(8))

        // Panel title
        wattron(screen, ViewUtils.colorPair(2))
        wmove(screen, startRow, startCol + 2)
        waddstr(screen, "[ \(title) ]")
        wattroff(screen, ViewUtils.colorPair(2))

        // Panel content
        await content()
    }

    @MainActor
    private static func drawServerStatusPanel(screen: OpaquePointer?, startRow: Int32, startCol: Int32,
                                            width: Int32, cachedServers: [Server]) async {
        let maxRows = 8
        let displayServers = Array(cachedServers.prefix(maxRows))

        for (index, server) in displayServers.enumerated() {
            let row = startRow + Int32(index)
            wmove(screen, row, startCol)

            // Status indicator
            let statusChar: String
            let statusColor: Int32
            switch server.status?.lowercased() {
            case "active":
                statusChar = "*"
                statusColor = 5 // Green
            case "error", "fault":
                statusChar = "X"
                statusColor = 7 // Red
            case "build", "building":
                statusChar = "+"
                statusColor = 2 // Yellow
            default:
                statusChar = "o"
                statusColor = 6 // White
            }

            wattron(screen, ViewUtils.colorPair(statusColor))
            waddstr(screen, statusChar)
            wattroff(screen, ViewUtils.colorPair(statusColor))

            // Server name (truncated)
            wattron(screen, ViewUtils.colorPair(6))
            let nameWidth = Int(width) - 15
            let displayName = String((server.name ?? "Unnamed Server").prefix(nameWidth)).padding(toLength: nameWidth, withPad: " ", startingAt: 0)
            waddstr(screen, " \(displayName)")

            // Status text
            let status = server.status ?? "unknown"
            waddstr(screen, " \(status)")
            wattroff(screen, ViewUtils.colorPair(6))
        }

        if cachedServers.count > maxRows {
            wmove(screen, startRow + Int32(maxRows), startCol)
            wattron(screen, ViewUtils.colorPair(4))
            waddstr(screen, "... and \(cachedServers.count - maxRows) more")
            wattroff(screen, ViewUtils.colorPair(4))
        }
    }

    @MainActor
    private static func drawResourceUtilizationPanel(screen: OpaquePointer?, startRow: Int32, startCol: Int32,
                                                   width: Int32, resourceCounts: ResourceCounts) async {
        wattron(screen, ViewUtils.colorPair(6))

        wmove(screen, startRow, startCol)
        waddstr(screen, "Total Resources:")

        wmove(screen, startRow + 2, startCol)
        waddstr(screen, "Servers:     \(resourceCounts.servers)")
        wmove(screen, startRow + 3, startCol)
        waddstr(screen, "Networks:    \(resourceCounts.networks)")
        wmove(screen, startRow + 4, startCol)
        waddstr(screen, "Volumes:     \(resourceCounts.volumes)")
        wmove(screen, startRow + 5, startCol)
        waddstr(screen, "Images:      \(resourceCounts.images)")

        wmove(screen, startRow + 7, startCol)
        waddstr(screen, "Server Health:")
        wmove(screen, startRow + 8, startCol)

        let total = resourceCounts.servers
        let active = resourceCounts.activeServers

        if total > 0 {
            let healthPercent = (active * 100) / total
            wattron(screen, healthPercent >= 80 ? ViewUtils.colorPair(5) : healthPercent >= 50 ? ViewUtils.colorPair(2) : ViewUtils.colorPair(7))
            waddstr(screen, "\(healthPercent)% Healthy")
            wattroff(screen, healthPercent >= 80 ? ViewUtils.colorPair(5) : healthPercent >= 50 ? ViewUtils.colorPair(2) : ViewUtils.colorPair(7))
        } else {
            waddstr(screen, "No servers")
        }

        wattroff(screen, ViewUtils.colorPair(6))
    }

    @MainActor
    private static func drawProjectQuotasPanel(screen: OpaquePointer?, startRow: Int32, startCol: Int32,
                                             width: Int32, cachedVolumes: [Volume], cachedNetworks: [Network],
                                             cachedComputeLimits: ComputeLimits?, cachedNetworkQuotas: NetworkQuotas?,
                                             cachedVolumeQuotas: VolumeQuotas?) async {
        var currentRow = startRow

        // Compute quotas
        if let computeLimits = cachedComputeLimits?.absolute {
            wattron(screen, ViewUtils.colorPair(3))
            wmove(screen, currentRow, startCol)
            waddstr(screen, "Compute Resources:")
            wattroff(screen, ViewUtils.colorPair(3))
            currentRow += 1

            // Instances
            if let used = computeLimits.totalInstancesUsed, let limit = computeLimits.maxTotalInstances {
                wmove(screen, currentRow, startCol)
                wattron(screen, ViewUtils.colorPair(6))
                let percentage = limit > 0 ? (used * 100) / limit : 0
                let color: Int32 = percentage > 80 ? 7 : (percentage > 60 ? 2 : 5)
                waddstr(screen, "  Instances: \(used)/\(limit) ")
                wattron(screen, ViewUtils.colorPair(color))
                waddstr(screen, "(\(percentage)%)")
                wattroff(screen, ViewUtils.colorPair(color))
                wattroff(screen, ViewUtils.colorPair(6))
                currentRow += 1
            }

            // Cores
            if let used = computeLimits.totalCoresUsed, let limit = computeLimits.maxTotalCores {
                wmove(screen, currentRow, startCol)
                wattron(screen, ViewUtils.colorPair(6))
                let percentage = limit > 0 ? (used * 100) / limit : 0
                let color: Int32 = percentage > 80 ? 7 : (percentage > 60 ? 2 : 5)
                waddstr(screen, "  Cores: \(used)/\(limit) ")
                wattron(screen, ViewUtils.colorPair(color))
                waddstr(screen, "(\(percentage)%)")
                wattroff(screen, ViewUtils.colorPair(color))
                wattroff(screen, ViewUtils.colorPair(6))
                currentRow += 1
            }

            // RAM (convert from MB to GB for display)
            if let used = computeLimits.totalRAMUsed, let limit = computeLimits.maxTotalRAMSize {
                wmove(screen, currentRow, startCol)
                wattron(screen, ViewUtils.colorPair(6))
                let usedGB = used / 1024
                let limitGB = limit / 1024
                let percentage = limit > 0 ? (used * 100) / limit : 0
                let color: Int32 = percentage > 80 ? 7 : (percentage > 60 ? 2 : 5)
                waddstr(screen, "  RAM: \(usedGB)/\(limitGB) GB ")
                wattron(screen, ViewUtils.colorPair(color))
                waddstr(screen, "(\(percentage)%)")
                wattroff(screen, ViewUtils.colorPair(color))
                wattroff(screen, ViewUtils.colorPair(6))
                currentRow += 1
            }

            currentRow += 1
        }

        // Network quotas
        if let networkQuotas = cachedNetworkQuotas {
            wattron(screen, ViewUtils.colorPair(3))
            wmove(screen, currentRow, startCol)
            waddstr(screen, "Network Quotas:")
            wattroff(screen, ViewUtils.colorPair(3))
            currentRow += 1

            if let networks = networkQuotas.network {
                wmove(screen, currentRow, startCol)
                wattron(screen, ViewUtils.colorPair(6))
                waddstr(screen, "  Networks: \(cachedNetworks.count)/\(networks)")
                wattroff(screen, ViewUtils.colorPair(6))
                currentRow += 1
            }

            if let routers = networkQuotas.router {
                wmove(screen, currentRow, startCol)
                wattron(screen, ViewUtils.colorPair(6))
                waddstr(screen, "  Routers: 0/\(routers)")
                wattroff(screen, ViewUtils.colorPair(6))
                currentRow += 1
            }

            currentRow += 1
        }

        // Volume quotas
        if let volumeQuotas = cachedVolumeQuotas {
            wattron(screen, ViewUtils.colorPair(3))
            wmove(screen, currentRow, startCol)
            waddstr(screen, "Storage Quotas:")
            wattroff(screen, ViewUtils.colorPair(3))
            currentRow += 1

            if let volumes = volumeQuotas.volumes {
                wmove(screen, currentRow, startCol)
                wattron(screen, ViewUtils.colorPair(6))
                waddstr(screen, "  Volumes: \(cachedVolumes.count)/\(volumes)")
                wattroff(screen, ViewUtils.colorPair(6))
                currentRow += 1
            }

            if let gigabytes = volumeQuotas.gigabytes {
                let usedGB = cachedVolumes.reduce(0) { $0 + ($1.size ?? 0) }
                wmove(screen, currentRow, startCol)
                wattron(screen, ViewUtils.colorPair(6))
                let percentage = gigabytes > 0 ? (usedGB * 100) / gigabytes : 0
                let color: Int32 = percentage > 80 ? 7 : (percentage > 60 ? 2 : 5)
                waddstr(screen, "  Storage: \(usedGB)/\(gigabytes) GB ")
                wattron(screen, ViewUtils.colorPair(color))
                waddstr(screen, "(\(percentage)%)")
                wattroff(screen, ViewUtils.colorPair(color))
                wattroff(screen, ViewUtils.colorPair(6))
                currentRow += 1
            }
        }

        // Show quota refresh status
        if cachedComputeLimits == nil && cachedNetworkQuotas == nil && cachedVolumeQuotas == nil {
            wmove(screen, startRow, startCol)
            wattron(screen, ViewUtils.colorPair(4))
            waddstr(screen, "Loading quotas...")
            wattroff(screen, ViewUtils.colorPair(4))
        }
    }

    @MainActor
    private static func drawNetworkStatusPanel(screen: OpaquePointer?, startRow: Int32, startCol: Int32,
                                             width: Int32, cachedNetworks: [Network]) async {
        let maxRows = 8
        let displayNetworks = Array(cachedNetworks.prefix(maxRows))

        for (index, network) in displayNetworks.enumerated() {
            let row = startRow + Int32(index)
            wmove(screen, row, startCol)

            // Status indicator
            let statusChar: String
            let statusColor: Int32
            if network.adminStateUp == true {
                statusChar = "*"
                statusColor = 5 // Green
            } else {
                statusChar = "X"
                statusColor = 7 // Red
            }

            wattron(screen, ViewUtils.colorPair(statusColor))
            waddstr(screen, statusChar)
            wattroff(screen, ViewUtils.colorPair(statusColor))

            // Network name (truncated)
            wattron(screen, ViewUtils.colorPair(6))
            let nameWidth = Int(width) - 8
            let displayName = String(network.name.prefix(nameWidth)).padding(toLength: nameWidth, withPad: " ", startingAt: 0)
            waddstr(screen, " \(displayName)")

            // External indicator
            if network.external == true {
                wattron(screen, ViewUtils.colorPair(2))
                waddstr(screen, " [EXT]")
                wattroff(screen, ViewUtils.colorPair(2))
                wattron(screen, ViewUtils.colorPair(6))
            }
            wattroff(screen, ViewUtils.colorPair(6))
        }

        if cachedNetworks.count > maxRows {
            wmove(screen, startRow + Int32(maxRows), startCol)
            wattron(screen, ViewUtils.colorPair(4))
            waddstr(screen, "... and \(cachedNetworks.count - maxRows) more")
            wattroff(screen, ViewUtils.colorPair(4))
        }
    }

    @MainActor
    private static func drawVolumeStatusPanel(screen: OpaquePointer?, startRow: Int32, startCol: Int32,
                                            width: Int32, cachedVolumes: [Volume]) async {
        let maxRows = 8
        let displayVolumes = Array(cachedVolumes.prefix(maxRows))

        for (index, volume) in displayVolumes.enumerated() {
            let row = startRow + Int32(index)
            wmove(screen, row, startCol)

            // Status indicator
            let statusChar: String
            let statusColor: Int32
            switch volume.status?.lowercased() {
            case "available":
                statusChar = "*"
                statusColor = 5 // Green
            case "in-use":
                statusChar = "+"
                statusColor = 2 // Yellow
            case "error", "error_deleting":
                statusChar = "X"
                statusColor = 7 // Red
            case "creating", "attaching", "detaching":
                statusChar = "~"
                statusColor = 4 // Blue
            default:
                statusChar = "o"
                statusColor = 6 // White
            }

            wattron(screen, ViewUtils.colorPair(statusColor))
            waddstr(screen, statusChar)
            wattroff(screen, ViewUtils.colorPair(statusColor))

            // Volume name (truncated)
            wattron(screen, ViewUtils.colorPair(6))
            let nameWidth = Int(width) - 18
            let displayName = String((volume.name ?? "Unnamed Volume").prefix(nameWidth)).padding(toLength: nameWidth, withPad: " ", startingAt: 0)
            waddstr(screen, " \(displayName)")

            // Size indicator
            if let size = volume.size {
                wattron(screen, ViewUtils.colorPair(3))
                waddstr(screen, " \(size)GB")
                wattroff(screen, ViewUtils.colorPair(3))
                wattron(screen, ViewUtils.colorPair(6))
            }

            // Attachment status
            if !volume.attachments.isEmpty {
                wattron(screen, ViewUtils.colorPair(2))
                waddstr(screen, " [ATT]")
                wattroff(screen, ViewUtils.colorPair(2))
                wattron(screen, ViewUtils.colorPair(6))
            }

            wattroff(screen, ViewUtils.colorPair(6))
        }

        if cachedVolumes.count > maxRows {
            wmove(screen, startRow + Int32(maxRows), startCol)
            wattron(screen, ViewUtils.colorPair(4))
            waddstr(screen, "... and \(cachedVolumes.count - maxRows) more")
            wattroff(screen, ViewUtils.colorPair(4))
        }

        // Summary line
        if !cachedVolumes.isEmpty {
            wmove(screen, startRow + Int32(min(maxRows + 1, 9)), startCol)
            wattron(screen, ViewUtils.colorPair(4))

            let totalSize = cachedVolumes.reduce(0) { $0 + ($1.size ?? 0) }
            let attachedCount = cachedVolumes.filter { !$0.attachments.isEmpty }.count
            let availableCount = cachedVolumes.filter { $0.status?.lowercased() == "available" }.count

            waddstr(screen, "Total: \(totalSize)GB, Attached: \(attachedCount), Free: \(availableCount)")
            wattroff(screen, ViewUtils.colorPair(4))
        }
    }
}