import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import OTClient
import CNCurses

// MARK: - Imports for separated modules
// Data models, view components, and utilities are now in separate files

@MainActor
final class TUI {

    private let client: OTClient
    private var currentView: ViewMode = .dashboard
    private var previousView: ViewMode = .dashboard
    private var running = true
    private var scrollOffset = 0
    private var helpScrollOffset = 0
    private var selectedIndex = 0  // Currently selected item in lists
    private var selectedResource: Any? = nil  // The selected resource for detail view
    private var lastTopology: TopologyGraph?
    private var searchQuery: String?
    private var statusMessage: String?
    private var screenRows: Int32 = 0
    private var screenCols: Int32 = 0
    private var resourceCounts = ResourceCounts()
    private var lastRefresh = Date()
    private var autoRefresh = true
    private var refreshInterval: TimeInterval = 30.0

    // Cached data for performance
    private var cachedServers: [Server] = []
    private var cachedNetworks: [Network] = []
    private var cachedVolumes: [Volume] = []
    private var cachedImages: [Image] = []

    // Quota data
    private var cachedComputeLimits: ComputeLimits?
    private var cachedComputeQuotas: ComputeQuotas?
    private var cachedNetworkQuotas: NetworkQuotas?
    private var cachedVolumeQuotas: VolumeQuotas?

    // Resource name cache for UUID resolution
    private var cachedFlavors: [Flavor] = []
    private var cachedSubnets: [Subnet] = []
    private var cachedSecurityGroups: [SecurityGroup] = []
    private var cachedKeyPairs: [KeyPair] = []
    private var resourceNameCache: ResourceNameCache = ResourceNameCache()

    // Server creation form state
    private var serverCreateForm = ServerCreateForm()

    // Server resize form state
    private var serverResizeForm = ServerResizeForm()

    // Security group management form state
    private var securityGroupForm = SecurityGroupManagementForm()

    init(client: OTClient) {
        self.client = client
    }

    func run() async {
        do {

            // Set TERM if not already set
            if getenv("TERM") == nil {
                setenv("TERM", "xterm", 1)
            }

            let screen = initscr()
            if screen == nil {
                print("ERROR: Failed to initialize ncurses screen")
                return
            }

            defer {
                endwin()
            }

            // Initialize ncurses with error checking
            if cbreak() == ERR {
                print("ERROR: Failed to set cbreak mode")
                return
            }

            if noecho() == ERR {
                print("ERROR: Failed to set noecho mode")
                return
            }

            if keypad(screen, true) == ERR {
                print("ERROR: Failed to enable keypad")
                return
            }

            if nodelay(screen, true) == ERR {
                print("ERROR: Failed to set nodelay")
                return
            }

            if curs_set(0) == ERR {
                print("WARNING: Failed to hide cursor")
            }

            // Initialize colors
            if has_colors() {
                if start_color() == ERR {
                    print("ERROR: Failed to start colors")
                    return
                }

                if use_default_colors() == ERR {
                    print("WARNING: Failed to use default colors")
                }

                // Define color pairs
                init_pair(1, Int16(COLOR_CYAN), Int16(-1))      // Header/branding
                init_pair(2, Int16(COLOR_YELLOW), Int16(-1))    // Highlighted text
                init_pair(3, Int16(COLOR_BLACK), Int16(COLOR_CYAN))  // Selected items
                init_pair(4, Int16(COLOR_MAGENTA), Int16(-1))   // Status info
                init_pair(5, Int16(COLOR_GREEN), Int16(-1))     // Success/active
                init_pair(6, Int16(COLOR_WHITE), Int16(-1))     // Normal text
                init_pair(7, Int16(COLOR_RED), Int16(-1))       // Errors/warnings
                init_pair(8, Int16(COLOR_BLUE), Int16(-1))      // Borders/structure
                init_pair(9, Int16(COLOR_BLACK), Int16(COLOR_WHITE))  // Inverted
            } else {
                print("WARNING: Terminal does not support colors")
            }

            // Get screen dimensions
            screenRows = getmaxy(screen)
            screenCols = getmaxx(screen)

            if screenRows < 20 || screenCols < 80 {
                print("Terminal too small: need 80x20, got \(screenCols)x\(screenRows)")
                wmove(screen, 0, 0)
                waddstr(screen, "Terminal too small. Need at least 80x20, got \(screenCols)x\(screenRows)")
                wrefresh(screen)
                wgetch(screen)
                return
            }
            print("Welcome to the OTUI!")

            // Initial data fetch
            await refreshAllData()

            // Initial draw
            await draw(screen: screen)

            // Main event loop
            while running {
                let ch = wgetch(screen)

                // Handle window resize
                if ch == Int32(KEY_RESIZE) {
                    screenRows = getmaxy(screen)
                    screenCols = getmaxx(screen)
                    wclear(screen)
                    await draw(screen: screen)
                    continue
                }

                // Handle user input
                await handleInput(ch, screen: screen)

                // Auto-refresh check
                if autoRefresh && Date().timeIntervalSince(lastRefresh) > refreshInterval {
                    await refreshAllData()
                    lastRefresh = Date()
                }

                if !running { break }
                await draw(screen: screen)
                usleep(100_000) // 100ms refresh rate
            }
            print("TUI main loop ended")
        }
    }

    private func handleInput(_ ch: Int32, screen: OpaquePointer?) async {
        // If we're in server create mode and editing a text field,
        // only allow ESC to exit edit mode, delegate everything else to server create handler
        if currentView == .serverCreate && serverCreateForm.fieldEditMode {
            if ch == Int32(27) { // ESC - Exit edit mode
                serverCreateForm.fieldEditMode = false
                return
            }
            // Delegate all other input to server create handler
            await handleServerCreateInput(ch, screen: screen)
            return
        }

        if currentView == .serverSecurityGroups {
            // Special handling for ESC in security group management
            if ch == 27 { // ESC
                changeView(to: .servers, resetSelection: false)
                return
            }
            // Delegate all other input to security group handler
            await handleSecurityGroupInput(ch, screen: screen)
            return
        }

        switch ch {
        case Int32(113): // q
            running = false
        case Int32(100): // d - Dashboard
            changeView(to: .dashboard)
        case Int32(115): // s - Servers
            if currentView.isDetailView {
                changeView(to: .servers, resetSelection: false)
                selectedResource = nil
            } else {
                changeView(to: .servers)
            }
        case Int32(110): // n - Networks
            if currentView.isDetailView {
                changeView(to: .networks, resetSelection: false)
                selectedResource = nil
            } else {
                changeView(to: .networks)
            }
        case Int32(118): // v - Volumes
            if currentView.isDetailView {
                changeView(to: .volumes, resetSelection: false)
                selectedResource = nil
            } else {
                changeView(to: .volumes)
            }
        case Int32(105): // i - Images
            if currentView.isDetailView {
                changeView(to: .images, resetSelection: false)
                selectedResource = nil
            } else {
                changeView(to: .images)
            }
        case Int32(102): // f - Flavors
            if currentView.isDetailView {
                changeView(to: .flavors, resetSelection: false)
                selectedResource = nil
            } else {
                changeView(to: .flavors)
            }
        case Int32(116): // t - Topology
            changeView(to: .topology)
        case Int32(107): // k - Key Pairs
            if currentView.isDetailView {
                changeView(to: .keyPairs, resetSelection: false)
                selectedResource = nil
            } else {
                changeView(to: .keyPairs)
            }
        case Int32(259): // KEY_UP
            if currentView == .help {
                helpScrollOffset = max(helpScrollOffset - 1, 0)
            } else if currentView.isDetailView {
                scrollOffset = max(scrollOffset - 1, 0)
            } else {
                selectedIndex = max(selectedIndex - 1, 0)
                // Adjust scroll if selection moves out of view
                if selectedIndex < scrollOffset {
                    scrollOffset = selectedIndex
                }
            }
        case Int32(258): // KEY_DOWN
            if currentView == .help {
                // Let the help view handle bounds checking internally
                // We'll use a reasonable maximum to prevent infinite scrolling
                helpScrollOffset = min(helpScrollOffset + 1, 50)
            } else if currentView.isDetailView {
                scrollOffset += 1
            } else {
                let maxIndex = getMaxSelectionIndex()
                selectedIndex = min(selectedIndex + 1, maxIndex)
                // Adjust scroll to keep selection in view
                let visibleItems = Int(screenRows) - 8 // Account for headers/borders
                if selectedIndex >= scrollOffset + visibleItems {
                    scrollOffset = selectedIndex - visibleItems + 1
                }
            }
        case Int32(32): // SPACEBAR - Show details
            if !currentView.isDetailView {
                await openDetailView()
            }
        case Int32(27): // ESC - Back/clear search
            if currentView == .help {
                changeView(to: previousView, resetSelection: false)
            } else if currentView.isDetailView {
                changeView(to: currentView.parentView, resetSelection: false)
                selectedResource = nil
            } else if searchQuery != nil {
                searchQuery = nil
            }
        case Int32(114): // r - Manual refresh
            if currentView == .topology {
                // Fast topology-only refresh for topology view
                await refreshTopology()
                lastRefresh = Date()
            } else {
                // Full data refresh for other views
                await refreshAllData()
                lastRefresh = Date()
                statusMessage = "Data refreshed"
            }
        case Int32(97): // a - Toggle auto-refresh
            autoRefresh.toggle()
            statusMessage = "Auto-refresh: \(autoRefresh ? "ON" : "OFF")"
        case Int32(99): // c - purge cache
            // Purge cache (existing functionality)
            purgeCache()
            await refreshAllData()
            lastRefresh = Date()
        case Int32(66): // B - Create server or purge cache
            if currentView == .servers && !currentView.isDetailView {
                // Navigate to server creation
                changeView(to: .serverCreate)
                serverCreateForm = ServerCreateForm() // Reset form
            }
        case Int32(47): // / - search or filter
            if let input = prompt("Search: ", screen: screen), !input.isEmpty {
                searchQuery = input
                scrollOffset = 0
                selectedIndex = 0
            } else {
                searchQuery = nil
            }
        case Int32(63): // ? - Show help
            if currentView != .help {
                helpScrollOffset = 0 // Reset scroll when entering help
                changeView(to: .help)
            }
        case Int32(87): // W - Export topology (only in topology view)
            if currentView == .topology && lastTopology != nil {
                await exportTopology()
            }
        case Int32(127), Int32(330): // DELETE key or Delete key - Delete selected server
            if currentView == .servers && !currentView.isDetailView {
                await deleteServer(screen: screen)
            }
        case Int32(82): // R - Restart/reboot selected server
            if currentView == .servers && !currentView.isDetailView {
                await restartServer(screen: screen)
            }
        case Int32(90): // Z - Resize selected server
            if currentView == .servers && !currentView.isDetailView {
                await resizeServer(screen: screen)
            }
        case Int32(76): // L - View logs for selected server
            if currentView == .servers && !currentView.isDetailView {
                await viewServerLogs(screen: screen)
            }
        case Int32(83): // S - Start selected server
            if currentView == .servers && !currentView.isDetailView {
                await startServer(screen: screen)
            }
        case Int32(84): // T - Stop selected server
            if currentView == .servers && !currentView.isDetailView {
                await stopServer(screen: screen)
            }
        case Int32(71): // G - Manage security groups for selected server
            if currentView == .servers && !currentView.isDetailView {
                await manageServerSecurityGroups(screen: screen)
            }
        default:
            break
        }

        // Handle server creation form navigation
        if currentView == .serverCreate {
            await handleServerCreateInput(ch, screen: screen)
        }
    }

