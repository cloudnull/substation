import Foundation
import CNCurses
import OTClient

struct MiscViews {
    @MainActor
    static func drawHelp(screen: OpaquePointer?, startRow: Int32, startCol: Int32,
                        width: Int32, height: Int32, scrollOffset: Int = 0) async {
        wattron(screen, ViewUtils.colorPair(2))
        wmove(screen, startRow, startCol + 2)
        waddstr(screen, "* Help - Keyboard Shortcuts")
        wattroff(screen, ViewUtils.colorPair(2))

        var currentRow = startRow + 2

        let helpText = [
            ("Navigation", [
                "UP/DOWN: Navigate up/down in lists",
                "LEFT/RIGHT: Navigate in server creation form",
                "SPACE: View details of selected item",
                "ESC: Return to previous view or clear search",
                "TAB: Navigate fields in server creation",
                "SHIFT+TAB: Navigate fields backward",
            ]),
            ("Views", [
                "d: Dashboard view",
                "s: Servers view",
                "n: Networks view",
                "v: Volumes view",
                "i: Images view",
                "f: Flavors view",
                "k: SSH Key Pairs view",
                "t: Topology view",
                "?: Help (this view)",
            ]),
            ("Server Management", [
                "B: Create new server (from servers view)",
                "G: Manage security groups for selected server",
                "R: Restart/reboot selected server",
                "Z: Resize selected server (change flavor)",
                "S: Start selected server",
                "T: Stop selected server",
                "L: View console logs for selected server",
                "DEL: Delete selected server",
            ]),
            ("General Actions", [
                "/: Search/filter current list",
                "r: Manual refresh data",
                "a: Toggle auto-refresh (ON/OFF)",
                "W: Export topology (from topology view)",
                "q/Q: Quit application",
            ]),
            ("Security Group Management", [
                "TAB: Switch between View/Add/Remove modes",
                "SPACE: Toggle security group selection",
                "ENTER: Apply pending changes",
                "ESC: Cancel and return to servers view",
                "Visual indicators: [X] = assigned, [ ] = available",
            ]),
            ("Server Creation", [
                "TAB: Move to next field",
                "ENTER: Edit field or create server",
                "LEFT/RIGHT: Change selection in dropdown fields",
                "Type: Enter text for server name",
                "BACKSPACE: Remove characters",
                "ESC: Cancel creation and return",
            ]),
            ("Features", [
                "Auto-refresh: Data refreshes every 30 seconds",
                "Smart caching: Reduces API calls for performance",
                "UUID resolution: Shows friendly names for resources",
                "Color coding: Visual status indicators",
                "Boot sources: Support for image and volume boot",
                "Choice indicators: (n/X) for multi-option fields",
                "Topology export: ASCII network diagrams",
                "Enhanced visuals: Field highlighting and feedback",
                "Volume Status: Dashboard shows volume health and usage",
                "Security Groups: Add/remove multiple groups from servers",
            ])
        ]

        // Calculate total lines and visible area
        let visibleLines = Int(height - 5) // Account for header and instructions
        var allLines: [(String, Bool)] = [] // (text, isHeader)

        // Build all lines with section markers
        for (section, items) in helpText {
            allLines.append((section, true)) // Section header
            for item in items {
                allLines.append((item, false)) // Item
            }
            allLines.append(("", false)) // Spacing
        }

        // Remove last empty line
        if !allLines.isEmpty && allLines.last?.0 == "" {
            allLines.removeLast()
        }

        // Apply scroll offset with bounds checking
        let maxPossibleScroll = max(allLines.count - visibleLines, 0)
        let actualScrollOffset = min(scrollOffset, maxPossibleScroll)
        let startIndex = actualScrollOffset
        let endIndex = min(startIndex + visibleLines, allLines.count)

        // Render visible lines
        for i in startIndex..<endIndex {
            let (text, isHeader) = allLines[i]

            if text.isEmpty {
                currentRow += 1
                continue
            }

            wmove(screen, currentRow, startCol + (isHeader ? 2 : 4))
            if isHeader {
                wattron(screen, ViewUtils.colorPair(3))
                waddstr(screen, text)
                wattroff(screen, ViewUtils.colorPair(3))
            } else {
                wattron(screen, ViewUtils.colorPair(6))
                waddstr(screen, text)
                wattroff(screen, ViewUtils.colorPair(6))
            }
            currentRow += 1
        }

        // Scroll indicators and instructions
        wmove(screen, startRow + height - 3, startCol + 2)
        wattron(screen, ViewUtils.colorPair(4))
        if allLines.count > visibleLines {
            let scrollInfo = "(\(startIndex + 1)-\(endIndex) of \(allLines.count)) Use UP/DOWN to scroll"
            waddstr(screen, scrollInfo)
        }
        wattroff(screen, ViewUtils.colorPair(4))

        wmove(screen, startRow + height - 2, startCol + 2)
        wattron(screen, ViewUtils.colorPair(4))
        waddstr(screen, "Press ESC to return to previous view")
        wattroff(screen, ViewUtils.colorPair(4))
    }

