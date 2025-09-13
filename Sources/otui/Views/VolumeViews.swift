import Foundation
import CNCurses
import OTClient

struct VolumeViews {
    @MainActor
    static func drawDetailedVolumeList(screen: OpaquePointer?, startRow: Int32, startCol: Int32,
                                     width: Int32, height: Int32, cachedVolumes: [Volume],
                                     searchQuery: String?, scrollOffset: Int, selectedIndex: Int) async {
        wattron(screen, ViewUtils.colorPair(2))
        wmove(screen, startRow, startCol + 2)
        let searchInfo = searchQuery != nil ? " (filtered: \(searchQuery!))" : ""
        waddstr(screen, "* Volumes\(searchInfo)")
        wattroff(screen, ViewUtils.colorPair(2))

        let volumes = FilterUtils.filterVolumes(cachedVolumes, query: searchQuery)
        let visibleHeight = Int(height) - 4

        for i in 0..<visibleHeight {
            let volumeIndex = scrollOffset + i
            let row = startRow + Int32(i) + 2

            if volumeIndex >= volumes.count {
                wmove(screen, row, startCol + 2)
                wclrtoeol(screen)
                continue
            }

            let volume = volumes[volumeIndex]
            wmove(screen, row, startCol + 2)
            wclrtoeol(screen)

            if volumeIndex == selectedIndex {
                wattron(screen, ViewUtils.colorPair(3))
                waddstr(screen, "> ")
            } else {
                waddstr(screen, "  ")
            }

            let maxNameWidth = Int(width) - 30
            let volumeName = volume.name ?? "Unnamed Volume"
            let truncatedName = volumeName.count > maxNameWidth ?
                String(volumeName.prefix(maxNameWidth - 3)) + "..." : volumeName
            waddstr(screen, truncatedName)

            // Size column
            let sizeCol = startCol + Int32(maxNameWidth) + 5
            wmove(screen, row, sizeCol)
            if let size = volume.size {
                waddstr(screen, "\(size)GB")
            }

            // Status column
            let statusCol = sizeCol + 8
            wmove(screen, row, statusCol)
            if let status = volume.status {
                let statusColor: Int32 = status.lowercased() == "available" ? 5 :
                                      (status.lowercased().contains("error") ? 7 : 2)
                wattron(screen, ViewUtils.colorPair(statusColor))
                waddstr(screen, status)
                wattroff(screen, ViewUtils.colorPair(statusColor))
            } else {
                wattron(screen, ViewUtils.colorPair(4))
                waddstr(screen, "Unknown")
                wattroff(screen, ViewUtils.colorPair(4))
            }

            if volumeIndex == selectedIndex {
                wattroff(screen, ViewUtils.colorPair(3))
            }
        }

        wmove(screen, startRow + height - 2, startCol + 2)
        wattron(screen, ViewUtils.colorPair(4))
        wattroff(screen, ViewUtils.colorPair(4))
    }

    @MainActor
    static func drawVolumeDetail(screen: OpaquePointer?, startRow: Int32, startCol: Int32,
                               width: Int32, height: Int32, volume: Volume) async {
        wattron(screen, ViewUtils.colorPair(2))
        wmove(screen, startRow, startCol + 2)
        waddstr(screen, "* Volume Details: \(volume.name ?? "Unnamed Volume")")
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
        waddstr(screen, "ID: \(volume.id)")
        wattroff(screen, ViewUtils.colorPair(6))
        currentRow += 1

        if let name = volume.name {
            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "Name: \(name)")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1
        }

        wmove(screen, currentRow, startCol + 4)
        wattron(screen, ViewUtils.colorPair(6))
        let status = volume.status ?? "Unknown"
        let statusColor: Int32 = status.lowercased() == "available" ? 5 :
                              (status.lowercased().contains("error") ? 7 : 2)
        waddstr(screen, "Status: ")
        wattron(screen, ViewUtils.colorPair(statusColor))
        waddstr(screen, status)
        wattroff(screen, ViewUtils.colorPair(statusColor))
        wattroff(screen, ViewUtils.colorPair(6))
        currentRow += 1

        currentRow += 1

        // Storage Information
        wattron(screen, ViewUtils.colorPair(3))
        wmove(screen, currentRow, startCol + 2)
        waddstr(screen, "Storage Information")
        wattroff(screen, ViewUtils.colorPair(3))
        currentRow += 1

        if let size = volume.size {
            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "Size: \(size) GB")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1
        }

        if let volumeType = volume.volumeType {
            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "Type: \(volumeType)")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1
        }

        if let bootable = volume.bootable {
            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "Bootable: \(bootable == "true" ? "Yes" : "No")")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1
        }

        if let encrypted = volume.encrypted {
            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "Encrypted: \(encrypted ? "Yes" : "No")")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1
        }

        currentRow += 1

        // Attachment Information
        if !volume.attachments.isEmpty {
            wattron(screen, ViewUtils.colorPair(3))
            wmove(screen, currentRow, startCol + 2)
            waddstr(screen, "Attachments")
            wattroff(screen, ViewUtils.colorPair(3))
            currentRow += 1

            for attachment in volume.attachments {
                wmove(screen, currentRow, startCol + 4)
                wattron(screen, ViewUtils.colorPair(6))
                if let serverId = attachment.serverId, let device = attachment.device {
                    waddstr(screen, "• Server: \(serverId) (Device: \(device))")
                } else if let serverId = attachment.serverId {
                    waddstr(screen, "• Server: \(serverId)")
                } else {
                    waddstr(screen, "• Unknown attachment")
                }
                wattroff(screen, ViewUtils.colorPair(6))
                currentRow += 1
            }
            currentRow += 1
        }

        // Timestamps
        if volume.createdAt != nil {
            wattron(screen, ViewUtils.colorPair(3))
            wmove(screen, currentRow, startCol + 2)
            waddstr(screen, "Timestamps")
            wattroff(screen, ViewUtils.colorPair(3))
            currentRow += 1

            if let created = volume.createdAt {
                wmove(screen, currentRow, startCol + 4)
                wattron(screen, ViewUtils.colorPair(6))
                waddstr(screen, "Created: \(created)")
                wattroff(screen, ViewUtils.colorPair(6))
                currentRow += 1
            }
            currentRow += 1
        }

        wmove(screen, startRow + height - 2, startCol + 2)
        wattron(screen, ViewUtils.colorPair(4))
        waddstr(screen, "Press ESC to return to volume list")
        wattroff(screen, ViewUtils.colorPair(4))
    }
}