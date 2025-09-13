import Foundation

enum ServerCreateField: CaseIterable {
    case name, bootSource, image, volume, flavor, network, securityGroup, keyPair

    var title: String {
        switch self {
        case .name: return "Server Name"
        case .bootSource: return "Boot Source"
        case .image: return "Image"
        case .volume: return "Volume"
        case .flavor: return "Flavor"
        case .network: return "Network"
        case .securityGroup: return "Security Group"
        case .keyPair: return "SSH Key Pair"
        }
    }
}

enum BootSource: CaseIterable {
    case image, volume

    var title: String {
        switch self {
        case .image: return "Boot from Image"
        case .volume: return "Boot from Volume"
        }
    }
}

struct ServerCreateForm {
    var serverName: String = ""
    var bootSource: BootSource = .image
    var selectedImageIndex: Int = 0
    var selectedVolumeIndex: Int = 0
    var selectedFlavorIndex: Int = 0
    var selectedNetworkIndex: Int = 0
    var selectedSecurityGroupIndex: Int = 0
    var selectedKeyPairIndex: Int = 0
    var currentField: ServerCreateField = .name
    var fieldEditMode: Bool = false // true when editing a text field
    var nameFieldHighlighted: Bool = false // true when name field has been activated

    mutating func nextField() {
        let fields = availableFields()
        if let currentIndex = fields.firstIndex(of: currentField) {
            let nextIndex = (currentIndex + 1) % fields.count
            currentField = fields[nextIndex]
        }
        fieldEditMode = false
    }

    mutating func previousField() {
        let fields = availableFields()
        if let currentIndex = fields.firstIndex(of: currentField) {
            let prevIndex = currentIndex == 0 ? fields.count - 1 : currentIndex - 1
            currentField = fields[prevIndex]
        }
        fieldEditMode = false
    }

    /// Returns the fields that should be shown based on current boot source
    private func availableFields() -> [ServerCreateField] {
        var fields: [ServerCreateField] = [.name, .bootSource]

        switch bootSource {
        case .image:
            fields.append(.image)
        case .volume:
            fields.append(.volume)
        }

        fields.append(contentsOf: [.flavor, .network, .securityGroup, .keyPair])
        return fields
    }

    mutating func toggleBootSource() {
        switch bootSource {
        case .image:
            bootSource = .volume
        case .volume:
            bootSource = .image
        }
    }

    mutating func activateNameField() {
        nameFieldHighlighted = true
        fieldEditMode = true
    }
}