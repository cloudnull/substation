import Foundation
import OTClient

struct TopologyGraph: Sendable {
    struct Counts: Sendable {
        let servers: Int
        let volumes: Int
        let ports: Int
        let networks: Int
        let subnets: Int
        let routers: Int
        let fips: Int
        let securityGroups: Int
    }
    let lines: [String]
    let counts: Counts
}

enum TopologyGraphBuilder {
    static func build(client: OTClient) async -> TopologyGraph {
        async let serversReq = try? await client.listServers()
        async let portsReq = try? await client.listPorts()
        async let networksReq = try? await client.listNetworks()
        async let subnetsReq = try? await client.listSubnets()
        async let volumesReq = try? await client.listVolumes()
        async let routersReq = try? await client.listRouters()
        async let fipsReq = try? await client.listFloatingIPs()
        async let sgsReq = try? await client.listSecurityGroups()

        let servers = await serversReq ?? []
        let ports = await portsReq ?? []
        let networks = await networksReq ?? []
        let subnets = await subnetsReq ?? []
        let volumes = await volumesReq ?? []
        let routers = await routersReq ?? []
        let fips = await fipsReq ?? []
        let sgs = await sgsReq ?? []

        let networkByID = Dictionary(uniqueKeysWithValues: networks.map { ($0.id, $0) })
        let subnetByID = Dictionary(uniqueKeysWithValues: subnets.map { ($0.id, $0) })
        let sgByID = Dictionary(uniqueKeysWithValues: sgs.map { ($0.id, $0) })

        var lines: [String] = []

        for server in servers.sorted(by: { $0.name < $1.name }) {
            lines.append("Server: \(server.name) (\(server.id))")
            let sPorts = ports.filter { $0.deviceID == server.id }
            for port in sPorts.sorted(by: { $0.id < $1.id }) {
                lines.append("  Port: \(port.id)")
                if let net = networkByID[port.networkID] {
                    lines.append("    Network: \(net.name) (\(net.id))")
                }
                for ip in port.fixedIPs {
                    if let subnet = subnetByID[ip.subnetID] {
                        lines.append("    Subnet: \(subnet.name ?? "") (\(subnet.id))")
                    }
                }
                for sgID in port.securityGroups {
                    if let sg = sgByID[sgID] {
                        lines.append("    SG: \(sg.name) (\(sg.id))")
                    }
                }
                let pfips = fips.filter { $0.portID == port.id }
                for f in pfips.sorted(by: { $0.floatingIPAddress < $1.floatingIPAddress }) {
                    lines.append("    FIP: \(f.floatingIPAddress) (\(f.id))")
                }
            }
            for volume in volumes.filter({ vol in vol.attachments.contains(where: { $0.serverId == server.id }) }).sorted(by: { ($0.name ?? "") < ($1.name ?? "") }) {
                lines.append("  Volume: \(volume.name ?? "") (\(volume.id))")
            }
        }

        for router in routers.sorted(by: { ($0.name ?? "") < ($1.name ?? "") }) {
            lines.append("Router: \(router.name ?? "") (\(router.id))")
            let rPorts = ports.filter { $0.deviceID == router.id }
            for port in rPorts.sorted(by: { $0.id < $1.id }) {
                lines.append("  Port: \(port.id)")
                if let net = networkByID[port.networkID] {
                    lines.append("    Network: \(net.name) (\(net.id))")
                }
                for ip in port.fixedIPs {
                    if let subnet = subnetByID[ip.subnetID] {
                        lines.append("    Subnet: \(subnet.name ?? "") (\(subnet.id))")
                    }
                }
                let rfips = fips.filter { $0.portID == port.id }
                for f in rfips.sorted(by: { $0.floatingIPAddress < $1.floatingIPAddress }) {
                    lines.append("    FIP: \(f.floatingIPAddress) (\(f.id))")
                }
            }
        }

        let counts = TopologyGraph.Counts(
            servers: servers.count,
            volumes: volumes.count,
            ports: ports.count,
            networks: networks.count,
            subnets: subnets.count,
            routers: routers.count,
            fips: fips.count,
            securityGroups: sgs.count
        )

        return TopologyGraph(lines: lines, counts: counts)
    }
}