    private func handleServerCreateInput(_ ch: Int32, screen: OpaquePointer?) async {
        switch ch {
        case Int32(9): // TAB - Next field
            serverCreateForm.nextField()
        case 353: // SHIFT+TAB - Previous field (KEY_BTAB if available)
            serverCreateForm.previousField()
        case Int32(10), Int32(13): // ENTER - Edit name field or create server
            if serverCreateForm.currentField == .name && !serverCreateForm.fieldEditMode {
                serverCreateForm.activateNameField()
            } else if serverCreateForm.currentField == .name && serverCreateForm.fieldEditMode {
                serverCreateForm.fieldEditMode = false
            } else if serverCreateForm.currentField == .bootSource {
                serverCreateForm.toggleBootSource()
            } else {
                // Create server
                await createServer()
            }
        case Int32(260): // KEY_LEFT - Previous selection
            if !serverCreateForm.fieldEditMode {
                switch serverCreateForm.currentField {
                case .image:
                    if cachedImages.count > 0 {
                        serverCreateForm.selectedImageIndex = max(0, serverCreateForm.selectedImageIndex - 1)
                    }
                case .volume:
                    if cachedVolumes.count > 0 {
                        serverCreateForm.selectedVolumeIndex = max(0, serverCreateForm.selectedVolumeIndex - 1)
                    }
                case .flavor:
                    if cachedFlavors.count > 0 {
                        serverCreateForm.selectedFlavorIndex = max(0, serverCreateForm.selectedFlavorIndex - 1)
                    }
                case .network:
                    if cachedNetworks.count > 0 {
                        serverCreateForm.selectedNetworkIndex = max(0, serverCreateForm.selectedNetworkIndex - 1)
                    }
                case .securityGroup:
                    if cachedSecurityGroups.count > 0 {
                        serverCreateForm.selectedSecurityGroupIndex = max(0, serverCreateForm.selectedSecurityGroupIndex - 1)
                    }
                case .keyPair:
                    if cachedKeyPairs.count > 0 {
                        serverCreateForm.selectedKeyPairIndex = max(0, serverCreateForm.selectedKeyPairIndex - 1)
                    }
                case .bootSource:
                    serverCreateForm.toggleBootSource()
                default:
                    break
                }
            }
        case Int32(261): // KEY_RIGHT - Next selection
            if !serverCreateForm.fieldEditMode {
                switch serverCreateForm.currentField {
                case .image:
                    if cachedImages.count > 0 {
                        serverCreateForm.selectedImageIndex = min(cachedImages.count - 1, serverCreateForm.selectedImageIndex + 1)
                    }
                case .volume:
                    if cachedVolumes.count > 0 {
                        serverCreateForm.selectedVolumeIndex = min(cachedVolumes.count - 1, serverCreateForm.selectedVolumeIndex + 1)
                    }
                case .flavor:
                    if cachedFlavors.count > 0 {
                        serverCreateForm.selectedFlavorIndex = min(cachedFlavors.count - 1, serverCreateForm.selectedFlavorIndex + 1)
                    }
                case .network:
                    if cachedNetworks.count > 0 {
                        serverCreateForm.selectedNetworkIndex = min(cachedNetworks.count - 1, serverCreateForm.selectedNetworkIndex + 1)
                    }
                case .securityGroup:
                    if cachedSecurityGroups.count > 0 {
                        serverCreateForm.selectedSecurityGroupIndex = min(cachedSecurityGroups.count - 1, serverCreateForm.selectedSecurityGroupIndex + 1)
                    }
                case .keyPair:
                    if cachedKeyPairs.count > 0 {
                        serverCreateForm.selectedKeyPairIndex = min(cachedKeyPairs.count - 1, serverCreateForm.selectedKeyPairIndex + 1)
                    }
                case .bootSource:
                    serverCreateForm.toggleBootSource()
                default:
                    break
                }
            }
        case Int32(259): // KEY_UP - Previous field
            serverCreateForm.previousField()
        case Int32(258): // KEY_DOWN - Next field
            serverCreateForm.nextField()
        case Int32(27): // ESC - Exit name edit mode or cancel creation
            if serverCreateForm.fieldEditMode {
                serverCreateForm.fieldEditMode = false
            } else {
                changeView(to: .servers, resetSelection: false)
            }
        case Int32(8), Int32(127), Int32(263): // BACKSPACE/DELETE - Remove character from name
            if serverCreateForm.fieldEditMode && serverCreateForm.currentField == .name && !serverCreateForm.serverName.isEmpty {
                serverCreateForm.serverName.removeLast()
            }
        default:
            // Handle character input for server name
            if serverCreateForm.fieldEditMode && serverCreateForm.currentField == .name && ch >= 32 && ch < 127 {
                if let scalar = UnicodeScalar(Int(ch)) {
                    let char = Character(scalar)
                    serverCreateForm.serverName.append(char)
                }
            }
        }
    }

    private func handleSecurityGroupInput(_ ch: Int32, screen: OpaquePointer?) async {
        switch ch {
        case Int32(9): // TAB - Switch operation mode
            let operations = SecurityGroupManagementForm.SecurityGroupOperation.allCases
            if let currentIndex = operations.firstIndex(of: securityGroupForm.selectedOperation) {
                let nextIndex = (currentIndex + 1) % operations.count
                securityGroupForm.selectedOperation = operations[nextIndex]
                securityGroupForm.selectedSecurityGroupIndex = 0 // Reset selection
            }
        case Int32(259): // UP
            let securityGroups: [SecurityGroup]
            switch securityGroupForm.selectedOperation {
            case .view:
                securityGroups = securityGroupForm.serverSecurityGroups
            case .add:
                securityGroups = securityGroupForm.getAvailableSecurityGroupsForAdd()
            case .remove:
                securityGroups = securityGroupForm.getSecurityGroupsForRemove()
            }
            if !securityGroups.isEmpty {
                securityGroupForm.selectedSecurityGroupIndex = max(0, securityGroupForm.selectedSecurityGroupIndex - 1)
            }
        case Int32(258): // DOWN
            let securityGroups: [SecurityGroup]
            switch securityGroupForm.selectedOperation {
            case .view:
                securityGroups = securityGroupForm.serverSecurityGroups
            case .add:
                securityGroups = securityGroupForm.getAvailableSecurityGroupsForAdd()
            case .remove:
                securityGroups = securityGroupForm.getSecurityGroupsForRemove()
            }
            if !securityGroups.isEmpty {
                securityGroupForm.selectedSecurityGroupIndex = min(securityGroups.count - 1, securityGroupForm.selectedSecurityGroupIndex + 1)
            }
        case Int32(32): // SPACE - Toggle security group selection
            let securityGroups: [SecurityGroup]
            switch securityGroupForm.selectedOperation {
            case .view:
                break // No action in view mode
            case .add:
                securityGroups = securityGroupForm.getAvailableSecurityGroupsForAdd()
                if securityGroupForm.selectedSecurityGroupIndex < securityGroups.count {
                    let selectedSG = securityGroups[securityGroupForm.selectedSecurityGroupIndex]
                    securityGroupForm.toggleSecurityGroup(selectedSG.id)
                }
            case .remove:
                securityGroups = securityGroupForm.getSecurityGroupsForRemove()
                if securityGroupForm.selectedSecurityGroupIndex < securityGroups.count {
                    let selectedSG = securityGroups[securityGroupForm.selectedSecurityGroupIndex]
                    securityGroupForm.toggleSecurityGroup(selectedSG.id)
                }
            }
        case Int32(10), Int32(13): // ENTER - Apply changes
            if securityGroupForm.hasPendingChanges() {
                await applySecurityGroupChanges(screen: screen)
            }
        default:
            break
        }
    }

