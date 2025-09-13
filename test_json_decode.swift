#!/usr/bin/env swift

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Copy of our fixed Server struct for testing
public struct Server: Decodable, Sendable {
    public let id: String
    public let name: String
    public let status: String?
    public let taskState: String?
    public let powerState: Int?
    public let flavor: FlavorInfo?
    public let image: ImageInfo?
    public let created: String?
    public let updated: String?
    public let addresses: [String: [Address]]?
    public let metadata: [String: String]?
    public let accessIPv4: String?
    public let accessIPv6: String?
    public let progress: Int?
    public let hostId: String?
    public let availabilityZone: String?
    public let keyName: String?

    public struct Address: Decodable, Sendable {
        public let addr: String
        public let version: Int
        public let type: String?

        enum CodingKeys: String, CodingKey {
            case addr, version
            case type = "OS-EXT-IPS:type"
        }
    }

    public struct FlavorInfo: Decodable, Sendable {
        public let id: String
        public let name: String?
        public let links: [Link]?

        public struct Link: Decodable, Sendable {
            public let href: String
            public let rel: String
        }
    }

    public struct ImageInfo: Decodable, Sendable {
        public let id: String
        public let name: String?
        public let links: [Link]?

        public struct Link: Decodable, Sendable {
            public let href: String
            public let rel: String
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, status, metadata, created, updated, addresses, progress, flavor, image
        case taskState = "OS-EXT-STS:task_state"
        case powerState = "OS-EXT-STS:power_state"
        case accessIPv4 = "accessIPv4"
        case accessIPv6 = "accessIPv6"
        case hostId = "hostId"
        case availabilityZone = "OS-EXT-AZ:availability_zone"
        case keyName = "key_name"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        taskState = try container.decodeIfPresent(String.self, forKey: .taskState)
        powerState = try container.decodeIfPresent(Int.self, forKey: .powerState)
        created = try container.decodeIfPresent(String.self, forKey: .created)
        updated = try container.decodeIfPresent(String.self, forKey: .updated)
        addresses = try container.decodeIfPresent([String: [Address]].self, forKey: .addresses)
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata)
        accessIPv4 = try container.decodeIfPresent(String.self, forKey: .accessIPv4)
        accessIPv6 = try container.decodeIfPresent(String.self, forKey: .accessIPv6)
        progress = try container.decodeIfPresent(Int.self, forKey: .progress)
        hostId = try container.decodeIfPresent(String.self, forKey: .hostId)
        availabilityZone = try container.decodeIfPresent(String.self, forKey: .availabilityZone)
        keyName = try container.decodeIfPresent(String.self, forKey: .keyName)

        // Handle flavor - can be dictionary (FlavorInfo) or string (ID) or null
        if let flavorDict = try? container.decode(FlavorInfo.self, forKey: .flavor) {
            flavor = flavorDict
        } else {
            flavor = nil
        }

        // Handle image - can be dictionary (ImageInfo) or string (ID) or null
        if let imageDict = try? container.decode(ImageInfo.self, forKey: .image) {
            image = imageDict
        } else {
            image = nil
        }
    }
}

public struct CatalogEntry: Decodable, Sendable {
    public struct Endpoint: Decodable, Sendable {
        public let region: String
        public let url: String
        public let interface: String
    }
    public let type: String
    public let name: String
    public let endpoints: [Endpoint]
}

// Simple test to verify JSON decoding works
struct AuthRequest: Encodable {
    struct Auth: Encodable {
        let identity: Identity
        let scope: Scope
    }
    let auth: Auth

    struct Identity: Encodable {
        let methods: [String]
        let password: PasswordCredentials
    }
    struct PasswordCredentials: Encodable {
        let user: User
    }
    struct User: Encodable {
        let name: String
        let domain: Domain
        let password: String
    }
    struct Domain: Encodable {
        let name: String
    }
    struct Scope: Encodable {
        let project: Project
    }
    struct Project: Encodable {
        let name: String
        let domain: Domain
    }
}

struct TokenResponse: Decodable {
    struct Token: Decodable {
        let catalog: [CatalogEntry]
    }
    let token: Token
}

