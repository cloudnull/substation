import Foundation
import OTClient

@MainActor
struct UIUtils {

    static func getDynamicHelpText(for currentView: ViewMode) -> String {
        let baseCommands = "q:quit ↑↓:select ?:help"

        switch currentView {
        case .dashboard:
            return "\(baseCommands) S:servers N:networks V:volumes I:images F:flavors T:topology r:refresh a:auto-refresh"
        case .servers:
            return "\(baseCommands) SPACE:details B:create G:security-groups I:interfaces R:restart Z:resize S:start T:stop L:logs DEL:delete /:search ESC:back"
        case .networks:
            return "\(baseCommands) SPACE:details /:search ESC:back"
        case .volumes:
            return "\(baseCommands) SPACE:details /:search ESC:back"
        case .images:
            return "\(baseCommands) SPACE:details /:search ESC:back"
        case .flavors:
            return "\(baseCommands) SPACE:details /:search ESC:back"
        case .keyPairs:
            return "\(baseCommands) SPACE:details /:search ESC:back"
        case .topology:
            return "\(baseCommands) W:export /:search ESC:back"
        case .serverDetail, .networkDetail, .volumeDetail, .imageDetail, .flavorDetail, .keyPairDetail:
            return "\(baseCommands) ESC:back"
        case .serverCreate:
            return "\(baseCommands) TAB:navigate ←→:change ENTER:edit/create ESC:cancel"
        case .serverSecurityGroups:
            return "\(baseCommands) TAB:mode SPACE:toggle ENTER:apply ESC:back"
        case .serverNetworkInterfaces:
            return "\(baseCommands) TAB:mode SPACE:toggle ENTER:apply ESC:back"
        case .help:
            return "\(baseCommands) ESC:back"
        }
    }

    static func getMaxSelectionIndex(
        for view: ViewMode,
        cachedServers: [Server],
        cachedNetworks: [Network],
        cachedVolumes: [Volume],
        cachedImages: [Image],
        cachedFlavors: [Flavor],
        cachedKeyPairs: [KeyPair],
        searchQuery: String?,
        resourceResolver: ResourceResolver
    ) -> Int {
        switch view {
        case .servers:
            return max(0, ResourceFilters.filterServers(cachedServers, query: searchQuery, getServerIP: resourceResolver.getServerIP).count - 1)
        case .networks:
            return max(0, ResourceFilters.filterNetworks(cachedNetworks, query: searchQuery).count - 1)
        case .volumes:
            return max(0, ResourceFilters.filterVolumes(cachedVolumes, query: searchQuery).count - 1)
        case .images:
            return max(0, ResourceFilters.filterImages(cachedImages, query: searchQuery).count - 1)
        case .flavors:
            return max(0, ResourceFilters.filterFlavors(cachedFlavors, query: searchQuery).count - 1)
        case .keyPairs:
            return max(0, ResourceFilters.filterKeyPairs(cachedKeyPairs, query: searchQuery).count - 1)
        case .topology:
            // For topology view, we don't support selection navigation
            return 0
        default:
            // For detail views and others, no selection
            return 0
        }
    }
}