import Foundation

@MainActor
final class ResourceNameCache {
    private var flavorNames: [String: String] = [:]
    private var imageNames: [String: String] = [:]
    private var serverNames: [String: String] = [:]
    private var networkNames: [String: String] = [:]
    private var subnetNames: [String: String] = [:]
    private var securityGroupNames: [String: String] = [:]

    func setFlavorName(_ id: String, name: String) {
        flavorNames[id] = name
    }

    func setImageName(_ id: String, name: String) {
        imageNames[id] = name
    }

    func setServerName(_ id: String, name: String) {
        serverNames[id] = name
    }

    func setNetworkName(_ id: String, name: String) {
        networkNames[id] = name
    }

    func setSubnetName(_ id: String, name: String) {
        subnetNames[id] = name
    }

    func setSecurityGroupName(_ id: String, name: String) {
        securityGroupNames[id] = name
    }

    func getFlavorName(_ id: String) -> String? {
        return flavorNames[id]
    }

    func getImageName(_ id: String) -> String? {
        return imageNames[id]
    }

    func getServerName(_ id: String) -> String? {
        return serverNames[id]
    }

    func getNetworkName(_ id: String) -> String? {
        return networkNames[id]
    }

    func getSubnetName(_ id: String) -> String? {
        return subnetNames[id]
    }

    func getSecurityGroupName(_ id: String) -> String? {
        return securityGroupNames[id]
    }

    func clear() {
        flavorNames.removeAll()
        imageNames.removeAll()
        serverNames.removeAll()
        networkNames.removeAll()
        subnetNames.removeAll()
        securityGroupNames.removeAll()
    }
}