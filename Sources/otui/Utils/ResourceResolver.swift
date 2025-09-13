import Foundation
import OTClient

@MainActor
struct ResourceResolver {
    private let cachedServers: [Server]
    private let cachedNetworks: [Network]
    private let cachedImages: [Image]
    private let cachedFlavors: [Flavor]
    private let cachedSubnets: [Subnet]
    private let cachedSecurityGroups: [SecurityGroup]
    private let resourceNameCache: ResourceNameCache
    private let client: OTClient

    init(
        cachedServers: [Server],
        cachedNetworks: [Network],
        cachedImages: [Image],
        cachedFlavors: [Flavor],
        cachedSubnets: [Subnet],
        cachedSecurityGroups: [SecurityGroup],
        resourceNameCache: ResourceNameCache,
        client: OTClient
    ) {
        self.cachedServers = cachedServers
        self.cachedNetworks = cachedNetworks
        self.cachedImages = cachedImages
        self.cachedFlavors = cachedFlavors
        self.cachedSubnets = cachedSubnets
        self.cachedSecurityGroups = cachedSecurityGroups
        self.resourceNameCache = resourceNameCache
        self.client = client
    }

    func resolveFlavorName(_ id: String) -> String {
        if let cachedName = resourceNameCache.getFlavorName(id) {
            return cachedName
        }

        // Fallback to stored list first
        if let flavor = cachedFlavors.first(where: { $0.id == id }) {
            return flavor.name
        }

        return id
    }

    func resolveFlavorNameAsync(_ id: String) async -> String {
        if let cachedName = resourceNameCache.getFlavorName(id) {
            return cachedName
        }

        // Try to find in current cache first
        if let flavor = cachedFlavors.first(where: { $0.id == id }) {
            resourceNameCache.setFlavorName(flavor.id, name: flavor.name)
            return flavor.name
        }

        // Try to fetch async
        do {
            let flavor = try await client.getFlavor(id: id)
            resourceNameCache.setFlavorName(flavor.id, name: flavor.name)
            return flavor.name
        } catch {
            return id
        }
    }

    private func resolveFlavorAsync(_ id: String) async -> Flavor? {
        // First try cache
        if let flavor = cachedFlavors.first(where: { $0.id == id }) {
            return flavor
        }

        do {
            let flavor = try await client.getFlavor(id: id)
            resourceNameCache.setFlavorName(flavor.id, name: flavor.name)
            return flavor
        } catch {
            return nil
        }
    }

    func resolveImageName(_ id: String) -> String {
        if let cachedName = resourceNameCache.getImageName(id) {
            return cachedName
        }
        return id
    }

    func resolveImageNameAsync(_ id: String) async -> String {
        if let cachedName = resourceNameCache.getImageName(id) {
            return cachedName
        }

        // Try to find in current cache first
        if let image = cachedImages.first(where: { $0.id == id }) {
            let name = image.name ?? "Unnamed Image"
            resourceNameCache.setImageName(image.id, name: name)
            return name
        }

        // If not in cache, try to fetch image details
        do {
            let image = try await client.getImage(id: id)
            let name = image.name ?? "Unnamed Image"
            resourceNameCache.setImageName(image.id, name: name)
            return name
        } catch {
            // If fetch fails, return the UUID as fallback
            return id
        }
    }

    func resolveServerName(_ id: String) -> String {
        if let cachedName = resourceNameCache.getServerName(id) {
            return cachedName
        }
        return id
    }

    func resolveNetworkName(_ id: String) -> String {
        if let cachedName = resourceNameCache.getNetworkName(id) {
            return cachedName
        }
        return id
    }

    func getServerIP(_ server: Server) -> String? {
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
}