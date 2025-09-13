import Foundation
import CNCurses
import OTClient

struct ImageViews {
    @MainActor
    static func drawDetailedImageList(screen: OpaquePointer?, startRow: Int32, startCol: Int32,
                                    width: Int32, height: Int32, cachedImages: [Image],
                                    searchQuery: String?, scrollOffset: Int, selectedIndex: Int) async {
        wattron(screen, ViewUtils.colorPair(2))
        wmove(screen, startRow, startCol + 2)
        let searchInfo = searchQuery != nil ? " (filtered: \(searchQuery!))" : ""
        waddstr(screen, "* Images\(searchInfo)")
        wattroff(screen, ViewUtils.colorPair(2))

        let images = FilterUtils.filterImages(cachedImages, query: searchQuery)
        let visibleHeight = Int(height) - 4

        for i in 0..<visibleHeight {
            let imageIndex = scrollOffset + i
            let row = startRow + Int32(i) + 2

            if imageIndex >= images.count {
                wmove(screen, row, startCol + 2)
                wclrtoeol(screen)
                continue
            }

            let image = images[imageIndex]
            wmove(screen, row, startCol + 2)
            wclrtoeol(screen)

            if imageIndex == selectedIndex {
                wattron(screen, ViewUtils.colorPair(3))
                waddstr(screen, "> ")
            } else {
                waddstr(screen, "  ")
            }

            let maxNameWidth = Int(width) - 30
            let imageName = image.name ?? "Unnamed Image"
            let truncatedName = imageName.count > maxNameWidth ?
                String(imageName.prefix(maxNameWidth - 3)) + "..." : imageName
            waddstr(screen, truncatedName)

            // Size column
            let sizeCol = startCol + Int32(maxNameWidth) + 5
            wmove(screen, row, sizeCol)
            if let size = image.size {
                let sizeGB = Double(size) / (1024 * 1024 * 1024)
                waddstr(screen, String(format: "%.1fGB", sizeGB))
            }

            // Status column
            let statusCol = sizeCol + 10
            wmove(screen, row, statusCol)
            if let status = image.status {
                let statusColor: Int32 = status.lowercased() == "active" ? 5 :
                                      (status.lowercased().contains("error") ? 7 : 2)
                wattron(screen, ViewUtils.colorPair(statusColor))
                waddstr(screen, status)
                wattroff(screen, ViewUtils.colorPair(statusColor))
            } else {
                wattron(screen, ViewUtils.colorPair(4))
                waddstr(screen, "Unknown")
                wattroff(screen, ViewUtils.colorPair(4))
            }

            if imageIndex == selectedIndex {
                wattroff(screen, ViewUtils.colorPair(3))
            }
        }

        wmove(screen, startRow + height - 2, startCol + 2)
        wattron(screen, ViewUtils.colorPair(4))
        wattroff(screen, ViewUtils.colorPair(4))
    }

    @MainActor
    static func drawImageDetail(screen: OpaquePointer?, startRow: Int32, startCol: Int32,
                              width: Int32, height: Int32, image: Image) async {
        wattron(screen, ViewUtils.colorPair(2))
        wmove(screen, startRow, startCol + 2)
        waddstr(screen, "* Image Details: \(image.name ?? "Unnamed Image")")
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
        waddstr(screen, "ID: \(image.id)")
        wattroff(screen, ViewUtils.colorPair(6))
        currentRow += 1

        if let name = image.name {
            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "Name: \(name)")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1
        }

        wmove(screen, currentRow, startCol + 4)
        wattron(screen, ViewUtils.colorPair(6))
        let status = image.status ?? "Unknown"
        let statusColor: Int32 = status.lowercased() == "active" ? 5 :
                              (status.lowercased().contains("error") ? 7 : 2)
        waddstr(screen, "Status: ")
        wattron(screen, ViewUtils.colorPair(statusColor))
        waddstr(screen, status)
        wattroff(screen, ViewUtils.colorPair(statusColor))
        wattroff(screen, ViewUtils.colorPair(6))
        currentRow += 1

        if let visibility = image.visibility {
            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "Visibility: \(visibility)")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1
        }

        currentRow += 1

        // Technical Information
        wattron(screen, ViewUtils.colorPair(3))
        wmove(screen, currentRow, startCol + 2)
        waddstr(screen, "Technical Information")
        wattroff(screen, ViewUtils.colorPair(3))
        currentRow += 1

        if let size = image.size {
            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            let sizeGB = Double(size) / (1024 * 1024 * 1024)
            waddstr(screen, String(format: "Size: %.2f GB", sizeGB))
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1
        }

        if let diskFormat = image.diskFormat {
            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "Disk Format: \(diskFormat)")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1
        }

        if let containerFormat = image.containerFormat {
            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "Container Format: \(containerFormat)")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1
        }

        if let minDisk = image.minDisk, minDisk > 0 {
            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "Minimum Disk: \(minDisk) GB")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1
        }

        if let minRam = image.minRam, minRam > 0 {
            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "Minimum RAM: \(minRam) MB")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1
        }

        currentRow += 1

        // Timestamps
        if image.createdAt != nil || image.updatedAt != nil {
            wattron(screen, ViewUtils.colorPair(3))
            wmove(screen, currentRow, startCol + 2)
            waddstr(screen, "Timestamps")
            wattroff(screen, ViewUtils.colorPair(3))
            currentRow += 1

            if let created = image.createdAt {
                wmove(screen, currentRow, startCol + 4)
                wattron(screen, ViewUtils.colorPair(6))
                waddstr(screen, "Created: \(created)")
                wattroff(screen, ViewUtils.colorPair(6))
                currentRow += 1
            }

            if let updated = image.updatedAt {
                wmove(screen, currentRow, startCol + 4)
                wattron(screen, ViewUtils.colorPair(6))
                waddstr(screen, "Updated: \(updated)")
                wattroff(screen, ViewUtils.colorPair(6))
                currentRow += 1
            }
        }

        wmove(screen, startRow + height - 2, startCol + 2)
        wattron(screen, ViewUtils.colorPair(4))
        waddstr(screen, "Press ESC to return to image list")
        wattroff(screen, ViewUtils.colorPair(4))
    }
}