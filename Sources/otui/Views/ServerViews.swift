import Foundation
import CNCurses
import OTClient

struct ServerViews {
    @MainActor
    static func drawDetailedServerList(screen: OpaquePointer?, startRow: Int32, startCol: Int32,
                                     width: Int32, height: Int32, cachedServers: [Server],
                                     searchQuery: String?, scrollOffset: Int, selectedIndex: Int,
                                     resourceNameCache: ResourceNameCache) async {
        // Title
        wattron(screen, ViewUtils.colorPair(2))
        wmove(screen, startRow, startCol + 2)
        let searchInfo = searchQuery != nil ? " (filtered: \(searchQuery!))" : ""
        waddstr(screen, "* Servers\(searchInfo)")
        wattroff(screen, ViewUtils.colorPair(2))

        // Headers
        wattron(screen, ViewUtils.colorPair(2))
        wmove(screen, startRow + 2, startCol + 2)
        waddstr(screen, "ST NAME                           STATUS     IP ADDRESS      FLAVOR/IMAGE")
        wattroff(screen, ViewUtils.colorPair(2))

        // Content
        let contentHeight = Int(height) - 4
        let filteredServers = FilterUtils.filterServers(cachedServers, query: searchQuery)
        let displayServers = Array(filteredServers.dropFirst(scrollOffset).prefix(contentHeight))

        for (index, server) in displayServers.enumerated() {
            let row = startRow + 3 + Int32(index)
            wmove(screen, row, startCol + 2)

            let absoluteIndex = scrollOffset + index
            let isSelected = (absoluteIndex == selectedIndex)

            // Highlight the entire row if selected
            if isSelected {
                wattron(screen, Int32(262144)) // A_REVERSE equivalent
            }

            // Status indicator
            let statusChar: String
            let statusColor: Int32
            switch server.status?.lowercased() {
            case "active":
                statusChar = "A "
                statusColor = 5
            case "error", "fault":
                statusChar = "E "
                statusColor = 7
            case "build", "building":
                statusChar = "B "
                statusColor = 2
            default:
                statusChar = "O "
                statusColor = 6
            }

            wattron(screen, ViewUtils.colorPair(statusColor))
            waddstr(screen, statusChar)
            wattroff(screen, ViewUtils.colorPair(statusColor))

            let textColor: Int32 = isSelected ? 1 : 6
            wattron(screen, ViewUtils.colorPair(textColor))

            // Name (32 chars)
            let name = String((server.name ?? "Unnamed Server").prefix(30)).padding(toLength: 30, withPad: " ", startingAt: 0)
            waddstr(screen, " \(name)")

            // Status (12 chars)
            let status = String((server.status ?? "unknown").prefix(10)).padding(toLength: 10, withPad: " ", startingAt: 0)
            waddstr(screen, " \(status)")

            // IP Address
            let ip = getServerIP(server) ?? "none"
            let ipDisplay = String(ip.prefix(15)).padding(toLength: 15, withPad: " ", startingAt: 0)
            waddstr(screen, " \(ipDisplay)")

            // Flavor/Image info instead of availability zone
            let remainingWidth = Int(width) - 65
            if remainingWidth > 10 {
                var flavorImageInfo = ""

                // Add flavor name (shortened)
                if let flavor = server.flavor {
                    let flavorName = resolveFlavorName(flavor.id, cache: resourceNameCache)
                    let shortFlavorName = String(flavorName.prefix(8))
                    flavorImageInfo += shortFlavorName
                }

                flavorImageInfo += "/"

                // Add image name (shortened)
                if let image = server.image {
                    let imageName = resolveImageName(image.id, cache: resourceNameCache)
                    let shortImageName = String(imageName.prefix(remainingWidth - flavorImageInfo.count - 1))
                    flavorImageInfo += shortImageName
                }

                let finalInfo = String(flavorImageInfo.prefix(remainingWidth))
                waddstr(screen, " \(finalInfo)")
            }
            wattroff(screen, ViewUtils.colorPair(textColor))

            if isSelected {
                wattroff(screen, Int32(262144)) // A_REVERSE equivalent
            }
        }

        // Scroll indicator
        if filteredServers.count > contentHeight {
            wmove(screen, startRow + Int32(height) - 1, startCol + Int32(width) - 20)
            wattron(screen, ViewUtils.colorPair(4))
            let scrollInfo = "[\(scrollOffset + 1)-\(min(scrollOffset + contentHeight, filteredServers.count))/\(filteredServers.count)]"
            waddstr(screen, scrollInfo)
            wattroff(screen, ViewUtils.colorPair(4))
        }
    }

