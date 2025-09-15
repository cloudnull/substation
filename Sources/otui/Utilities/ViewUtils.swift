import Foundation
import CNCurses

struct ViewUtils {
    static func colorPair(_ n: Int32) -> Int32 { n << 8 }

    static func getDynamicHelpText(for currentView: ViewMode) -> String {
        let baseCommands = "q:quit ↑↓:select ?:help"

        switch currentView {
        case .dashboard:
            return "\(baseCommands) S:servers N:networks V:volumes I:images F:flavors T:topology r:refresh a:auto-refresh"
        case .servers:
            return "\(baseCommands) SPACE:details C:create R:restart Z:resize DEL:delete /:search ESC:back"
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
            return "\(baseCommands) /:search ESC:back"
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

    static func prompt(_ text: String, screen: OpaquePointer?, screenRows: Int32) -> String? {
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

    static func confirmDelete(_ itemName: String, screen: OpaquePointer?, screenRows: Int32) -> Bool {
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
}