    @MainActor
    static func drawServerCreate(screen: OpaquePointer?, startRow: Int32, startCol: Int32,
                                width: Int32, height: Int32, serverCreateForm: ServerCreateForm,
                                cachedImages: [Image], cachedFlavors: [Flavor],
                                cachedNetworks: [Network], cachedSecurityGroups: [SecurityGroup],
                                cachedKeyPairs: [KeyPair], cachedVolumes: [Volume]) async {
        wattron(screen, ViewUtils.colorPair(2))
        wmove(screen, startRow, startCol + 2)
        waddstr(screen, "* Create New Server")
        wattroff(screen, ViewUtils.colorPair(2))

        var currentRow = startRow + 2

        // Server name
        wattron(screen, ViewUtils.colorPair(3))
        wmove(screen, currentRow, startCol + 2)
        waddstr(screen, "Server Name:")
        wattroff(screen, ViewUtils.colorPair(3))
        currentRow += 1

        wmove(screen, currentRow, startCol + 4)

        // Enhanced highlighting for server name field
        let nameFieldSelected = serverCreateForm.currentField == .name
        let nameFieldActive = nameFieldSelected && serverCreateForm.fieldEditMode
        let nameFieldHighlighted = serverCreateForm.nameFieldHighlighted

        if nameFieldActive {
            wattron(screen, ViewUtils.colorPair(5)) // Green for active input
        } else if nameFieldHighlighted {
            wattron(screen, ViewUtils.colorPair(2)) // Yellow/orange for highlighted
        } else if nameFieldSelected {
            wattron(screen, ViewUtils.colorPair(7)) // Red for selected
        } else {
            wattron(screen, ViewUtils.colorPair(6)) // Normal color
        }

        let nameText = serverCreateForm.serverName.isEmpty ? "[Enter server name]" : serverCreateForm.serverName
        waddstr(screen, nameText)

        if nameFieldActive {
            waddstr(screen, "_") // Show cursor when editing
        }

        if nameFieldActive {
            wattroff(screen, ViewUtils.colorPair(5))
        } else if nameFieldHighlighted {
            wattroff(screen, ViewUtils.colorPair(2))
        } else if nameFieldSelected {
            wattroff(screen, ViewUtils.colorPair(7))
        } else {
            wattroff(screen, ViewUtils.colorPair(6))
        }
        currentRow += 2

        // Boot Source selection
        wattron(screen, ViewUtils.colorPair(3))
        wmove(screen, currentRow, startCol + 2)
        waddstr(screen, "Boot Source:")
        wattroff(screen, ViewUtils.colorPair(3))
        currentRow += 1

        wmove(screen, currentRow, startCol + 4)
        if serverCreateForm.currentField == .bootSource {
            wattron(screen, ViewUtils.colorPair(7))
        } else {
            wattron(screen, ViewUtils.colorPair(6))
        }
        waddstr(screen, serverCreateForm.bootSource.title)
        if serverCreateForm.currentField == .bootSource {
            waddstr(screen, " ←→")  // Show navigation hint
        }
        if serverCreateForm.currentField == .bootSource {
            wattroff(screen, ViewUtils.colorPair(7))
        } else {
            wattroff(screen, ViewUtils.colorPair(6))
        }
        currentRow += 2

        // Image or Volume selection (based on boot source)
        switch serverCreateForm.bootSource {
        case .image:
            wattron(screen, ViewUtils.colorPair(3))
            wmove(screen, currentRow, startCol + 2)
            waddstr(screen, "Image:")
            wattroff(screen, ViewUtils.colorPair(3))
            currentRow += 1

            wmove(screen, currentRow, startCol + 4)
            if serverCreateForm.currentField == .image {
                wattron(screen, ViewUtils.colorPair(7))
            } else {
                wattron(screen, ViewUtils.colorPair(6))
            }

            if serverCreateForm.selectedImageIndex < cachedImages.count {
                let selectedImage = cachedImages[serverCreateForm.selectedImageIndex]
                let imageName = selectedImage.name ?? "Unnamed Image"
                let choiceIndicator = cachedImages.count > 1 ? " (\(serverCreateForm.selectedImageIndex + 1)/\(cachedImages.count))" : ""
                waddstr(screen, "\(imageName)\(choiceIndicator)")
            } else {
                waddstr(screen, "[No image selected]")
            }

            if serverCreateForm.currentField == .image {
                wattroff(screen, ViewUtils.colorPair(7))
            } else {
                wattroff(screen, ViewUtils.colorPair(6))
            }

        case .volume:
            wattron(screen, ViewUtils.colorPair(3))
            wmove(screen, currentRow, startCol + 2)
            waddstr(screen, "Volume:")
            wattroff(screen, ViewUtils.colorPair(3))
            currentRow += 1

            wmove(screen, currentRow, startCol + 4)
            if serverCreateForm.currentField == .volume {
                wattron(screen, ViewUtils.colorPair(7))
            } else {
                wattron(screen, ViewUtils.colorPair(6))
            }

            if serverCreateForm.selectedVolumeIndex < cachedVolumes.count {
                let selectedVolume = cachedVolumes[serverCreateForm.selectedVolumeIndex]
                let volumeName = selectedVolume.name ?? "Unnamed Volume"
                let sizeInfo = selectedVolume.size != nil ? " [\(selectedVolume.size!)GB]" : ""
                let choiceIndicator = cachedVolumes.count > 1 ? " (\(serverCreateForm.selectedVolumeIndex + 1)/\(cachedVolumes.count))" : ""
                waddstr(screen, "\(volumeName)\(sizeInfo)\(choiceIndicator)")
            } else {
                waddstr(screen, "[No volume selected]")
            }

            if serverCreateForm.currentField == .volume {
                wattroff(screen, ViewUtils.colorPair(7))
            } else {
                wattroff(screen, ViewUtils.colorPair(6))
            }
        }
        currentRow += 2

        // Flavor selection
        wattron(screen, ViewUtils.colorPair(3))
        wmove(screen, currentRow, startCol + 2)
        waddstr(screen, "Flavor:")
        wattroff(screen, ViewUtils.colorPair(3))
        currentRow += 1

        wmove(screen, currentRow, startCol + 4)
        if serverCreateForm.currentField == .flavor {
            wattron(screen, ViewUtils.colorPair(7))
        } else {
            wattron(screen, ViewUtils.colorPair(6))
        }

        if serverCreateForm.selectedFlavorIndex < cachedFlavors.count {
            let selectedFlavor = cachedFlavors[serverCreateForm.selectedFlavorIndex]
            let vcpuInfo = selectedFlavor.vcpus != nil ? " [\(selectedFlavor.vcpus!)vCPU" : ""
            let ramInfo = selectedFlavor.ram != nil ? ", \(selectedFlavor.ram!)MB]" : (vcpuInfo.isEmpty ? "" : "]")
            let choiceIndicator = cachedFlavors.count > 1 ? " (\(serverCreateForm.selectedFlavorIndex + 1)/\(cachedFlavors.count))" : ""
            waddstr(screen, "\(selectedFlavor.name)\(vcpuInfo)\(ramInfo)\(choiceIndicator)")
        } else {
            waddstr(screen, "[No flavor selected]")
        }

        if serverCreateForm.currentField == .flavor {
            wattroff(screen, ViewUtils.colorPair(7))
        } else {
            wattroff(screen, ViewUtils.colorPair(6))
        }
        currentRow += 2

        // Network selection
        wattron(screen, ViewUtils.colorPair(3))
        wmove(screen, currentRow, startCol + 2)
        waddstr(screen, "Network:")
        wattroff(screen, ViewUtils.colorPair(3))
        currentRow += 1

        wmove(screen, currentRow, startCol + 4)
        if serverCreateForm.currentField == .network {
            wattron(screen, ViewUtils.colorPair(7))
        } else {
            wattron(screen, ViewUtils.colorPair(6))
        }

        if serverCreateForm.selectedNetworkIndex < cachedNetworks.count {
            let selectedNetwork = cachedNetworks[serverCreateForm.selectedNetworkIndex]
            let choiceIndicator = cachedNetworks.count > 1 ? " (\(serverCreateForm.selectedNetworkIndex + 1)/\(cachedNetworks.count))" : ""
            waddstr(screen, "\(selectedNetwork.name)\(choiceIndicator)")
        } else {
            waddstr(screen, "[Auto-assign network]")
        }

        if serverCreateForm.currentField == .network {
            wattroff(screen, ViewUtils.colorPair(7))
        } else {
            wattroff(screen, ViewUtils.colorPair(6))
        }
        currentRow += 2

        // Network selection
        wattron(screen, ViewUtils.colorPair(3))
        wmove(screen, currentRow, startCol + 2)
        waddstr(screen, "Security Group:")
        wattroff(screen, ViewUtils.colorPair(3))
        currentRow += 1

        wmove(screen, currentRow, startCol + 4)
        if serverCreateForm.currentField == .securityGroup {
            wattron(screen, ViewUtils.colorPair(7))
        } else {
            wattron(screen, ViewUtils.colorPair(6))
        }

        if serverCreateForm.selectedSecurityGroupIndex < cachedSecurityGroups.count {
            let selectedSecurityGroup = cachedSecurityGroups[serverCreateForm.selectedSecurityGroupIndex]
            let choiceIndicator = cachedSecurityGroups.count > 1 ? " (\(serverCreateForm.selectedSecurityGroupIndex + 1)/\(cachedSecurityGroups.count))" : ""
            waddstr(screen, "\(selectedSecurityGroup.name)\(choiceIndicator)")
        } else {
            waddstr(screen, "[No security group selected]")
        }

        if serverCreateForm.currentField == .securityGroup {
            wattroff(screen, ViewUtils.colorPair(7))
        } else {
            wattroff(screen, ViewUtils.colorPair(6))
        }
        currentRow += 2

        // Key pair selection
        wattron(screen, ViewUtils.colorPair(3))
        wmove(screen, currentRow, startCol + 2)
        waddstr(screen, "Key Pair:")
        wattroff(screen, ViewUtils.colorPair(3))
        currentRow += 1

        wmove(screen, currentRow, startCol + 4)
        if serverCreateForm.currentField == .keyPair {
            wattron(screen, ViewUtils.colorPair(7))
        } else {
            wattron(screen, ViewUtils.colorPair(6))
        }

        if serverCreateForm.selectedKeyPairIndex < cachedKeyPairs.count {
            let selectedKeyPair = cachedKeyPairs[serverCreateForm.selectedKeyPairIndex]
            let choiceIndicator = cachedKeyPairs.count > 1 ? " (\(serverCreateForm.selectedKeyPairIndex + 1)/\(cachedKeyPairs.count))" : ""
            waddstr(screen, "\(selectedKeyPair.name)\(choiceIndicator)")
        } else {
            waddstr(screen, "[No key pair]")
        }

        if serverCreateForm.currentField == .keyPair {
            wattroff(screen, ViewUtils.colorPair(7))
        } else {
            wattroff(screen, ViewUtils.colorPair(6))
        }

        // Instructions
        wmove(screen, startRow + height - 4, startCol + 2)
        wattron(screen, ViewUtils.colorPair(4))
        waddstr(screen, "↑/↓: Navigate fields | Enter: Create server | ESC: Cancel")
        wattroff(screen, ViewUtils.colorPair(4))

        wmove(screen, startRow + height - 3, startCol + 2)
        wattron(screen, ViewUtils.colorPair(4))
        waddstr(screen, "←/→: Change selection | Type: Edit server name")
        wattroff(screen, ViewUtils.colorPair(4))
    }

