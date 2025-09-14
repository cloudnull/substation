import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import OTClient
import CNCurses

@MainActor
final class TUI {
    enum Resource: CaseIterable {
        case servers, networks, volumes, images, topology

        var title: String {
            switch self {
            case .servers: return "Servers"
            case .networks: return "Networks"
            case .volumes: return "Volumes"
            case .images: return "Images"
            case .topology: return "Topology"
            }
        }
    }

    private let client: OTClient
    private var current: Resource = .servers
    private var running = true
    private var scrollOffset = 0
    private var lastTopology: TopologyGraph?

    init(client: OTClient) {
        self.client = client
    }

    func run() async {
        let screen = initscr()
        cbreak()
        noecho()
        keypad(screen, true)
        nodelay(screen, true)
        defer { endwin() }

        while running {
            await draw(screen: screen)
            let ch = wgetch(screen)
            switch ch {
            case Int32(113): // q
                running = false
            case Int32(49): // 1
                current = .servers
                scrollOffset = 0
            case Int32(50): // 2
                current = .networks
                scrollOffset = 0
            case Int32(51): // 3
                current = .volumes
                scrollOffset = 0
            case Int32(52): // 4
                current = .images
                scrollOffset = 0
            case Int32(53): // 5
                current = .topology
                scrollOffset = 0
            case Int32(259): // KEY_UP
                scrollOffset = max(scrollOffset - 1, 0)
            case Int32(258): // KEY_DOWN
                scrollOffset += 1
            case Int32(119): // w
                if current == .topology {
                    await exportTopology()
                }
            default:
                break
            }
            usleep(200_000) // 200ms refresh
        }
    }

    private func draw(screen: OpaquePointer?) async {
        werase(screen)
        let lines = await fetchLines()
        let maxRows = 18
        if scrollOffset > max(0, lines.count - maxRows) {
            scrollOffset = max(0, lines.count - maxRows)
        }
        wmove(screen, 0, 0)
        waddstr(screen, current.title)
        for (idx, line) in lines.dropFirst(scrollOffset).prefix(maxRows).enumerated() {
            wmove(screen, Int32(idx + 1), 0)
            waddstr(screen, line)
        }
        wmove(screen, 20, 0)
        let footer = "1 Servers 2 Networks 3 Volumes 4 Images 5 Topology | q Quit"
        waddstr(screen, footer)
        wrefresh(screen)
    }

    private func fetchLines() async -> [String] {
        switch current {
        case .servers:
            let servers = (try? await client.listServers()) ?? []
            return servers.map { "\($0.name) \($0.id)" }
        case .networks:
            let nets = (try? await client.listNetworks()) ?? []
            return nets.map { "\($0.name) \($0.id)" }
        case .volumes:
            let vols = (try? await client.listVolumes()) ?? []
            return vols.map { "\($0.name ?? "") \($0.id)" }
        case .images:
            let imgs = (try? await client.listImages()) ?? []
            return imgs.map { "\($0.name ?? "") \($0.id)" }
        case .topology:
            let graph = await TopologyGraphBuilder.build(client: client)
            lastTopology = graph
            return graph.lines
        }
    }

    private func exportTopology() async {
        let graph: TopologyGraph
        if let cached = lastTopology {
            graph = cached
        } else {
            graph = await TopologyGraphBuilder.build(client: client)
            lastTopology = graph
        }
        var header = "# Topology Graph\n"
        header += "Region: \(client.region) Project: \(client.project)\n"
        let c = graph.counts
        header += "Totals: Servers \(c.servers) Networks \(c.networks) Subnets \(c.subnets) Ports \(c.ports) Routers \(c.routers) Volumes \(c.volumes) FIPs \(c.fips) SecurityGroups \(c.securityGroups)\n\n"
        let body = graph.lines.joined(separator: "\n")
        let content = header + body + "\n"
        try? content.write(to: URL(fileURLWithPath: "topology.txt"), atomically: true, encoding: .utf8)
    }
}
