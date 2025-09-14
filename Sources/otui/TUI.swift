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
        case servers, networks, volumes, images

        var title: String {
            switch self {
            case .servers: return "Servers"
            case .networks: return "Networks"
            case .volumes: return "Volumes"
            case .images: return "Images"
            }
        }
    }

    private let client: OTClient
    private var current: Resource = .servers
    private var running = true

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
            case Int32(50): // 2
                current = .networks
            case Int32(51): // 3
                current = .volumes
            case Int32(52): // 4
                current = .images
            default:
                break
            }
            usleep(200_000) // 200ms refresh
        }
    }

    private func draw(screen: OpaquePointer?) async {
        werase(screen)
        let lines = await fetchLines()
        wmove(screen, 0, 0)
        waddstr(screen, current.title)
        for (idx, line) in lines.enumerated() {
            wmove(screen, Int32(idx + 1), 0)
            waddstr(screen, line)
        }
        wmove(screen, 20, 0)
        waddstr(screen, "1 Servers 2 Networks 3 Volumes 4 Images | q Quit")
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
        }
    }
}
