import Foundation
import CNCurses
import OTClient

struct FlavorViews {
    @MainActor
    static func drawDetailedFlavorList(screen: OpaquePointer?, startRow: Int32, startCol: Int32,
                                     width: Int32, height: Int32, cachedFlavors: [Flavor],
                                     searchQuery: String?, scrollOffset: Int, selectedIndex: Int) async {
        wattron(screen, ViewUtils.colorPair(2))
        wmove(screen, startRow, startCol + 2)
        let searchInfo = searchQuery != nil ? " (filtered: \(searchQuery!))" : ""
        waddstr(screen, "* Flavors\(searchInfo)")
        wattroff(screen, ViewUtils.colorPair(2))

        let flavors = FilterUtils.filterFlavors(cachedFlavors, query: searchQuery)
        let visibleHeight = Int(height) - 4

        for i in 0..<visibleHeight {
            let flavorIndex = scrollOffset + i
            let row = startRow + Int32(i) + 2

            if flavorIndex >= flavors.count {
                wmove(screen, row, startCol + 2)
                wclrtoeol(screen)
                continue
            }

            let flavor = flavors[flavorIndex]
            wmove(screen, row, startCol + 2)
            wclrtoeol(screen)

            if flavorIndex == selectedIndex {
                wattron(screen, ViewUtils.colorPair(3))
                waddstr(screen, "> ")
            } else {
                waddstr(screen, "  ")
            }

            let maxNameWidth = Int(width) - 40
            let flavorName = flavor.name
            let truncatedName = flavorName.count > maxNameWidth ?
                String(flavorName.prefix(maxNameWidth - 3)) + "..." : flavorName
            waddstr(screen, truncatedName)

            // Specs columns
            let specsCol = startCol + Int32(maxNameWidth) + 5
            wmove(screen, row, specsCol)

            var specs = ""
            if let vcpus = flavor.vcpus {
                specs += "\(vcpus)vCPU "
            }
            if let ram = flavor.ram {
                specs += "\(ram)MB "
            }
            if let disk = flavor.disk {
                specs += "\(disk)GB"
            }

            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, specs)
            wattroff(screen, ViewUtils.colorPair(6))

            if flavorIndex == selectedIndex {
                wattroff(screen, ViewUtils.colorPair(3))
            }
        }

        wmove(screen, startRow + height - 2, startCol + 2)
        wattron(screen, ViewUtils.colorPair(4))
        wattroff(screen, ViewUtils.colorPair(4))
    }

    @MainActor
    static func drawFlavorDetail(screen: OpaquePointer?, startRow: Int32, startCol: Int32,
                                width: Int32, height: Int32, flavor: Flavor) async {
        wattron(screen, ViewUtils.colorPair(2))
        wmove(screen, startRow, startCol + 2)
        waddstr(screen, "* Flavor Details: \(flavor.name)")
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
        waddstr(screen, "ID: \(flavor.id)")
        wattroff(screen, ViewUtils.colorPair(6))
        currentRow += 1

        wmove(screen, currentRow, startCol + 4)
        wattron(screen, ViewUtils.colorPair(6))
        waddstr(screen, "Name: \(flavor.name)")
        wattroff(screen, ViewUtils.colorPair(6))
        currentRow += 1

        currentRow += 1

        // Resource Specifications
        wattron(screen, ViewUtils.colorPair(3))
        wmove(screen, currentRow, startCol + 2)
        waddstr(screen, "Resource Specifications")
        wattroff(screen, ViewUtils.colorPair(3))
        currentRow += 1

        if let vcpus = flavor.vcpus {
            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "vCPUs: \(vcpus)")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1
        }

        if let ram = flavor.ram {
            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "RAM: \(ram) MB")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1
        }

        if let disk = flavor.disk {
            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "Root Disk: \(disk) GB")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1
        }

        if let ephemeral = flavor.ephemeral, ephemeral > 0 {
            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "Ephemeral Disk: \(ephemeral) GB")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1
        }

        if let swap = flavor.swap, !swap.isEmpty && swap != "0" {
            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "Swap: \(swap) MB")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1
        }

        currentRow += 1

        // Access Configuration
        wattron(screen, ViewUtils.colorPair(3))
        wmove(screen, currentRow, startCol + 2)
        waddstr(screen, "Access Configuration")
        wattroff(screen, ViewUtils.colorPair(3))
        currentRow += 1

        if let isPublic = flavor.isPublic {
            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "Public: \(isPublic ? "Yes" : "No")")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1
        }

        if let disabled = flavor.disabled {
            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "Disabled: \(disabled ? "Yes" : "No")")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1
        }

        currentRow += 1

        wmove(screen, startRow + height - 2, startCol + 2)
        wattron(screen, ViewUtils.colorPair(4))
        waddstr(screen, "Press ESC to return to flavor list")
        wattroff(screen, ViewUtils.colorPair(4))
    }
}