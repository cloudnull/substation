import Foundation

enum ViewMode: CaseIterable {
    case dashboard, servers, networks, volumes, images, flavors, topology
    case serverDetail, networkDetail, volumeDetail, imageDetail, flavorDetail
    case serverCreate, keyPairs, keyPairDetail, help, serverSecurityGroups, serverNetworkInterfaces

    var title: String {
        switch self {
            case .dashboard: return "Dashboard"
            case .servers: return "Servers"
            case .networks: return "Networks"
            case .volumes: return "Volumes"
            case .images: return "Images"
            case .flavors: return "Flavors"
            case .topology: return "Topology"
            case .serverDetail: return "Server Details"
            case .networkDetail: return "Network Details"
            case .volumeDetail: return "Volume Details"
            case .imageDetail: return "Image Details"
            case .flavorDetail: return "Flavor Details"
            case .serverCreate: return "Create Server"
            case .keyPairs: return "SSH Key Pairs"
            case .keyPairDetail: return "Key Pair Details"
            case .help: return "Help"
            case .serverSecurityGroups: return "Manage Security Groups"
            case .serverNetworkInterfaces: return "Manage Network Interfaces"
        }
    }

    var key: String {
        switch self {
        case .dashboard: return "D"
        case .servers: return "S"
        case .networks: return "N"
        case .volumes: return "V"
        case .images: return "I"
        case .flavors: return "F"
        case .topology: return "T"
        case .serverDetail: return ""
        case .networkDetail: return ""
        case .volumeDetail: return ""
        case .imageDetail: return ""
        case .flavorDetail: return ""
        case .serverCreate: return ""
        case .keyPairs: return "K"
        case .keyPairDetail: return ""
        case .help: return "?"
        case .serverSecurityGroups: return ""
        case .serverNetworkInterfaces: return ""
        }
    }

    var isDetailView: Bool {
        switch self {
        case .serverDetail, .networkDetail, .volumeDetail, .imageDetail, .flavorDetail, .serverCreate, .keyPairDetail, .serverSecurityGroups, .serverNetworkInterfaces:
            return true
        default:
            return false
        }
    }

    var parentView: ViewMode {
        switch self {
        case .serverDetail: return .servers
        case .networkDetail: return .networks
        case .volumeDetail: return .volumes
        case .imageDetail: return .images
        case .flavorDetail: return .flavors
        case .serverCreate: return .servers
        case .keyPairDetail: return .keyPairs
        case .serverSecurityGroups: return .servers
        case .serverNetworkInterfaces: return .servers
        default: return self
        }
    }
}