// Get environment variables
guard let authURL = ProcessInfo.processInfo.environment["OS_AUTH_URL"],
      let username = ProcessInfo.processInfo.environment["OS_USERNAME"],
      let password = ProcessInfo.processInfo.environment["OS_PASSWORD"],
      let projectName = ProcessInfo.processInfo.environment["OS_PROJECT_NAME"],
      let region = ProcessInfo.processInfo.environment["OS_REGION_NAME"],
      let userDomain = ProcessInfo.processInfo.environment["OS_USER_DOMAIN_NAME"],
      let projectDomain = ProcessInfo.processInfo.environment["OS_PROJECT_DOMAIN_NAME"] else {
    print("Missing required environment variables")
    exit(1)
}

print("Testing OpenStack JSON decoding...")

// Test authentication
let authRequest = AuthRequest(
    auth: AuthRequest.Auth(
        identity: AuthRequest.Identity(
            methods: ["password"],
            password: AuthRequest.PasswordCredentials(
                user: AuthRequest.User(
                    name: username,
                    domain: AuthRequest.Domain(name: userDomain),
                    password: password
                )
            )
        ),
        scope: AuthRequest.Scope(
            project: AuthRequest.Project(
                name: projectName,
                domain: AuthRequest.Domain(name: projectDomain)
            )
        )
    )
)

var request = URLRequest(url: URL(string: authURL + "/auth/tokens")!)
request.httpMethod = "POST"
request.addValue("application/json", forHTTPHeaderField: "Content-Type")
request.addValue("application/json", forHTTPHeaderField: "Accept")
request.httpBody = try JSONEncoder().encode(authRequest)

let semaphore = DispatchSemaphore(value: 0)
var token: String?
var computeEndpoint: String?

URLSession.shared.dataTask(with: request) { data, response, error in
    defer { semaphore.signal() }

    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 201,
          let authToken = httpResponse.value(forHTTPHeaderField: "X-Subject-Token"),
          let data = data else {
        print("Auth failed: \(error?.localizedDescription ?? "Unknown error")")
        return
    }

    token = authToken

    do {
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        for service in tokenResponse.token.catalog {
            if service.type == "compute" {
                for endpoint in service.endpoints {
                    if endpoint.region == region && endpoint.interface == "public" {
                        computeEndpoint = endpoint.url
                        break
                    }
                }
            }
        }
    } catch {
        print("Failed to parse token response: \(error)")
    }
}.resume()

semaphore.wait()

guard let authToken = token, let endpoint = computeEndpoint else {
    print("Failed to get token or compute endpoint")
    exit(1)
}

print("✅ Authentication successful")
print("✅ Compute endpoint: \(endpoint)")

// Now test server JSON decoding specifically
var serversRequest = URLRequest(url: URL(string: endpoint + "/servers/detail")!)
serversRequest.httpMethod = "GET"
serversRequest.addValue(authToken, forHTTPHeaderField: "X-Auth-Token")
serversRequest.addValue("application/json", forHTTPHeaderField: "Accept")

let serversSemaphore = DispatchSemaphore(value: 0)

URLSession.shared.dataTask(with: serversRequest) { data, response, error in
    defer { serversSemaphore.signal() }

    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200,
          let data = data else {
        print("❌ Servers request failed: \(error?.localizedDescription ?? "Unknown error")")
        print("Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        return
    }

    print("✅ Servers API call successful")

    // Test JSON decoding with our fixed Server struct
    do {
        struct ServerListResponse: Decodable {
            let servers: [Server]
        }

        let serverList = try JSONDecoder().decode(ServerListResponse.self, from: data)
        print("✅ JSON decoding successful! Found \(serverList.servers.count) servers")

        // Show details about each server to verify the fix
        for (index, server) in serverList.servers.enumerated() {
            print("  Server \(index + 1):")
            print("    ID: \(server.id)")
            print("    Name: \(server.name)")
            print("    Status: \(server.status ?? "unknown")")
            if let flavor = server.flavor {
                print("    Flavor ID: \(flavor.id)")
            } else {
                print("    Flavor: nil")
            }
            if let image = server.image {
                print("    Image ID: \(image.id)")
            } else {
                print("    Image: nil")
            }
            print("")
        }

    } catch {
        print("❌ JSON decoding failed: \(error)")

        // Print the raw JSON for debugging
        if let jsonString = String(data: data, encoding: .utf8) {
            print("Raw JSON response:")
            print(jsonString.prefix(1000))
        }
    }
}.resume()

serversSemaphore.wait()

print("🎉 Test completed!")