import Foundation
import OTClient

struct SecurityGroupManagementForm {
    var selectedServer: Server?
    var availableSecurityGroups: [SecurityGroup] = []
    var serverSecurityGroups: [SecurityGroup] = []
    var selectedSecurityGroupIndex: Int = 0
    var selectedOperation: SecurityGroupOperation = .view
    var pendingAdditions: Set<String> = []
    var pendingRemovals: Set<String> = []
    var isLoading: Bool = false
    var errorMessage: String?

    enum SecurityGroupOperation: CaseIterable {
        case view, add, remove

        var title: String {
            switch self {
            case .view: return "View Current"
            case .add: return "Add Groups"
            case .remove: return "Remove Groups"
            }
        }
    }

    mutating func reset() {
        selectedSecurityGroupIndex = 0
        selectedOperation = .view
        pendingAdditions.removeAll()
        pendingRemovals.removeAll()
        isLoading = false
        errorMessage = nil
    }

    mutating func toggleSecurityGroup(_ securityGroupID: String) {
        switch selectedOperation {
        case .add:
            if pendingAdditions.contains(securityGroupID) {
                pendingAdditions.remove(securityGroupID)
            } else {
                pendingAdditions.insert(securityGroupID)
                pendingRemovals.remove(securityGroupID) // Remove from removals if present
            }
        case .remove:
            if pendingRemovals.contains(securityGroupID) {
                pendingRemovals.remove(securityGroupID)
            } else {
                pendingRemovals.insert(securityGroupID)
                pendingAdditions.remove(securityGroupID) // Remove from additions if present
            }
        case .view:
            break // No action in view mode
        }
    }

    func isSecurityGroupSelected(_ securityGroupID: String) -> Bool {
        switch selectedOperation {
        case .add:
            return pendingAdditions.contains(securityGroupID)
        case .remove:
            return pendingRemovals.contains(securityGroupID)
        case .view:
            return serverSecurityGroups.contains { $0.id == securityGroupID }
        }
    }

    func isSecurityGroupCurrentlyAssigned(_ securityGroupID: String) -> Bool {
        return serverSecurityGroups.contains { $0.id == securityGroupID }
    }

    func getAvailableSecurityGroupsForAdd() -> [SecurityGroup] {
        let currentIDs = Set(serverSecurityGroups.map { $0.id })
        return availableSecurityGroups.filter { !currentIDs.contains($0.id) }
    }

    func getSecurityGroupsForRemove() -> [SecurityGroup] {
        return serverSecurityGroups
    }

    func hasPendingChanges() -> Bool {
        return !pendingAdditions.isEmpty || !pendingRemovals.isEmpty
    }
}