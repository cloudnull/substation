import OTClient

struct NetworkInterfaceManagementForm {
    var selectedServer: Server?
    var availablePorts: [Port] = []
    var serverInterfaces: [ServerInterface] = []
    var selectedPortIndex: Int = 0
    var selectedOperation: NetworkInterfaceOperation = .view
    var pendingAttachments: Set<String> = []
    var pendingDetachments: Set<String> = []
    var isLoading: Bool = false
    var errorMessage: String?

    enum NetworkInterfaceOperation: CaseIterable {
        case view, attach, detach

        var title: String {
            switch self {
            case .view: return "View Current"
            case .attach: return "Attach Ports"
            case .detach: return "Detach Ports"
            }
        }
    }

    mutating func reset() {
        selectedPortIndex = 0
        selectedOperation = .view
        pendingAttachments.removeAll()
        pendingDetachments.removeAll()
        isLoading = false
        errorMessage = nil
    }

    mutating func togglePort(_ portID: String) {
        switch selectedOperation {
        case .attach:
            if pendingAttachments.contains(portID) {
                pendingAttachments.remove(portID)
            } else {
                pendingAttachments.insert(portID)
                pendingDetachments.remove(portID) // Remove from detachments if present
            }
        case .detach:
            if pendingDetachments.contains(portID) {
                pendingDetachments.remove(portID)
            } else {
                pendingDetachments.insert(portID)
                pendingAttachments.remove(portID) // Remove from attachments if present
            }
        case .view:
            break // No action in view mode
        }
    }

    func isPortSelected(_ portID: String) -> Bool {
        switch selectedOperation {
        case .attach:
            return pendingAttachments.contains(portID)
        case .detach:
            return pendingDetachments.contains(portID)
        case .view:
            return serverInterfaces.contains { $0.portID == portID }
        }
    }

    func isPortCurrentlyAttached(_ portID: String) -> Bool {
        return serverInterfaces.contains { $0.portID == portID }
    }

    func getAvailablePortsForAttach() -> [Port] {
        let currentPortIDs = Set(serverInterfaces.map { $0.portID })
        return availablePorts.filter { !currentPortIDs.contains($0.id) }
    }

    func getPortsForDetach() -> [Port] {
        let currentPortIDs = Set(serverInterfaces.map { $0.portID })
        return availablePorts.filter { currentPortIDs.contains($0.id) }
    }

    func hasPendingChanges() -> Bool {
        return !pendingAttachments.isEmpty || !pendingDetachments.isEmpty
    }

    func getPortForInterface(_ interface: ServerInterface) -> Port? {
        return availablePorts.first { $0.id == interface.portID }
    }
}