    private func applySecurityGroupChanges(screen: OpaquePointer?) async {
        guard let server = securityGroupForm.selectedServer else {
            statusMessage = "No server selected"
            return
        }

        let serverName = server.name ?? "Unnamed Server"
        var changeCount = 0
        var errorCount = 0

        // Apply additions
        for securityGroupID in securityGroupForm.pendingAdditions {
            if let securityGroup = securityGroupForm.availableSecurityGroups.first(where: { $0.id == securityGroupID }) {
                statusMessage = "Adding security group '\(securityGroup.name)' to \(serverName)..."
                await draw(screen: screen)

                do {
                    try await client.addSecurityGroup(serverID: server.id, securityGroupName: securityGroup.name)
                    changeCount += 1
                } catch let error as OTError {
                    errorCount += 1
                    let baseMsg = "Failed to add security group '\(securityGroup.name)'"
                    switch error {
                    case .authenticationFailed:
                        statusMessage = "\(baseMsg): Authentication failed"
                    case .endpointNotFound:
                        statusMessage = "\(baseMsg): Endpoint not found"
                    case .unexpectedResponse:
                        statusMessage = "\(baseMsg): Unexpected response"
                    case .httpError(let code):
                        if code == 409 {
                            statusMessage = "\(baseMsg): Already assigned"
                        } else if code == 404 {
                            statusMessage = "\(baseMsg): Security group not found"
                        } else {
                            statusMessage = "\(baseMsg): HTTP error \(code)"
                        }
                    }
                    await draw(screen: screen)
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 second pause for error
                } catch {
                    errorCount += 1
                    statusMessage = "Failed to add security group '\(securityGroup.name)': \(error.localizedDescription)"
                    await draw(screen: screen)
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }

        // Apply removals
        for securityGroupID in securityGroupForm.pendingRemovals {
            if let securityGroup = securityGroupForm.serverSecurityGroups.first(where: { $0.id == securityGroupID }) {
                statusMessage = "Removing security group '\(securityGroup.name)' from \(serverName)..."
                await draw(screen: screen)

                do {
                    try await client.removeSecurityGroup(serverID: server.id, securityGroupName: securityGroup.name)
                    changeCount += 1
                } catch let error as OTError {
                    errorCount += 1
                    let baseMsg = "Failed to remove security group '\(securityGroup.name)'"
                    switch error {
                    case .authenticationFailed:
                        statusMessage = "\(baseMsg): Authentication failed"
                    case .endpointNotFound:
                        statusMessage = "\(baseMsg): Endpoint not found"
                    case .unexpectedResponse:
                        statusMessage = "\(baseMsg): Unexpected response"
                    case .httpError(let code):
                        if code == 409 {
                            statusMessage = "\(baseMsg): Cannot remove (conflict)"
                        } else if code == 404 {
                            statusMessage = "\(baseMsg): Security group not found"
                        } else {
                            statusMessage = "\(baseMsg): HTTP error \(code)"
                        }
                    }
                    await draw(screen: screen)
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                } catch {
                    errorCount += 1
                    statusMessage = "Failed to remove security group '\(securityGroup.name)': \(error.localizedDescription)"
                    await draw(screen: screen)
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }

        // Summary and refresh
        if changeCount > 0 {
            var message = "Applied \(changeCount) security group changes"
            if errorCount > 0 {
                message += " (with \(errorCount) errors)"
            }
            statusMessage = message

            // Clear pending changes
            securityGroupForm.pendingAdditions.removeAll()
            securityGroupForm.pendingRemovals.removeAll()

            // Refresh security groups
            do {
                securityGroupForm.serverSecurityGroups = try await client.getServerSecurityGroups(serverID: server.id)
            } catch {
                statusMessage = message + " - Warning: Failed to refresh security groups"
            }
        } else if errorCount > 0 {
            statusMessage = "All \(errorCount) security group operations failed"
        } else {
            statusMessage = "No changes to apply"
        }
    }

    private func createServer() async {
        // Validation
        guard !serverCreateForm.serverName.isEmpty else {
            statusMessage = "Server name is required"
            return
        }

        // Validate boot source requirements
        switch serverCreateForm.bootSource {
        case .image:
            guard cachedImages.count > 0 && serverCreateForm.selectedImageIndex < cachedImages.count else {
                statusMessage = "Please select a valid image"
                return
            }
        case .volume:
            guard cachedVolumes.count > 0 && serverCreateForm.selectedVolumeIndex < cachedVolumes.count else {
                statusMessage = "Please select a valid volume"
                return
            }
        }

        guard cachedFlavors.count > 0 && serverCreateForm.selectedFlavorIndex < cachedFlavors.count else {
            statusMessage = "Please select a valid flavor"
            return
        }

        let selectedFlavor = cachedFlavors[serverCreateForm.selectedFlavorIndex]

        // Get selected network and key pair
        let selectedNetworkId = cachedNetworks.count > 0 && serverCreateForm.selectedNetworkIndex < cachedNetworks.count
            ? cachedNetworks[serverCreateForm.selectedNetworkIndex].id
            : nil
        let selectedKeyPairName = cachedKeyPairs.count > 0 && serverCreateForm.selectedKeyPairIndex < cachedKeyPairs.count
            ? cachedKeyPairs[serverCreateForm.selectedKeyPairIndex].name
            : nil

        statusMessage = "Creating server..."

        do {
            // Get boot source reference
            let (bootSourceRef, _) = getBootSourceReference()

            let newServer: Server

            switch serverCreateForm.bootSource {
            case .image:
                newServer = try await client.createServer(
                    name: serverCreateForm.serverName,
                    imageRef: bootSourceRef,
                    flavorRef: selectedFlavor.id,
                    networkId: selectedNetworkId,
                    keyPairName: selectedKeyPairName
                )
            case .volume:
                // For now, use the same API but with volume UUID as imageRef
                // This is a simplified approach - production would use block device mapping
                newServer = try await client.createServer(
                    name: serverCreateForm.serverName,
                    imageRef: bootSourceRef,
                    flavorRef: selectedFlavor.id,
                    networkId: selectedNetworkId,
                    keyPairName: selectedKeyPairName
                )
            }

            // Add to cached servers and refresh
            cachedServers.append(newServer)
            statusMessage = "Server '\(serverCreateForm.serverName)' created successfully"

            // Return to servers view
            changeView(to: .servers, resetSelection: false)

            // Refresh data to get updated server list
            await refreshAllData()

        } catch let error as OTError {
            let baseMsg = "Failed to create server"
            switch error {
            case .authenticationFailed:
                statusMessage = "\(baseMsg): Authentication failed - check credentials"
            case .endpointNotFound:
                statusMessage = "\(baseMsg): Compute service endpoint not found - check cloud config"
            case .unexpectedResponse:
                statusMessage = "\(baseMsg): Unexpected response - server may be overloaded"
            case .httpError(let code):
                statusMessage = "\(baseMsg): HTTP \(code) - check image/flavor/network availability"
            }
        } catch let decodingError as DecodingError {
            let baseMsg = "Failed to create server"
            switch decodingError {
            case .dataCorrupted(let context):
                statusMessage = "\(baseMsg): Data corrupted - \(context.debugDescription)"
            case .keyNotFound(let key, _):
                statusMessage = "\(baseMsg): Missing key '\(key.stringValue)' in response"
            case .typeMismatch(let type, let context):
                statusMessage = "\(baseMsg): Type mismatch for \(type) - \(context.debugDescription)"
            case .valueNotFound(let type, let context):
                statusMessage = "\(baseMsg): Missing value for \(type) - \(context.debugDescription)"
            @unknown default:
                statusMessage = "\(baseMsg): JSON parsing error - \(decodingError.localizedDescription)"
            }
        } catch {
            statusMessage = "Failed to create server: \(error.localizedDescription) - Type: \(type(of: error))"
        }
    }

    private func getBootSourceReference() -> (String, String) {
        switch serverCreateForm.bootSource {
        case .image:
            let selectedImage = cachedImages[serverCreateForm.selectedImageIndex]
            return (selectedImage.id, "image")
        case .volume:
            let selectedVolume = cachedVolumes[serverCreateForm.selectedVolumeIndex]
            return (selectedVolume.id, "volume")
        }
    }

    private func deleteServer(screen: OpaquePointer?) async {
        guard currentView == .servers else { return }

        let resourceResolver = createResourceResolver()
        let filteredServers = ResourceFilters.filterServers(cachedServers, query: searchQuery, getServerIP: resourceResolver.getServerIP)
        guard selectedIndex < filteredServers.count else {
            statusMessage = "No server selected"
            return
        }

        let server = filteredServers[selectedIndex]
        let serverName = server.name ?? "Unnamed Server"

        // Confirm deletion
        guard confirmDelete(serverName, screen: screen) else {
            statusMessage = "Server deletion cancelled"
            return
        }

        // Show deletion in progress
        statusMessage = "Deleting server '\(serverName)'..."
        await draw(screen: screen) // Refresh UI to show progress message

        do {
            try await client.deleteServer(id: server.id)

            // Remove from cached servers
            if let index = cachedServers.firstIndex(where: { $0.id == server.id }) {
                cachedServers.remove(at: index)
            }

            // Adjust selection if needed
            let newMaxIndex = max(0, filteredServers.count - 2) // -1 for removed item, -1 for 0-based
            selectedIndex = min(selectedIndex, newMaxIndex)

            statusMessage = "Server '\(serverName)' deleted successfully"

            // Refresh data to get updated server list
            await refreshAllData()

        } catch let error as OTError {
            let baseMsg = "Failed to delete server '\(serverName)'"
            switch error {
            case .authenticationFailed:
                statusMessage = "\(baseMsg): Authentication failed - check credentials"
            case .endpointNotFound:
                statusMessage = "\(baseMsg): Endpoint not found - check service configuration"
            case .unexpectedResponse:
                statusMessage = "\(baseMsg): Unexpected response from server"
            case .httpError(let code):
                statusMessage = "\(baseMsg): HTTP error \(code)"
            }
        } catch {
            statusMessage = "Failed to delete server '\(serverName)': \(error.localizedDescription)"
        }
    }

    private func restartServer(screen: OpaquePointer?) async {
        guard currentView == .servers else { return }

        let resourceResolver = createResourceResolver()
        let filteredServers = ResourceFilters.filterServers(cachedServers, query: searchQuery, getServerIP: resourceResolver.getServerIP)
        guard selectedIndex < filteredServers.count else {
            statusMessage = "No server selected"
            return
        }

        let server = filteredServers[selectedIndex]
        let serverName = server.name ?? "Unnamed Server"

        // Confirm restart
        guard confirmRestart(serverName, screen: screen) else {
            statusMessage = "Server restart cancelled"
            return
        }

        // Show restart in progress
        statusMessage = "Restarting server '\(serverName)'..."
        await draw(screen: screen) // Refresh UI to show progress message

        do {
            try await client.rebootServer(id: server.id, type: "SOFT")

            statusMessage = "Server '\(serverName)' restart initiated successfully"

            // Refresh data to get updated server status
            await refreshAllData()

        } catch let error as OTError {
            let baseMsg = "Failed to restart server '\(serverName)'"
            switch error {
            case .authenticationFailed:
                statusMessage = "\(baseMsg): Authentication failed - check credentials"
            case .endpointNotFound:
                statusMessage = "\(baseMsg): Endpoint not found - check service configuration"
            case .unexpectedResponse:
                statusMessage = "\(baseMsg): Unexpected response from server"
            case .httpError(let code):
                statusMessage = "\(baseMsg): HTTP error \(code)"
            }
        } catch {
            statusMessage = "Failed to restart server '\(serverName)': \(error.localizedDescription)"
        }
    }

    private func resizeServer(screen: OpaquePointer?) async {
        guard currentView == .servers else { return }

        let resourceResolver = createResourceResolver()
        let filteredServers = ResourceFilters.filterServers(cachedServers, query: searchQuery, getServerIP: resourceResolver.getServerIP)
        guard selectedIndex < filteredServers.count else {
            statusMessage = "No server selected"
            return
        }

        let server = filteredServers[selectedIndex]
        let serverName = server.name ?? "Unnamed Server"

        print("DEBUG: Starting resize for server: \(serverName) (\(server.id))")
        statusMessage = "DEBUG: Starting resize for \(serverName)"
        await draw(screen: screen)

        // Check if server is in a resizable state
        if let status = server.status, !["ACTIVE", "SHUTOFF"].contains(status) {
            statusMessage = "Server '\(serverName)' must be ACTIVE or SHUTOFF to resize (current: \(status))"
            return
        }

        // Show resize dialog and get flavor selection
        statusMessage = "DEBUG: Showing resize dialog for \(serverName)"
        await draw(screen: screen)

        guard let selectedFlavorId = await showResizeDialog(server: server, screen: screen) else {
            statusMessage = "Server resize cancelled"
            return
        }

        print("DEBUG: Selected flavor ID for resize: \(selectedFlavorId)")
        statusMessage = "DEBUG: Selected flavor \(selectedFlavorId), calling API..."
        await draw(screen: screen)

        // Show resize in progress
        statusMessage = "Resizing server '\(serverName)'..."
        await draw(screen: screen) // Refresh UI to show progress message

        do {
            try await client.resizeServer(id: server.id, flavorRef: selectedFlavorId)

            statusMessage = "Server '\(serverName)' resize initiated successfully"

            // Refresh data to get updated server status
            await refreshAllData()

        } catch let error as OTError {
            let baseMsg = "Failed to resize server '\(serverName)'"
            switch error {
            case .authenticationFailed:
                statusMessage = "\(baseMsg): Authentication failed - check credentials"
            case .endpointNotFound:
                statusMessage = "\(baseMsg): Endpoint not found - check service configuration"
            case .unexpectedResponse:
                statusMessage = "\(baseMsg): Unexpected response from server"
            case .httpError(let code):
                statusMessage = "\(baseMsg): HTTP error \(code)"
            }
        } catch {
            statusMessage = "Failed to resize server '\(serverName)': \(error.localizedDescription)"
        }
    }

    private func viewServerLogs(screen: OpaquePointer?) async {
        guard currentView == .servers else { return }

        let resourceResolver = createResourceResolver()
        let filteredServers = ResourceFilters.filterServers(cachedServers, query: searchQuery, getServerIP: resourceResolver.getServerIP)
        guard selectedIndex < filteredServers.count else {
            statusMessage = "No server selected"
            return
        }

        let server = filteredServers[selectedIndex]
        let serverName = server.name ?? "Unnamed Server"

        statusMessage = "Fetching console logs for '\(serverName)'..."
        await draw(screen: screen)

        do {
            let consoleOutput = try await client.getConsoleOutput(id: server.id)
            await showConsoleOutputDialog(serverName: serverName, output: consoleOutput, screen: screen)
            // Redraw the main interface after closing the console dialog
            statusMessage = "Console logs closed"
            await draw(screen: screen)
        } catch let error as OTError {
            let baseMsg = "Failed to get console output for '\(serverName)'"
            switch error {
            case .authenticationFailed:
                statusMessage = "\(baseMsg): Authentication failed - check credentials"
            case .endpointNotFound:
                statusMessage = "\(baseMsg): Endpoint not found - check service configuration"
            case .unexpectedResponse:
                statusMessage = "\(baseMsg): Unexpected response from server"
            case .httpError(let code):
                if code == 400 {
                    statusMessage = "\(baseMsg): Bad request (server may not support console output)"
                } else if code == 404 {
                    statusMessage = "\(baseMsg): Server not found"
                } else {
                    statusMessage = "\(baseMsg): HTTP error \(code)"
                }
            }
        } catch {
            statusMessage = "Failed to get console output for '\(serverName)': \(error.localizedDescription)"
        }
    }

    private func startServer(screen: OpaquePointer?) async {
        guard currentView == .servers else { return }

        let resourceResolver = createResourceResolver()
        let filteredServers = ResourceFilters.filterServers(cachedServers, query: searchQuery, getServerIP: resourceResolver.getServerIP)
        guard selectedIndex < filteredServers.count else {
            statusMessage = "No server selected"
            return
        }

        let server = filteredServers[selectedIndex]
        let serverName = server.name ?? "Unnamed Server"

        statusMessage = "Starting server '\(serverName)'..."
        await draw(screen: screen)

        do {
            try await client.startServer(id: server.id)
            statusMessage = "Server '\(serverName)' start initiated successfully"

            // Refresh server data to update status
            await refreshAllData()
        } catch let error as OTError {
            let baseMsg = "Failed to start server '\(serverName)'"
            switch error {
            case .authenticationFailed:
                statusMessage = "\(baseMsg): Authentication failed - check credentials"
            case .endpointNotFound:
                statusMessage = "\(baseMsg): Endpoint not found - check service configuration"
            case .unexpectedResponse:
                statusMessage = "\(baseMsg): Unexpected response from server"
            case .httpError(let code):
                if code == 409 {
                    statusMessage = "\(baseMsg): Server cannot be started (current state conflict)"
                } else if code == 404 {
                    statusMessage = "\(baseMsg): Server not found"
                } else {
                    statusMessage = "\(baseMsg): HTTP error \(code)"
                }
            }
        } catch {
            statusMessage = "Failed to start server '\(serverName)': \(error.localizedDescription)"
        }
    }

    private func stopServer(screen: OpaquePointer?) async {
        guard currentView == .servers else { return }

        let resourceResolver = createResourceResolver()
        let filteredServers = ResourceFilters.filterServers(cachedServers, query: searchQuery, getServerIP: resourceResolver.getServerIP)
        guard selectedIndex < filteredServers.count else {
            statusMessage = "No server selected"
            return
        }

        let server = filteredServers[selectedIndex]
        let serverName = server.name ?? "Unnamed Server"

        statusMessage = "Stopping server '\(serverName)'..."
        await draw(screen: screen)

        do {
            try await client.stopServer(id: server.id)
            statusMessage = "Server '\(serverName)' stop initiated successfully"

            // Refresh server data to update status
            await refreshAllData()
        } catch let error as OTError {
            let baseMsg = "Failed to stop server '\(serverName)'"
            switch error {
            case .authenticationFailed:
                statusMessage = "\(baseMsg): Authentication failed - check credentials"
            case .endpointNotFound:
                statusMessage = "\(baseMsg): Endpoint not found - check service configuration"
            case .unexpectedResponse:
                statusMessage = "\(baseMsg): Unexpected response from server"
            case .httpError(let code):
                if code == 409 {
                    statusMessage = "\(baseMsg): Server cannot be stopped (current state conflict)"
                } else if code == 404 {
                    statusMessage = "\(baseMsg): Server not found"
                } else {
                    statusMessage = "\(baseMsg): HTTP error \(code)"
                }
            }
        } catch {
            statusMessage = "Failed to stop server '\(serverName)': \(error.localizedDescription)"
        }
    }

    private func manageServerSecurityGroups(screen: OpaquePointer?) async {
        guard currentView == .servers else { return }

        let resourceResolver = createResourceResolver()
        let filteredServers = ResourceFilters.filterServers(cachedServers, query: searchQuery, getServerIP: resourceResolver.getServerIP)
        guard selectedIndex < filteredServers.count else {
            statusMessage = "No server selected"
            return
        }

        let server = filteredServers[selectedIndex]

        // Initialize the security group form
        securityGroupForm.selectedServer = server
        securityGroupForm.reset()
        securityGroupForm.isLoading = true

        // Switch to security group management view
        changeView(to: .serverSecurityGroups, resetSelection: false)
        await draw(screen: screen)

        // Load security groups data
        do {
            async let serverSecurityGroups = client.getServerSecurityGroups(serverID: server.id)
            async let allSecurityGroups = client.listSecurityGroups()

            securityGroupForm.serverSecurityGroups = try await serverSecurityGroups
            securityGroupForm.availableSecurityGroups = try await allSecurityGroups
            securityGroupForm.isLoading = false
            securityGroupForm.errorMessage = nil

            statusMessage = "Security groups loaded for \(server.name ?? "server")"
        } catch let error as OTError {
            securityGroupForm.isLoading = false
            let baseMsg = "Failed to load security groups"
            switch error {
            case .authenticationFailed:
                securityGroupForm.errorMessage = "\(baseMsg): Authentication failed"
            case .endpointNotFound:
                securityGroupForm.errorMessage = "\(baseMsg): Endpoint not found"
            case .unexpectedResponse:
                securityGroupForm.errorMessage = "\(baseMsg): Unexpected response"
            case .httpError(let code):
                securityGroupForm.errorMessage = "\(baseMsg): HTTP error \(code)"
            }
            statusMessage = securityGroupForm.errorMessage
        } catch {
            securityGroupForm.isLoading = false
            securityGroupForm.errorMessage = "Failed to load security groups: \(error.localizedDescription)"
            statusMessage = securityGroupForm.errorMessage
        }
    }

    private func getMaxSelectionIndex() -> Int {
        let resourceResolver = createResourceResolver()

        return UIUtils.getMaxSelectionIndex(
            for: currentView,
            cachedServers: cachedServers,
            cachedNetworks: cachedNetworks,
            cachedVolumes: cachedVolumes,
            cachedImages: cachedImages,
            cachedFlavors: cachedFlavors,
            cachedKeyPairs: cachedKeyPairs,
            searchQuery: searchQuery,
            resourceResolver: resourceResolver
        )
    }

    private func createResourceResolver() -> ResourceResolver {
        return ResourceResolver(
            cachedServers: cachedServers,
            cachedNetworks: cachedNetworks,
            cachedImages: cachedImages,
            cachedFlavors: cachedFlavors,
            cachedSubnets: cachedSubnets,
            cachedSecurityGroups: cachedSecurityGroups,
            resourceNameCache: resourceNameCache,
            client: client
        )
    }

    private func openDetailView() async {
        let resourceResolver = createResourceResolver()

        switch currentView {
        case .servers:
            let filteredServers = ResourceFilters.filterServers(cachedServers, query: searchQuery, getServerIP: resourceResolver.getServerIP)
            guard selectedIndex < filteredServers.count else { return }
            selectedResource = filteredServers[selectedIndex]
            changeView(to: .serverDetail, resetSelection: false)
        case .networks:
            let filteredNetworks = ResourceFilters.filterNetworks(cachedNetworks, query: searchQuery)
            guard selectedIndex < filteredNetworks.count else { return }
            selectedResource = filteredNetworks[selectedIndex]
            changeView(to: .networkDetail, resetSelection: false)
        case .volumes:
            let filteredVolumes = ResourceFilters.filterVolumes(cachedVolumes, query: searchQuery)
            guard selectedIndex < filteredVolumes.count else { return }
            selectedResource = filteredVolumes[selectedIndex]
            changeView(to: .volumeDetail, resetSelection: false)
        case .images:
            let filteredImages = ResourceFilters.filterImages(cachedImages, query: searchQuery)
            guard selectedIndex < filteredImages.count else { return }
            selectedResource = filteredImages[selectedIndex]
            changeView(to: .imageDetail, resetSelection: false)
        case .flavors:
            let filteredFlavors = ResourceFilters.filterFlavors(cachedFlavors, query: searchQuery)
            guard selectedIndex < filteredFlavors.count else { return }
            selectedResource = filteredFlavors[selectedIndex]
            changeView(to: .flavorDetail, resetSelection: false)
        case .keyPairs:
            let filteredKeyPairs = ResourceFilters.filterKeyPairs(cachedKeyPairs, query: searchQuery)
            guard selectedIndex < filteredKeyPairs.count else { return }
            selectedResource = filteredKeyPairs[selectedIndex]
            changeView(to: .keyPairDetail, resetSelection: false)
        default:
            break
        }
    }

    private func refreshAllData() async {
        // Fetch servers
        do {
            cachedServers = try await client.listServers()
        } catch {
            cachedServers = []
        }

        // Fetch networks
        do {
            cachedNetworks = try await client.listNetworks()
        } catch {
            cachedNetworks = []
        }

        // Fetch volumes
        do {
            cachedVolumes = try await client.listVolumes()
        } catch {
            cachedVolumes = []
        }

        // Fetch images
        do {
            cachedImages = try await client.listImages()
        } catch {
            cachedImages = []
        }

        // Fetch flavors
        do {
            cachedFlavors = try await client.listFlavors()
            // Sort flavors by name for better UX
            cachedFlavors.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            cachedFlavors = []
        }

        // Fetch subnets
        do {
            cachedSubnets = try await client.listSubnets()
        } catch {
            cachedSubnets = []
        }

        // Fetch security groups
        do {
            cachedSecurityGroups = try await client.listSecurityGroups()
        } catch {
            cachedSecurityGroups = []
        }

        // Fetch key pairs
        do {
            cachedKeyPairs = try await client.listKeyPairs()
        } catch {
            cachedKeyPairs = []
        }

        // Populate resource name cache
        resourceNameCache.clear()

        // Cache server names
        for server in cachedServers {
            resourceNameCache.setServerName(server.id, name: server.name ?? "Unnamed Server")
        }

        // Cache network names
        for network in cachedNetworks {
            resourceNameCache.setNetworkName(network.id, name: network.name)
        }

        // Cache image names
        for image in cachedImages {
            if let name = image.name {
                resourceNameCache.setImageName(image.id, name: name)
            }
        }

        // Cache flavor names
        for flavor in cachedFlavors {
            resourceNameCache.setFlavorName(flavor.id, name: flavor.name)
        }

        // Cache subnet names
        for subnet in cachedSubnets {
            if let name = subnet.name {
                resourceNameCache.setSubnetName(subnet.id, name: name)
            }
        }

        // Note: Security group caching removed since they're not directly displayed
        // but the infrastructure remains for future use

        // Fetch quotas
        do {
            cachedComputeLimits = try await client.getComputeLimits()
        } catch {
            cachedComputeLimits = nil
        }

        do {
            cachedComputeQuotas = try await client.getComputeQuotas()
        } catch {
            cachedComputeQuotas = nil
        }

        do {
            cachedNetworkQuotas = try await client.getNetworkQuotas()
        } catch {
            cachedNetworkQuotas = nil
        }

        do {
            cachedVolumeQuotas = try await client.getVolumeQuotas()
        } catch {
            cachedVolumeQuotas = nil
        }

        // Update resource counts
        resourceCounts.servers = cachedServers.count
        resourceCounts.networks = cachedNetworks.count
        resourceCounts.volumes = cachedVolumes.count
        resourceCounts.images = cachedImages.count
        resourceCounts.activeServers = cachedServers.filter { $0.status?.lowercased() == "active" }.count
        resourceCounts.errorServers = cachedServers.filter {
            $0.status?.lowercased().contains("error") == true
        }.count

        // Build topology graph after all data is loaded
        lastTopology = await TopologyGraphBuilder.build(client: client)
    }

    private func refreshTopology() async {
        statusMessage = "Refreshing topology..."
        lastTopology = await TopologyGraphBuilder.build(client: client)
        statusMessage = "Topology refreshed"
    }

    private func exportTopology() async {
        guard let topology = lastTopology else {
            statusMessage = "No topology data to export"
            return
        }

        do {
            var content: [String] = []
            content.append("OpenStack Topology Export")
            content.append("Generated: \(Date())")
            content.append("")
            content.append("=== ASCII Diagram ===")
            content.append(contentsOf: topology.asciiDiagram)
            content.append("")
            content.append("=== Detailed Lines ===")
            content.append(contentsOf: topology.lines)

            let fileContent = content.joined(separator: "\n")
            try fileContent.write(toFile: "topology.txt", atomically: true, encoding: .utf8)
            statusMessage = "Topology exported to topology.txt"
        } catch {
            statusMessage = "Failed to export topology: \(error.localizedDescription)"
        }
    }

    private func purgeCache() {
        // Clear all cached data
        cachedServers.removeAll()
        cachedNetworks.removeAll()
        cachedVolumes.removeAll()
        cachedImages.removeAll()
        cachedFlavors.removeAll()
        cachedSubnets.removeAll()
        cachedSecurityGroups.removeAll()
        cachedKeyPairs.removeAll()

        // Clear quota caches
        cachedComputeLimits = nil
        cachedComputeQuotas = nil
        cachedNetworkQuotas = nil
        cachedVolumeQuotas = nil

        // Clear resource name cache
        resourceNameCache.clear()

        // Clear topology cache
        lastTopology = nil

        // Reset resource counts
        resourceCounts = ResourceCounts()

        statusMessage = "All caches purged"
    }

    private func colorPair(_ n: Int32) -> Int32 { n << 8 }

    private func draw(screen: OpaquePointer?) async {
        werase(screen)

        // Draw layout components in proper order
        drawHeader(screen: screen)
        drawSidebar(screen: screen)
        await drawMainPanel(screen: screen)
        drawStatusBar(screen: screen)

        wrefresh(screen)
    }

    private func drawHeader(screen: OpaquePointer?) {
        // Top header bar with branding and system info
        wattron(screen, colorPair(1))
        wmove(screen, 0, 0)

        let timeStr = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let headerLeft = "* OTUI v1.0 - OpenStack Terminal Interface"
        let headerRight = "Region: \(client.region) │ Project: \(client.project) │ \(timeStr)"

        // Left side
        waddstr(screen, headerLeft)

        // Right side aligned
        let rightStart = screenCols - Int32(headerRight.count) - 1
        if rightStart > Int32(headerLeft.count) + 2 {
            wmove(screen, 0, rightStart)
            waddstr(screen, headerRight)
        }

        // Fill the rest of the line
        wmove(screen, 0, 0)
        for _ in 0..<screenCols {
            waddch(screen, UInt32(" ".first?.asciiValue ?? 32))
        }
        wmove(screen, 0, 0)
        waddstr(screen, headerLeft)
        if rightStart > Int32(headerLeft.count) + 2 {
            wmove(screen, 0, rightStart)
            waddstr(screen, headerRight)
        }

        wattroff(screen, colorPair(1))

        // Separator line
        wattron(screen, colorPair(8))
        wmove(screen, 1, 0)
        for _ in 0..<screenCols {
            waddch(screen, UInt32("─".utf8.first ?? 45))
        }
        wattroff(screen, colorPair(8))
    }

    private func drawSidebar(screen: OpaquePointer?) {
        let sidebarWidth: Int32 = 25

        // Clear and draw sidebar background with explicit bounds
        wattron(screen, colorPair(6))
        for row in 2..<min(screenRows-2, screenRows-2) {
            wmove(screen, row, 0)
            // Clear the entire sidebar row first
            for _ in 0..<sidebarWidth {
                waddch(screen, UInt32(" ".first?.asciiValue ?? 32))
            }
        }
        wattroff(screen, colorPair(6))

        // Navigation section with bounds checking
        var navRow: Int32 = 5
        if screenRows > 5 && screenCols > 24 {
            wattron(screen, colorPair(2) )
            wmove(screen, 3, 2)
            waddstr(screen, "Navigation")
            wattroff(screen, colorPair(2) )

            let views = ViewMode.allCases
            navRow = 5
            for view in views {
                if view.key.isEmpty { continue } // Skip detail views
                if navRow >= screenRows - 8 { break } // Leave space for Resource Summary

                wmove(screen, navRow, 2)
                let navText = view == currentView ? "► \(view.key) \(view.title)" : "  \(view.key) \(view.title)"
                let maxNavWidth = Int(sidebarWidth - 4) // Leave margin
                let truncatedText = String(navText.prefix(maxNavWidth))

                if view == currentView {
                    wattron(screen, colorPair(3) )
                    waddstr(screen, truncatedText)
                    wattroff(screen, colorPair(3) )
                } else {
                    wattron(screen, colorPair(6))
                    waddstr(screen, truncatedText)
                    wattroff(screen, colorPair(6))
                }
                navRow += 1
            }
        }        // Resource counts section with bounds checking
        let resourceSummaryRow: Int32 = max(16, navRow + 2)
        if resourceSummaryRow < screenRows - 12 && screenCols > 24 {
            wattron(screen, colorPair(2) )
            wmove(screen, resourceSummaryRow, 2)
            waddstr(screen, "Resource Summary")
            wattroff(screen, colorPair(2) )

            let countsY = resourceSummaryRow + 1
            let maxSummaryWidth = Int(sidebarWidth - 4)

            wattron(screen, colorPair(6))

            // Only draw if we have space
            if countsY + 10 < screenRows - 2 {
                wmove(screen, countsY, 2)
                let serversText = String("Servers:   \(resourceCounts.servers)".prefix(maxSummaryWidth))
                waddstr(screen, serversText)

                wmove(screen, countsY + 1, 2)
                let activeText = String("  Active:  \(resourceCounts.activeServers)".prefix(maxSummaryWidth))
                waddstr(screen, activeText)

                wmove(screen, countsY + 2, 2)
                if resourceCounts.errorServers > 0 {
                    wattroff(screen, colorPair(6))
                    wattron(screen, colorPair(7))
                }
                let errorsText = String("  Errors:  \(resourceCounts.errorServers)".prefix(maxSummaryWidth))
                waddstr(screen, errorsText)
                if resourceCounts.errorServers > 0 {
                    wattroff(screen, colorPair(7))
                    wattron(screen, colorPair(6))
                }

                wmove(screen, countsY + 3, 2)
                let networksText = String("Networks:  \(resourceCounts.networks)".prefix(maxSummaryWidth))
                waddstr(screen, networksText)

                wmove(screen, countsY + 4, 2)
                let volumesText = String("Volumes:   \(resourceCounts.volumes)".prefix(maxSummaryWidth))
                waddstr(screen, volumesText)

                wmove(screen, countsY + 5, 2)
                let imagesText = String("Images:    \(resourceCounts.images)".prefix(maxSummaryWidth))
                waddstr(screen, imagesText)

                wattroff(screen, colorPair(6))

                // Status indicators
                wmove(screen, countsY + 7, 2)
                wattron(screen, colorPair(2) )
                waddstr(screen, "Status")
                wattroff(screen, colorPair(2) )

                wmove(screen, countsY + 9, 2)
                wattron(screen, autoRefresh ? colorPair(5) : colorPair(7))
                let autoRefreshText = String("Auto-refresh: \(autoRefresh ? "ON" : "OFF")".prefix(maxSummaryWidth))
                waddstr(screen, autoRefreshText)
                wattroff(screen, autoRefresh ? colorPair(5) : colorPair(7))

                wmove(screen, countsY + 10, 2)
                wattron(screen, colorPair(6))
                let lastRefreshStr = DateFormatter.localizedString(from: lastRefresh, dateStyle: .none, timeStyle: .medium)
                let lastRefreshText = String("Last: \(lastRefreshStr)".prefix(maxSummaryWidth))
                waddstr(screen, lastRefreshText)
                wattroff(screen, colorPair(6))
            }
        }

        // Vertical separator
        wattron(screen, colorPair(8))
        for row in 2..<screenRows-2 {
            wmove(screen, row, sidebarWidth)
            waddch(screen, UInt32("│".utf8.first ?? 124))
        }
        wattroff(screen, colorPair(8))
    }

    private func drawMainPanel(screen: OpaquePointer?) async {
        let sidebarWidth: Int32 = 25
        let mainStartCol: Int32 = sidebarWidth + 2  // Ensure clear separation from sidebar
        let mainWidth = max(10, screenCols - mainStartCol - 1)  // Minimum width check
        let mainStartRow: Int32 = 2
        let mainHeight = max(5, screenRows - mainStartRow - 2)  // Minimum height check

        // Only draw if we have sufficient space
        guard mainWidth > 10 && mainHeight > 5 else { return }

        switch currentView {
        case .dashboard:
            await DashboardView.draw(screen: screen, startRow: mainStartRow, startCol: mainStartCol, width: mainWidth, height: mainHeight, resourceCounts: resourceCounts, cachedServers: cachedServers, cachedNetworks: cachedNetworks, cachedVolumes: cachedVolumes, cachedComputeLimits: cachedComputeLimits, cachedNetworkQuotas: cachedNetworkQuotas, cachedVolumeQuotas: cachedVolumeQuotas)
        case .servers:
            await ServerViews.drawDetailedServerList(screen: screen, startRow: mainStartRow, startCol: mainStartCol, width: mainWidth, height: mainHeight, cachedServers: cachedServers, searchQuery: searchQuery, scrollOffset: scrollOffset, selectedIndex: selectedIndex, resourceNameCache: resourceNameCache)
        case .networks:
            await NetworkViews.drawDetailedNetworkList(screen: screen, startRow: mainStartRow, startCol: mainStartCol, width: mainWidth, height: mainHeight, cachedNetworks: cachedNetworks, searchQuery: searchQuery, scrollOffset: scrollOffset, selectedIndex: selectedIndex)
        case .volumes:
            await VolumeViews.drawDetailedVolumeList(screen: screen, startRow: mainStartRow, startCol: mainStartCol, width: mainWidth, height: mainHeight, cachedVolumes: cachedVolumes, searchQuery: searchQuery, scrollOffset: scrollOffset, selectedIndex: selectedIndex)
        case .images:
            await ImageViews.drawDetailedImageList(screen: screen, startRow: mainStartRow, startCol: mainStartCol, width: mainWidth, height: mainHeight, cachedImages: cachedImages, searchQuery: searchQuery, scrollOffset: scrollOffset, selectedIndex: selectedIndex)
        case .flavors:
            await FlavorViews.drawDetailedFlavorList(screen: screen, startRow: mainStartRow, startCol: mainStartCol, width: mainWidth, height: mainHeight, cachedFlavors: cachedFlavors, searchQuery: searchQuery, scrollOffset: scrollOffset, selectedIndex: selectedIndex)
        case .keyPairs:
            await KeyPairViews.drawDetailedKeyPairList(screen: screen, startRow: mainStartRow, startCol: mainStartCol, width: mainWidth, height: mainHeight, cachedKeyPairs: cachedKeyPairs, searchQuery: searchQuery, scrollOffset: scrollOffset, selectedIndex: selectedIndex)
        case .keyPairDetail:
            if let keyPair = selectedResource as? KeyPair {
                await KeyPairViews.drawKeyPairDetail(screen: screen, startRow: mainStartRow, startCol: mainStartCol, width: mainWidth, height: mainHeight, keyPair: keyPair)
            }
        case .topology:
            await TopologyViews.drawTopologyView(screen: screen, startRow: mainStartRow, startCol: mainStartCol, width: mainWidth, height: mainHeight, topology: lastTopology)
        case .serverDetail:
            if let server = selectedResource as? Server {
                await ServerViews.drawServerDetail(screen: screen, startRow: mainStartRow, startCol: mainStartCol, width: mainWidth, height: mainHeight, server: server, client: client, resourceNameCache: resourceNameCache)
            }
        case .networkDetail:
            if let network = selectedResource as? Network {
                await NetworkViews.drawNetworkDetail(screen: screen, startRow: mainStartRow, startCol: mainStartCol, width: mainWidth, height: mainHeight, network: network)
            }
        case .volumeDetail:
            if let volume = selectedResource as? Volume {
                await VolumeViews.drawVolumeDetail(screen: screen, startRow: mainStartRow, startCol: mainStartCol, width: mainWidth, height: mainHeight, volume: volume)
            }
        case .imageDetail:
            if let image = selectedResource as? Image {
                await ImageViews.drawImageDetail(screen: screen, startRow: mainStartRow, startCol: mainStartCol, width: mainWidth, height: mainHeight, image: image)
            }
        case .flavorDetail:
            if let flavor = selectedResource as? Flavor {
                await FlavorViews.drawFlavorDetail(screen: screen, startRow: mainStartRow, startCol: mainStartCol, width: mainWidth, height: mainHeight, flavor: flavor)
            }
        case .serverCreate:
            await MiscViews.drawServerCreate(screen: screen, startRow: mainStartRow, startCol: mainStartCol, width: mainWidth, height: mainHeight, serverCreateForm: serverCreateForm, cachedImages: cachedImages, cachedFlavors: cachedFlavors, cachedNetworks: cachedNetworks, cachedSecurityGroups: cachedSecurityGroups, cachedKeyPairs: cachedKeyPairs, cachedVolumes: cachedVolumes)
        case .serverSecurityGroups:
            await SecurityGroupManagementView.draw(screen: screen, startRow: mainStartRow, startCol: mainStartCol, width: mainWidth, height: mainHeight, form: securityGroupForm)
        case .help:
            await MiscViews.drawHelp(screen: screen, startRow: mainStartRow, startCol: mainStartCol, width: mainWidth, height: mainHeight, scrollOffset: helpScrollOffset)
        }
    }

    // REMOVED: drawServerDetail method - now in ServerViews module

    private func drawStatusBar(screen: OpaquePointer?) {
        let statusRow = screenRows - 2

        // Status bar background
        wattron(screen, colorPair(4))
        wmove(screen, statusRow, 0)
        for _ in 0..<screenCols {
            waddch(screen, UInt32(" ".first?.asciiValue ?? 32))
        }
        wmove(screen, statusRow, 1)

        if let status = statusMessage {
            waddstr(screen, "Status: \(status)")
        } else {
            waddstr(screen, "Ready")
        }
        wattroff(screen, colorPair(4))

        // Help line
        wmove(screen, screenRows - 1, 0)
        wattron(screen, colorPair(6))
        for _ in 0..<screenCols {
            waddch(screen, UInt32(" ".first?.asciiValue ?? 32))
        }
        wmove(screen, screenRows - 1, 1)

        // Dynamic help line based on current view
        let helpText = getDynamicHelpText()
        let maxWidth = Int(screenCols) - 2
        let truncatedText = String(helpText.prefix(maxWidth))
        waddstr(screen, truncatedText)
        wattroff(screen, colorPair(6))
    }

    // Helper functions
    private func changeView(to newView: ViewMode, resetSelection: Bool = true) {
        if currentView != newView && currentView != .help {
            previousView = currentView
        }
        currentView = newView
        if resetSelection {
            scrollOffset = 0
            selectedIndex = 0
            selectedResource = nil
        }
    }

    private func getDynamicHelpText() -> String {
        return UIUtils.getDynamicHelpText(for: currentView)
    }

    private func getServerIP(_ server: Server) -> String? {
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

    private func prompt(_ text: String, screen: OpaquePointer?) -> String? {
        echo()
        nodelay(screen, false)
        defer {
            noecho()
            nodelay(screen, true)
        }

        let promptLine = screenRows - 2
        wmove(screen, promptLine, 0)
        wclrtoeol(screen)
        wattron(screen, colorPair(2))
        waddstr(screen, text)
        wattroff(screen, colorPair(2))

        let buf = UnsafeMutablePointer<CChar>.allocate(capacity: 256)
        defer { buf.deallocate() }
        wgetnstr(screen, buf, 255)

        wmove(screen, promptLine, 0)
        wclrtoeol(screen)

        return String(cString: buf)
    }

    private func confirmDelete(_ itemName: String, screen: OpaquePointer?) -> Bool {
        nodelay(screen, false)
        defer {
            nodelay(screen, true)
        }

        let promptLine = screenRows - 2
        wmove(screen, promptLine, 0)
        wclrtoeol(screen)
        wattron(screen, colorPair(7)) // Red color for warning
        waddstr(screen, "Delete '\(itemName)'? Press Y to confirm, any other key to cancel: ")
        wattroff(screen, colorPair(7))

        let ch = wgetch(screen)

        wmove(screen, promptLine, 0)
        wclrtoeol(screen)

        // Only Y (both uppercase and lowercase) confirms deletion
        return ch == Int32(89) || ch == Int32(121) // 'Y' or 'y'
    }

    private func confirmRestart(_ itemName: String, screen: OpaquePointer?) -> Bool {
        nodelay(screen, false)
        defer {
            nodelay(screen, true)
        }

        let promptLine = screenRows - 2
        wmove(screen, promptLine, 0)
        wclrtoeol(screen)
        wattron(screen, colorPair(2)) // Yellow color for warning
        waddstr(screen, "Restart '\(itemName)'? Press Y to confirm, any other key to cancel: ")
        wattroff(screen, colorPair(2))

        let ch = wgetch(screen)

        wmove(screen, promptLine, 0)
        wclrtoeol(screen)

        // Only Y (both uppercase and lowercase) confirms restart
        return ch == Int32(89) || ch == Int32(121) // 'Y' or 'y'
    }

    private func showResizeDialog(server: Server, screen: OpaquePointer?) async -> String? {
        guard !cachedFlavors.isEmpty else {
            statusMessage = "No flavors available for resize"
            return nil
        }

        print("DEBUG: Opening resize dialog with \(cachedFlavors.count) flavors available")
        for (index, flavor) in cachedFlavors.enumerated() {
            print("DEBUG: Flavor \(index): \(flavor.name) (ID: \(flavor.id))")
        }

        // Reset resize form
        serverResizeForm.reset()

        // Disable nodelay for dialog interaction
        nodelay(screen, false)
        defer {
            nodelay(screen, true)
        }

        while true {
            // Clear screen
            clear()

            // Draw the resize dialog
            let dialogWidth: Int32 = 80
            let dialogHeight: Int32 = 20
            let dialogStartRow = (screenRows - dialogHeight) / 2
            let dialogStartCol = (screenCols - dialogWidth) / 2

            await MiscViews.drawServerResizeDialog(
                screen: screen,
                startRow: dialogStartRow,
                startCol: dialogStartCol,
                width: dialogWidth,
                height: dialogHeight,
                server: server,
                cachedFlavors: cachedFlavors,
                serverResizeForm: serverResizeForm
            )

            refresh()

            let ch = wgetch(screen)

            switch ch {
            case Int32(27): // ESC - Cancel
                return nil
            case Int32(10), Int32(13): // ENTER - Confirm resize
                if serverResizeForm.selectedFlavorIndex < cachedFlavors.count {
                    let selectedFlavor = cachedFlavors[serverResizeForm.selectedFlavorIndex]

                    // Show final confirmation
                    let flavorName = selectedFlavor.name
                    wmove(screen, screenRows - 2, 0)
                    wclrtoeol(screen)
                    wattron(screen, colorPair(5)) // Red for warning
                    waddstr(screen, "Resize to '\(flavorName)'? Server will be temporarily shutdown. Y to confirm: ")
                    wattroff(screen, colorPair(5))

                    let confirmCh = wgetch(screen)
                    if confirmCh == Int32(89) || confirmCh == Int32(121) { // 'Y' or 'y'
                        waddstr(screen, "Confirmed resize to flavor: \(selectedFlavor.id)")
                        return selectedFlavor.id
                    } else {
                        waddstr(screen, "Declined resize confirmation")
                    }
                }
            case Int32(260): // KEY_LEFT - Previous flavor
                if cachedFlavors.count > 0 {
                    serverResizeForm.selectedFlavorIndex = max(0, serverResizeForm.selectedFlavorIndex - 1)
                }
            case Int32(261): // KEY_RIGHT - Next flavor
                if cachedFlavors.count > 0 {
                    serverResizeForm.selectedFlavorIndex = min(cachedFlavors.count - 1, serverResizeForm.selectedFlavorIndex + 1)
                }
            default:
                break
            }
        }
    }

    private func showConsoleOutputDialog(serverName: String, output: String, screen: OpaquePointer?) async {
        // Disable nodelay for dialog interaction
        nodelay(screen, false)
        defer {
            nodelay(screen, true)
        }

        var verticalScrollOffset = 0
        var horizontalScrollOffset = 0
        let lines = output.components(separatedBy: .newlines)
        let totalLines = lines.count

        // Calculate maximum line width for horizontal scrolling
        let maxLineWidth = lines.map { $0.count }.max() ?? 0

        while true {
            // Clear screen
            clear()

            // Full screen dialog - use entire screen
            let dialogWidth = screenCols
            let dialogHeight = screenRows
            let dialogStartRow: Int32 = 0
            let dialogStartCol: Int32 = 0

            // Draw title bar at top
            wmove(screen, 0, 0)
            wattron(screen, colorPair(2)) // Bright color for title
            let title = "Console Output: \(serverName)"
            let titlePadding = String(repeating: " ", count: Int(screenCols) - title.count)
            waddstr(screen, title + titlePadding)
            wattroff(screen, colorPair(2))

            // Draw help bar at bottom
            wmove(screen, screenRows - 1, 0)
            wattron(screen, colorPair(3))
            let helpText = "UP/DOWN,j/k:scroll vertical  LEFT/RIGHT,h/l:scroll horizontal  PgUp/PgDn,Home/End  ESC:close"
            let helpPadding = String(repeating: " ", count: Int(screenCols) - helpText.count)
            waddstr(screen, helpText + helpPadding)
            wattroff(screen, colorPair(3))

            // Draw console output content (full screen minus title and help bars)
            let contentHeight = Int(dialogHeight - 2) // Leave space for title and help bars
            let contentWidth = Int(dialogWidth)

            for i in 0..<contentHeight {
                let lineIndex = verticalScrollOffset + i
                if lineIndex < totalLines {
                    let fullLine = lines[lineIndex]
                    // Apply horizontal scrolling
                    let startPos = horizontalScrollOffset
                    let endPos = min(startPos + contentWidth, fullLine.count)

                    let visibleLine: String
                    if startPos < fullLine.count {
                        let startIndex = fullLine.index(fullLine.startIndex, offsetBy: startPos)
                        let endIndex = fullLine.index(fullLine.startIndex, offsetBy: endPos)
                        visibleLine = String(fullLine[startIndex..<endIndex])
                    } else {
                        visibleLine = ""
                    }

                    wmove(screen, dialogStartRow + 1 + Int32(i), dialogStartCol)
                    waddstr(screen, visibleLine)

                    // Clear the rest of the line to avoid artifacts
                    wclrtoeol(screen)
                }
            }

            // Draw vertical scroll indicator on the right edge
            if totalLines > contentHeight {
                let scrollPos = Int32((Double(verticalScrollOffset) / Double(totalLines - contentHeight)) * Double(contentHeight - 1))
                wmove(screen, 1 + scrollPos, screenCols - 1)
                wattron(screen, colorPair(6))
                waddch(screen, CUnsignedInt(9608)) // Full block character for scroll indicator
                wattroff(screen, colorPair(6))
            }

            // Draw horizontal scroll indicator on the bottom of content area
            if maxLineWidth > contentWidth {
                let maxHorizontalScroll = maxLineWidth - contentWidth
                if maxHorizontalScroll > 0 {
                    let scrollPos = Int32((Double(horizontalScrollOffset) / Double(maxHorizontalScroll)) * Double(contentWidth - 10))
                    wmove(screen, screenRows - 2, scrollPos)
                    wattron(screen, colorPair(6))
                    waddstr(screen, "<------>")
                    wattroff(screen, colorPair(6))
                }
            }

            refresh()

            let ch = wgetch(screen)

            switch ch {
            case Int32(27): // ESC - Close dialog
                // Clear screen thoroughly and trigger a redraw when exiting
                erase()
                clear()
                refresh()
                return
            case Int32(259), Int32(107): // UP or 'k' - Scroll up
                verticalScrollOffset = max(0, verticalScrollOffset - 1)
            case Int32(258), Int32(106): // DOWN or 'j' - Scroll down
                verticalScrollOffset = min(max(0, totalLines - contentHeight), verticalScrollOffset + 1)
            case Int32(260), Int32(104): // LEFT or 'h' - Scroll left
                horizontalScrollOffset = max(0, horizontalScrollOffset - 5)
            case Int32(261), Int32(108): // RIGHT or 'l' - Scroll right
                let maxHorizontalScroll = max(0, maxLineWidth - contentWidth)
                horizontalScrollOffset = min(maxHorizontalScroll, horizontalScrollOffset + 5)
            case Int32(338): // PAGE_DOWN
                verticalScrollOffset = min(max(0, totalLines - contentHeight), verticalScrollOffset + contentHeight)
            case Int32(339): // PAGE_UP
                verticalScrollOffset = max(0, verticalScrollOffset - contentHeight)
            case Int32(262): // HOME
                verticalScrollOffset = 0
                horizontalScrollOffset = 0
            case Int32(360): // END
                verticalScrollOffset = max(0, totalLines - contentHeight)
                let maxHorizontalScroll = max(0, maxLineWidth - contentWidth)
                horizontalScrollOffset = maxHorizontalScroll
            default:
                break
            }
        }
    }
}