    @MainActor
    static func drawServerResizeDialog(screen: OpaquePointer?, startRow: Int32, startCol: Int32,
                                     width: Int32, height: Int32, server: Server,
                                     cachedFlavors: [Flavor], serverResizeForm: ServerResizeForm) async {
        // Draw border for dialog
        wattron(screen, ViewUtils.colorPair(2))
        for row in startRow..<(startRow + height) {
            wmove(screen, row, startCol)
            for _ in startCol..<(startCol + width) {
                waddstr(screen, " ")
            }
        }

        // Draw title
        wmove(screen, startRow + 1, startCol + 2)
        waddstr(screen, "* Resize Server: \(server.name ?? "Unknown")")
        wattroff(screen, ViewUtils.colorPair(2))

        var currentRow = startRow + 3

        // Current flavor info
        if let currentFlavor = server.flavor {
            wattron(screen, ViewUtils.colorPair(3))
            wmove(screen, currentRow, startCol + 2)
            waddstr(screen, "Current Flavor:")
            wattroff(screen, ViewUtils.colorPair(3))
            currentRow += 1

            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "ID: \(currentFlavor.id)")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 2
        }

        // New flavor selection
        wattron(screen, ViewUtils.colorPair(3))
        wmove(screen, currentRow, startCol + 2)
        waddstr(screen, "New Flavor:")
        wattroff(screen, ViewUtils.colorPair(3))
        currentRow += 1