    @MainActor
    static func drawServerDetail(screen: OpaquePointer?, startRow: Int32, startCol: Int32,
                               width: Int32, height: Int32, server: Server,
                               client: OTClient, resourceNameCache: ResourceNameCache) async {
        // Title
        wattron(screen, ViewUtils.colorPair(2))
        wmove(screen, startRow, startCol + 2)
        waddstr(screen, "* Server Details: \(server.name ?? "Unnamed Server")")
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
        waddstr(screen, "ID: \(server.id)")
        wattroff(screen, ViewUtils.colorPair(6))
        currentRow += 1

        wmove(screen, currentRow, startCol + 4)
        wattron(screen, ViewUtils.colorPair(6))
        let status = server.status ?? "Unknown"
        let statusColor: Int32 = status.lowercased() == "active" ? 5 : (status.lowercased().contains("error") ? 7 : 2)
        waddstr(screen, "Status: ")
        wattron(screen, ViewUtils.colorPair(statusColor))
        waddstr(screen, status)
        wattroff(screen, ViewUtils.colorPair(statusColor))
        wattroff(screen, ViewUtils.colorPair(6))
        currentRow += 1

        if let zone = server.availabilityZone {
            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "Availability Zone: \(zone)")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1
        }

        if let keyName = server.keyName {
            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "Key Pair: \(keyName)")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1
        }

        currentRow += 1

        // Flavor Information
        if let flavor = server.flavor {
            wattron(screen, ViewUtils.colorPair(3))
            wmove(screen, currentRow, startCol + 2)
            waddstr(screen, "Flavor")
            wattroff(screen, ViewUtils.colorPair(3))
            currentRow += 1

            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "ID: \(flavor.id)")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1

            // Always try to get complete flavor information for consistency
            let resolvedFlavor = await resolveFlavor(flavor.id, client: client, resourceNameCache: resourceNameCache)
            let flavorName: String

            if let resolved = resolvedFlavor {
                flavorName = resolved.name
            } else if let name = flavor.name {
                flavorName = name
            } else {
                flavorName = await resolveFlavorNameAsync(flavor.id, client: client, resourceNameCache: resourceNameCache)
            }

            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "Name: \(flavorName)")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1

            // Show flavor specs if available
            if let resolved = resolvedFlavor {
                if let vcpus = resolved.vcpus {
                    wmove(screen, currentRow, startCol + 4)
                    wattron(screen, ViewUtils.colorPair(6))
                    waddstr(screen, "vCPUs: \(vcpus)")
                    wattroff(screen, ViewUtils.colorPair(6))
                    currentRow += 1
                }

                if let ram = resolved.ram {
                    wmove(screen, currentRow, startCol + 4)
                    wattron(screen, ViewUtils.colorPair(6))
                    waddstr(screen, "RAM: \(ram) MB")
                    wattroff(screen, ViewUtils.colorPair(6))
                    currentRow += 1
                }

                if let disk = resolved.disk {
                    wmove(screen, currentRow, startCol + 4)
                    wattron(screen, ViewUtils.colorPair(6))
                    waddstr(screen, "Disk: \(disk) GB")
                    wattroff(screen, ViewUtils.colorPair(6))
                    currentRow += 1
                }
            } else {
                // If we couldn't resolve the flavor details, show a message
                wmove(screen, currentRow, startCol + 4)
                wattron(screen, ViewUtils.colorPair(4))
                waddstr(screen, "Flavor details not available")
                wattroff(screen, ViewUtils.colorPair(4))
                currentRow += 1
            }

            currentRow += 1
        }

        // Image Information
        if let image = server.image {
            wattron(screen, ViewUtils.colorPair(3))
            wmove(screen, currentRow, startCol + 2)
            waddstr(screen, "Image")
            wattroff(screen, ViewUtils.colorPair(3))
            currentRow += 1

            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "ID: \(image.id)")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1

            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            // Always try to use async resolution for consistency
            let imageName = await resolveImageNameAsync(image.id, client: client, resourceNameCache: resourceNameCache)
            waddstr(screen, "Name: \(imageName)")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1
            currentRow += 1
        }

        // Network Addresses
        if let addresses = server.addresses, !addresses.isEmpty {
            wattron(screen, ViewUtils.colorPair(3))
            wmove(screen, currentRow, startCol + 2)
            waddstr(screen, "Network Addresses")
            wattroff(screen, ViewUtils.colorPair(3))
            currentRow += 1

            for (network, addressList) in addresses {
                wmove(screen, currentRow, startCol + 4)
                wattron(screen, ViewUtils.colorPair(6))

                // Try to resolve network name if network looks like a UUID
                let displayName = network.contains("-") && network.count == 36
                    ? resolveNetworkName(network, cache: resourceNameCache)
                    : network

                waddstr(screen, "\(displayName):")
                wattroff(screen, ViewUtils.colorPair(6))
                currentRow += 1

                for address in addressList {
                    wmove(screen, currentRow, startCol + 6)
                    wattron(screen, ViewUtils.colorPair(6))
                    let typeInfo = address.type != nil ? " (\(address.type!))" : ""
                    waddstr(screen, "IPv\(address.version): \(address.addr)\(typeInfo)")
                    wattroff(screen, ViewUtils.colorPair(6))
                    currentRow += 1
                }
            }
            currentRow += 1
        }

        // Timestamps
        if server.created != nil || server.updated != nil {
            wattron(screen, ViewUtils.colorPair(3))
            wmove(screen, currentRow, startCol + 2)
            waddstr(screen, "Timestamps")
            wattroff(screen, ViewUtils.colorPair(3))
            currentRow += 1

            if let created = server.created {
                wmove(screen, currentRow, startCol + 4)
                wattron(screen, ViewUtils.colorPair(6))
                waddstr(screen, "Created: \(created)")
                wattroff(screen, ViewUtils.colorPair(6))
                currentRow += 1
            }

            if let updated = server.updated {
                wmove(screen, currentRow, startCol + 4)
                wattron(screen, ViewUtils.colorPair(6))
                waddstr(screen, "Updated: \(updated)")
                wattroff(screen, ViewUtils.colorPair(6))
                currentRow += 1
            }
            currentRow += 1
        }

        // Instructions
        wmove(screen, startRow + height - 2, startCol + 2)
        wattron(screen, ViewUtils.colorPair(4))
        waddstr(screen, "Press ESC to return to server list")
        wattroff(screen, ViewUtils.colorPair(4))
    }

    // Helper functions
    private static func getServerIP(_ server: Server) -> String? {
        guard let addresses = server.addresses else { return nil }
        for (_, addressList) in addresses {
            for address in addressList {
                if address.version == 4 {
                    return address.addr
                }
            }
        }
        return nil
    }

    @MainActor
    private static func resolveFlavorName(_ id: String, cache: ResourceNameCache) -> String {
        if let name = cache.getFlavorName(id) {
            return name
        }
        return id
    }

    @MainActor
    private static func resolveFlavorNameAsync(_ id: String, client: OTClient, resourceNameCache: ResourceNameCache) async -> String {
        // First check cache
        if let name = resourceNameCache.getFlavorName(id) {
            return name
        }

        // If not in cache, try to fetch flavor details
        do {
            let flavor = try await client.getFlavor(id: id)
            // Cache the result for future use
            resourceNameCache.setFlavorName(flavor.id, name: flavor.name)
            return flavor.name
        } catch {
            // If fetch fails, return the UUID as fallback
            return id
        }
    }

    @MainActor
    private static func resolveFlavor(_ id: String, client: OTClient, resourceNameCache: ResourceNameCache) async -> Flavor? {
        // If not in cache, try to fetch flavor details
        do {
            let flavor = try await client.getFlavor(id: id)
            // Cache the result for future use
            resourceNameCache.setFlavorName(flavor.id, name: flavor.name)
            return flavor
        } catch {
            // If fetch fails, return nil
            return nil
        }
    }

    @MainActor
    private static func resolveImageName(_ id: String, cache: ResourceNameCache) -> String {
        if let name = cache.getImageName(id) {
            return name
        }
        return id
    }

    @MainActor
    private static func resolveImageNameAsync(_ id: String, client: OTClient, resourceNameCache: ResourceNameCache) async -> String {
        // First check cache
        if let name = resourceNameCache.getImageName(id) {
            return name
        }

        // If not in cache, try to fetch image details
        do {
            let image = try await client.getImage(id: id)
            // Cache the result for future use
            if let name = image.name {
                resourceNameCache.setImageName(image.id, name: name)
                return name
            }
            return id
        } catch {
            // If fetch fails, return the UUID as fallback
            return id
        }
    }

    @MainActor
    private static func resolveNetworkName(_ id: String, cache: ResourceNameCache) -> String {
        if let name = cache.getNetworkName(id) {
            return name
        }
        return id
    }
}