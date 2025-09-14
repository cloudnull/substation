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
    private var searchQuery: String?
    private var statusMessage: String?

    private let logo = [
        "  ____   _______   _    _   _____ ",
        " / __ \\ |__   __| | |  | | |_   _|",
        "| |  | |   | |   | |  | |   | |  ",
        "| |  | |   | |   | |  | |   | |  ",
        "| |__| |   | |   | |__| |  _| |_ ",
        " \\____/    |_|    \\____/  |_____|"]

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

        // Draw once so the user sees the interface immediately
        await draw(screen: screen)

        while running {
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
            case Int32(47): // /
                if let input = prompt("Search: ", screen: screen), !input.isEmpty {
                    searchQuery = input
                    scrollOffset = 0
                } else {
                    searchQuery = nil
                }
            case Int32(27): // ESC
                searchQuery = nil
            case Int32(119): // w
                if current == .topology {
                    await exportTopology()
                }
            case Int32(111): // o start
                if let id = prompt("Start server ID: ", screen: screen), !id.isEmpty {
                    do { try await client.startServer(id: id); statusMessage = "Started \(id)" } catch { statusMessage = "Error \(error)" }
                }
            case Int32(112): // p stop
                if let id = prompt("Stop server ID: ", screen: screen), !id.isEmpty {
                    do { try await client.stopServer(id: id); statusMessage = "Stopped \(id)" } catch { statusMessage = "Error \(error)" }
                }
            case Int32(97): // a attach port
                if let sid = prompt("Server ID: ", screen: screen),
                   let pid = prompt("Port ID: ", screen: screen), !sid.isEmpty, !pid.isEmpty {
                    do { try await client.attachPort(serverID: sid, portID: pid); statusMessage = "Attached port" } catch { statusMessage = "Error \(error)" }
                }
            case Int32(102): // f alloc fip
                if let net = prompt("External network ID: ", screen: screen), !net.isEmpty {
                    let port = prompt("Port ID (optional): ", screen: screen)
                    do { let fip = try await client.createFloatingIP(networkID: net, portID: port?.isEmpty == true ? nil : port); statusMessage = "FIP \(fip.id)" } catch { statusMessage = "Error \(error)" }
                }
            case Int32(117): // u update fip
                if let id = prompt("FIP ID: ", screen: screen), !id.isEmpty {
                    let port = prompt("Port ID (blank to detach): ", screen: screen)
                    do { _ = try await client.updateFloatingIP(id: id, portID: port?.isEmpty == true ? nil : port); statusMessage = "Updated FIP" } catch { statusMessage = "Error \(error)" }
                }
            case Int32(114): // r delete fip
                if let id = prompt("Delete FIP ID: ", screen: screen), !id.isEmpty {
                    do { try await client.deleteFloatingIP(id: id); statusMessage = "Deleted FIP" } catch { statusMessage = "Error \(error)" }
                }
            case Int32(103): // g add sg rule
                if let sg = prompt("Security group ID: ", screen: screen), !sg.isEmpty,
                   let dir = prompt("Direction (ingress/egress): ", screen: screen), !dir.isEmpty {
                    let proto = prompt("Protocol (optional): ", screen: screen)
                    let range = prompt("Port range min-max (optional): ", screen: screen)
                    var min: Int?; var max: Int?
                    if let r = range, !r.isEmpty {
                        let parts = r.split(separator: "-")
                        if let f = parts.first, let v = Int(f) { min = v }
                        if parts.count > 1, let l = parts.last, let v = Int(l) { max = v }
                    }
                    let cidr = prompt("Remote IP prefix (optional): ", screen: screen)
                    do {
                        let rule = try await client.createSecurityGroupRule(securityGroupID: sg, direction: dir, protocol: proto?.isEmpty == true ? nil : proto, portRangeMin: min, portRangeMax: max, remoteIPPrefix: cidr?.isEmpty == true ? nil : cidr)
                        statusMessage = "Rule \(rule.id)"
                    } catch { statusMessage = "Error \(error)" }
                }
            case Int32(100): // d delete sg rule
                if let rid = prompt("Rule ID: ", screen: screen), !rid.isEmpty {
                    do { try await client.deleteSecurityGroupRule(id: rid); statusMessage = "Deleted rule" } catch { statusMessage = "Error \(error)" }
                }
            default:
                break
            }
            if !running { break }
            await draw(screen: screen)
            usleep(200_000) // 200ms refresh
        }
    }

    private func draw(screen: OpaquePointer?) async {
        let cols: Int32 = 80

        werase(screen)

        // Header
        wmove(screen, 0, 0)
        waddstr(screen, "Region: \(client.region)")
        wmove(screen, 1, 0)
        waddstr(screen, "Project: \(client.project)")
        wmove(screen, 2, 0)
        waddstr(screen, "OpenStack Terminal UI")

        // ASCII logo on the right
        for (idx, line) in logo.enumerated() {
            let startX = Int32(max(0, Int(cols) - line.count - 1))
            wmove(screen, Int32(idx), startX)
            waddstr(screen, line)
        }

        // Title for current view
        var title = current.title
        if let query = searchQuery { title += " [\(query)]" }
        wmove(screen, 6, 0)
        waddstr(screen, title)

        // Refresh early so the header is visible while data loads
        wrefresh(screen)

        let lines = await fetchLines()
        let maxRows = 13
        if scrollOffset > max(0, lines.count - maxRows) {
            scrollOffset = max(0, lines.count - maxRows)
        }
        for (idx, line) in lines.dropFirst(scrollOffset).prefix(maxRows).enumerated() {
            wmove(screen, Int32(idx + 7), 0)
            waddstr(screen, line)
        }
        if let status = statusMessage {
            wmove(screen, 20, 0)
            wclrtoeol(screen)
            waddstr(screen, status)
        }
        wmove(screen, 21, 0)
        let footer = "1 Servers 2 Networks 3 Volumes 4 Images 5 Topology | o start p stop a attach f newFIP u updFIP r delFIP g addRule d delRule / Search q Quit"
        waddstr(screen, footer)
        wrefresh(screen)
    }

    private func fetchLines() async -> [String] {
        switch current {
        case .servers:
            let servers = (try? await client.listServers()) ?? []
            let lines = servers.map { "\($0.name) \($0.id)" }
            return filterLines(lines, query: searchQuery)
        case .networks:
            let nets = (try? await client.listNetworks()) ?? []
            let lines = nets.map { "\($0.name) \($0.id)" }
            return filterLines(lines, query: searchQuery)
        case .volumes:
            let vols = (try? await client.listVolumes()) ?? []
            let lines = vols.map { "\($0.name ?? "") \($0.id)" }
            return filterLines(lines, query: searchQuery)
        case .images:
            let imgs = (try? await client.listImages()) ?? []
            let lines = imgs.map { "\($0.name ?? "") \($0.id)" }
            return filterLines(lines, query: searchQuery)
        case .topology:
            let graph = await TopologyGraphBuilder.build(client: client)
            lastTopology = graph
            return filterLines(graph.lines, query: searchQuery)
        }
    }

    private func prompt(_ text: String, screen: OpaquePointer?) -> String? {
        echo()
        nodelay(screen, false)
        defer {
            noecho()
            nodelay(screen, true)
        }
        wmove(screen, 22, 0)
        wclrtoeol(screen)
        waddstr(screen, text)
        let buf = UnsafeMutablePointer<CChar>.allocate(capacity: 256)
        defer { buf.deallocate() }
        wgetnstr(screen, buf, 255)
        return String(cString: buf)
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