        wmove(screen, currentRow, startCol + 4)
        wattron(screen, ViewUtils.colorPair(7)) // Highlighted since it's the only selectable field

        if serverResizeForm.selectedFlavorIndex < cachedFlavors.count {
            let selectedFlavor = cachedFlavors[serverResizeForm.selectedFlavorIndex]
            let vcpuInfo = selectedFlavor.vcpus != nil ? " [\(selectedFlavor.vcpus!)vCPU" : ""
            let ramInfo = selectedFlavor.ram != nil ? ", \(selectedFlavor.ram!)MB]" : (vcpuInfo.isEmpty ? "" : "]")
            let choiceIndicator = cachedFlavors.count > 1 ? " (\(serverResizeForm.selectedFlavorIndex + 1)/\(cachedFlavors.count))" : ""
            waddstr(screen, "\(selectedFlavor.name)\(vcpuInfo)\(ramInfo)\(choiceIndicator)")
        } else {
            waddstr(screen, "[No flavor selected]")
        }

        wattroff(screen, ViewUtils.colorPair(7))
        currentRow += 3

        // Warning message
        wattron(screen, ViewUtils.colorPair(5)) // Warning color (red)
        wmove(screen, currentRow, startCol + 2)
        waddstr(screen, "⚠  WARNING: Server will be temporarily shutdown during resize")
        wattroff(screen, ViewUtils.colorPair(5))
        currentRow += 2

        // Instructions
        wmove(screen, startRow + height - 4, startCol + 2)
        wattron(screen, ViewUtils.colorPair(4))
        waddstr(screen, "←/→: Change flavor selection | Enter: Confirm resize | ESC: Cancel")
        wattroff(screen, ViewUtils.colorPair(4))
    }
}