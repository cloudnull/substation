import Foundation

struct ServerResizeForm {
    var selectedFlavorIndex: Int = 0
    var confirmed: Bool = false

    init() {
        self.selectedFlavorIndex = 0
        self.confirmed = false
    }

    mutating func reset() {
        selectedFlavorIndex = 0
        confirmed = false
    }
}