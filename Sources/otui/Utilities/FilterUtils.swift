import Foundation
import OTClient

struct FilterUtils {
    static func filterServers(_ servers: [Server], query: String?) -> [Server] {
        guard let query = query?.lowercased() else { return servers }
        return servers.filter { server in
            server.name?.lowercased().contains(query) == true ||
            server.status?.lowercased().contains(query) == true ||
            server.id.lowercased().contains(query) ||
            getServerIP(server)?.contains(query) == true
        }
    }

    static func filterNetworks(_ networks: [Network], query: String?) -> [Network] {
        guard let query = query?.lowercased() else { return networks }
        return networks.filter { network in
            network.name.lowercased().contains(query) ||
            network.status?.lowercased().contains(query) == true ||
            network.id.lowercased().contains(query)
        }
    }

    static func filterVolumes(_ volumes: [Volume], query: String?) -> [Volume] {
        guard let query = query?.lowercased() else { return volumes }
        return volumes.filter { volume in
            volume.name?.lowercased().contains(query) == true ||
            volume.status?.lowercased().contains(query) == true ||
            volume.id.lowercased().contains(query)
        }
    }

    static func filterImages(_ images: [Image], query: String?) -> [Image] {
        guard let query = query?.lowercased() else { return images }
        return images.filter { image in
            image.name?.lowercased().contains(query) == true ||
            image.status?.lowercased().contains(query) == true ||
            image.id.lowercased().contains(query)
        }
    }

    static func filterFlavors(_ flavors: [Flavor], query: String?) -> [Flavor] {
        guard let query = query?.lowercased() else { return flavors }
        return flavors.filter { flavor in
            flavor.name.lowercased().contains(query) ||
            flavor.id.lowercased().contains(query)
        }
    }

    static func filterKeyPairs(_ keyPairs: [KeyPair], query: String?) -> [KeyPair] {
        guard let query = query?.lowercased() else { return keyPairs }
        return keyPairs.filter { keyPair in
            keyPair.name.lowercased().contains(query) ||
            keyPair.type?.lowercased().contains(query) == true ||
            keyPair.fingerprint?.lowercased().contains(query) == true
        }
    }

    static func filterLines(_ lines: [String], query: String?) -> [String] {
        guard let query = query?.lowercased() else { return lines }
        return lines.filter { $0.lowercased().contains(query) }
    }

    private static func getServerIP(_ server: Server) -> String? {
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