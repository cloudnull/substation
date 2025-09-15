import Foundation
import CNCurses
import OTClient

struct SecurityGroupManagementView {
    @MainActor
    static func draw(screen: OpaquePointer?, startRow: Int32, startCol: Int32,
                    width: Int32, height: Int32, form: SecurityGroupManagementForm) async {

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
        waddstr(screen, "* Manage Security Groups - \(server.name ?? "Unnamed Server")")
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
            instruction = "Viewing current security groups. Press TAB to switch modes."
        case .add:
            instruction = "Select groups to add. SPACE to toggle, ENTER to apply changes."
        case .remove:
            instruction = "Select groups to remove. SPACE to toggle, ENTER to apply changes."
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
            waddstr(screen, "Loading security groups...")
            wattroff(screen, ViewUtils.colorPair(2))
            return
        }

        // Security groups list
        let securityGroups: [SecurityGroup]
        let listTitle: String

        switch form.selectedOperation {
        case .view:
            securityGroups = form.serverSecurityGroups
            listTitle = "Current Security Groups:"
        case .add:
            securityGroups = form.getAvailableSecurityGroupsForAdd()
            listTitle = "Available Security Groups:"
        case .remove:
            securityGroups = form.getSecurityGroupsForRemove()
            listTitle = "Assigned Security Groups:"
        }

        wattron(screen, ViewUtils.colorPair(3))
        wmove(screen, currentRow, startCol + 2)
        waddstr(screen, listTitle)
        wattroff(screen, ViewUtils.colorPair(3))
        currentRow += 1

        // List security groups
        let maxDisplayRows = Int(height - 15) // Leave space for header, instructions, and footer
        let startIndex = max(0, form.selectedSecurityGroupIndex - maxDisplayRows + 1)
        let endIndex = min(securityGroups.count, startIndex + maxDisplayRows)

        for i in startIndex..<endIndex {
            let securityGroup = securityGroups[i]
            let row = currentRow + Int32(i - startIndex)
            let isSelected = i == form.selectedSecurityGroupIndex
            let isToggled = form.isSecurityGroupSelected(securityGroup.id)

            wmove(screen, row, startCol + 4)

            // Selection indicator
            if isSelected {
                wattron(screen, ViewUtils.colorPair(2))
                waddstr(screen, "> ")
                wattroff(screen, ViewUtils.colorPair(2))
            } else {
                waddstr(screen, "  ")
            }

            // Toggle indicator for add/remove modes
            if form.selectedOperation != .view {
                let toggleChar = isToggled ? "[X]" : "[ ]"
                let toggleColor: Int32 = isToggled ? 5 : 6
                wattron(screen, ViewUtils.colorPair(toggleColor))
                waddstr(screen, toggleChar)
                wattroff(screen, ViewUtils.colorPair(toggleColor))
                waddstr(screen, " ")
            }

            // Security group name
            let nameColor: Int32 = isSelected ? 2 : 6
            wattron(screen, ViewUtils.colorPair(nameColor))
            waddstr(screen, securityGroup.name)
            wattroff(screen, ViewUtils.colorPair(nameColor))

            // Status indicator for current assignment
            if form.selectedOperation == .add && form.isSecurityGroupCurrentlyAssigned(securityGroup.id) {
                wattron(screen, ViewUtils.colorPair(4))
                waddstr(screen, " (already assigned)")
                wattroff(screen, ViewUtils.colorPair(4))
            }
        }

        // Scroll indicator
        if securityGroups.count > maxDisplayRows {
            let scrollRow = startRow + height - 5
            wmove(screen, scrollRow, startCol + 2)
            wattron(screen, ViewUtils.colorPair(4))
            waddstr(screen, "(\(form.selectedSecurityGroupIndex + 1)/\(securityGroups.count)) Use UP/DOWN to scroll")
            wattroff(screen, ViewUtils.colorPair(4))
        }

        // Pending changes summary
        if form.hasPendingChanges() {
            let summaryRow = startRow + height - 4
            wmove(screen, summaryRow, startCol + 2)
            wattron(screen, ViewUtils.colorPair(3))
            waddstr(screen, "Pending: +\(form.pendingAdditions.count) -\(form.pendingRemovals.count)")
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
}