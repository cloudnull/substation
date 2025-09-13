import Foundation

// MARK: - Cloud Configuration Models

struct CloudsConfig: Codable {
    let clouds: [String: CloudConfig]
}

struct CloudConfig: Codable {
    let auth: AuthConfig
    let region_name: String?
    let interface: String?
    let identity_api_version: String?

    enum CodingKeys: String, CodingKey {
        case auth
        case region_name
        case interface
        case identity_api_version
    }
}

struct AuthConfig: Codable {
    let auth_url: String
    let username: String?
    let password: String?
    let project_name: String?
    let project_domain_name: String?
    let user_domain_name: String?
    let application_credential_id: String?
    let application_credential_secret: String?

    enum CodingKeys: String, CodingKey {
        case auth_url
        case username
        case password
        case project_name
        case project_domain_name
        case user_domain_name
        case application_credential_id
        case application_credential_secret
    }
}

// MARK: - Cloud Configuration Manager

class CloudConfigManager {
    private let defaultPath: String

    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        self.defaultPath = "\(homeDir)/.config/openstack/clouds.yaml"
    }

    func loadCloudsConfig(path: String? = nil) throws -> CloudsConfig {
        let configPath = path ?? defaultPath

        guard FileManager.default.fileExists(atPath: configPath) else {
            throw CloudConfigError.fileNotFound(configPath)
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: configPath))

        // Parse YAML manually for our simple structure
        return try parseSimpleYAML(data)
    }

    private func parseSimpleYAML(_ data: Data) throws -> CloudsConfig {
        guard let yamlString = String(data: data, encoding: .utf8) else {
            throw CloudConfigError.invalidConfiguration("Unable to decode YAML as UTF-8")
        }

        var clouds: [String: CloudConfig] = [:]
        let lines = yamlString.components(separatedBy: .newlines)

        var currentCloud: String?
        var currentAuth: [String: String] = [:]
        var currentConfig: [String: Any] = [:]
        var inCloudsSection = false
        var inAuthSection = false
        var expectingListItem = false
        var listKey: String?

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                continue
            }

            let indent = line.prefix(while: { $0 == " " }).count

            if trimmedLine == "clouds:" {
                inCloudsSection = true
                continue
            }

            if !inCloudsSection {
                continue
            }

            if indent == 2 && trimmedLine.hasSuffix(":") {
                // Save previous cloud if exists
                if let cloudName = currentCloud {
                    clouds[cloudName] = try createCloudConfig(from: currentConfig, auth: currentAuth)
                }

                // Start new cloud
                currentCloud = String(trimmedLine.dropLast())
                currentAuth = [:]
                currentConfig = [:]
                inAuthSection = false
                expectingListItem = false
                listKey = nil
                continue
            }

            if indent == 4 && trimmedLine == "auth:" {
                inAuthSection = true
                expectingListItem = false
                listKey = nil
                continue
            }

            // Check if we're exiting the auth section
            if inAuthSection && indent == 4 && trimmedLine != "auth:" && trimmedLine.contains(":") {
                inAuthSection = false
                expectingListItem = false
                listKey = nil
            }

            if trimmedLine.contains(":") {
                let parts = trimmedLine.split(separator: ":", maxSplits: 1)
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let value = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

                if inAuthSection && indent == 6 {
                    currentAuth[key] = value
                } else if !inAuthSection && indent == 4 {
                    if value.isEmpty {
                        // This might be a list - set up for list parsing
                        expectingListItem = true
                        listKey = key
                    } else {
                        currentConfig[key] = value
                        expectingListItem = false
                        listKey = nil
                    }
                }
            } else if expectingListItem && trimmedLine.hasPrefix("- ") && indent == 6 {
                // This is a list item
                let item = String(trimmedLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if let key = listKey {
                    currentConfig[key] = item  // Take the first item only
                    expectingListItem = false
                    listKey = nil
                }
            }
        }

        // Save the last cloud
        if let cloudName = currentCloud {
            clouds[cloudName] = try createCloudConfig(from: currentConfig, auth: currentAuth)
        }

        return CloudsConfig(clouds: clouds)
    }

    private func createCloudConfig(from config: [String: Any], auth: [String: String]) throws -> CloudConfig {
        guard let authUrl = auth["auth_url"] else {
            throw CloudConfigError.missingRequiredField("auth_url")
        }

        let authConfig = AuthConfig(
            auth_url: authUrl,
            username: auth["username"],
            password: auth["password"],
            project_name: auth["project_name"],
            project_domain_name: auth["project_domain_name"],
            user_domain_name: auth["user_domain_name"],
            application_credential_id: auth["application_credential_id"],
            application_credential_secret: auth["application_credential_secret"]
        )

        return CloudConfig(
            auth: authConfig,
            region_name: config["region_name"] as? String,
            interface: config["interface"] as? String,
            identity_api_version: config["identity_api_version"] as? String
        )
    }

    func listAvailableClouds(path: String? = nil) throws -> [String] {
        let config = try loadCloudsConfig(path: path)
        return Array(config.clouds.keys).sorted()
    }

    func getCloudConfig(_ cloudName: String, path: String? = nil) throws -> CloudConfig {
        let config = try loadCloudsConfig(path: path)

        guard let cloudConfig = config.clouds[cloudName] else {
            throw CloudConfigError.cloudNotFound(cloudName, availableClouds: Array(config.clouds.keys))
        }

        return cloudConfig
    }
}

// MARK: - Errors

enum CloudConfigError: Error {
    case fileNotFound(String)
    case cloudNotFound(String, availableClouds: [String])
    case invalidConfiguration(String)
    case missingRequiredField(String)
}

extension CloudConfigError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "clouds.yaml file not found at: \(path)"
        case .cloudNotFound(let cloud, let available):
            return "Cloud '\(cloud)' not found. Available clouds: \(available.joined(separator: ", "))"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        }
    }
}