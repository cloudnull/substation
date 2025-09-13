import Foundation
import CNCurses
import OTClient

struct KeyPairViews {
    @MainActor
    static func drawDetailedKeyPairList(screen: OpaquePointer?, startRow: Int32, startCol: Int32,
                                      width: Int32, height: Int32, cachedKeyPairs: [KeyPair],
                                      searchQuery: String?, scrollOffset: Int, selectedIndex: Int) async {
        wattron(screen, ViewUtils.colorPair(2))
        wmove(screen, startRow, startCol + 2)
        let searchInfo = searchQuery != nil ? " (filtered: \(searchQuery!))" : ""
        waddstr(screen, "* Key Pairs\(searchInfo)")
        wattroff(screen, ViewUtils.colorPair(2))

        let keyPairs = FilterUtils.filterKeyPairs(cachedKeyPairs, query: searchQuery)
        let visibleHeight = Int(height) - 4

        for i in 0..<visibleHeight {
            let keyPairIndex = scrollOffset + i
            let row = startRow + Int32(i) + 2

            if keyPairIndex >= keyPairs.count {
                wmove(screen, row, startCol + 2)
                wclrtoeol(screen)
                continue
            }

            let keyPair = keyPairs[keyPairIndex]
            wmove(screen, row, startCol + 2)
            wclrtoeol(screen)

            if keyPairIndex == selectedIndex {
                wattron(screen, ViewUtils.colorPair(3))
                waddstr(screen, "> ")
            } else {
                waddstr(screen, "  ")
            }

            let maxNameWidth = Int(width) - 25
            let keyPairName = keyPair.name
            let truncatedName = keyPairName.count > maxNameWidth ?
                String(keyPairName.prefix(maxNameWidth - 3)) + "..." : keyPairName
            waddstr(screen, truncatedName)

            // Fingerprint column
            let fingerprintCol = startCol + Int32(maxNameWidth) + 5
            wmove(screen, row, fingerprintCol)
            if let fingerprint = keyPair.fingerprint {
                wattron(screen, ViewUtils.colorPair(6))
                let shortFingerprint = fingerprint.count > 15 ?
                    String(fingerprint.suffix(15)) : fingerprint
                waddstr(screen, shortFingerprint)
                wattroff(screen, ViewUtils.colorPair(6))
            }

            if keyPairIndex == selectedIndex {
                wattroff(screen, ViewUtils.colorPair(3))
            }
        }

        wmove(screen, startRow + height - 2, startCol + 2)
        wattron(screen, ViewUtils.colorPair(4))
        wattroff(screen, ViewUtils.colorPair(4))
    }

    @MainActor
    static func drawKeyPairDetail(screen: OpaquePointer?, startRow: Int32, startCol: Int32,
                                width: Int32, height: Int32, keyPair: KeyPair) async {
        wattron(screen, ViewUtils.colorPair(2))
        wmove(screen, startRow, startCol + 2)
        waddstr(screen, "* Key Pair Details: \(keyPair.name)")
        wattroff(screen, ViewUtils.colorPair(2))

        var currentRow = startRow + 2

        // Basic Information
        wattron(screen, ViewUtils.colorPair(3))
        wmove(screen, currentRow, startCol + 2)
        waddstr(screen, "Basic Information")
        wattroff(screen, ViewUtils.colorPair(3))
        currentRow += 1

        wmove(screen, currentRow, startCol + 4)
        wattron(screen, ViewUtils.colorPair(6))
        waddstr(screen, "Name: \(keyPair.name)")
        wattroff(screen, ViewUtils.colorPair(6))
        currentRow += 1

        if let fingerprint = keyPair.fingerprint {
            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "Fingerprint: \(fingerprint)")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1
        }

        if let type = keyPair.type {
            wmove(screen, currentRow, startCol + 4)
            wattron(screen, ViewUtils.colorPair(6))
            waddstr(screen, "Type: \(type)")
            wattroff(screen, ViewUtils.colorPair(6))
            currentRow += 1
        }

        currentRow += 1

        // Public Key
        if let publicKey = keyPair.publicKey {
            wattron(screen, ViewUtils.colorPair(3))
            wmove(screen, currentRow, startCol + 2)
            waddstr(screen, "Public Key")
            wattroff(screen, ViewUtils.colorPair(3))
            currentRow += 1

            // Split the public key into multiple lines if needed
            let maxKeyWidth = Int(width) - 6
            let keyLines = FormatUtils.wrapText(publicKey, maxWidth: maxKeyWidth)
            let maxDisplayLines = Int(height) - Int(currentRow - startRow) - 3
            let displayLines = Array(keyLines.prefix(maxDisplayLines))

            for line in displayLines {
                wmove(screen, currentRow, startCol + 4)
                wattron(screen, ViewUtils.colorPair(6))
                waddstr(screen, line)
                wattroff(screen, ViewUtils.colorPair(6))
                currentRow += 1
            }

            if keyLines.count > displayLines.count {
                wmove(screen, currentRow, startCol + 4)
                wattron(screen, ViewUtils.colorPair(4))
                waddstr(screen, "... (truncated)")
                wattroff(screen, ViewUtils.colorPair(4))
                currentRow += 1
            }
        }

        wmove(screen, startRow + height - 2, startCol + 2)
        wattron(screen, ViewUtils.colorPair(4))
        waddstr(screen, "Press ESC to return to key pair list")
        wattroff(screen, ViewUtils.colorPair(4))
    }
}