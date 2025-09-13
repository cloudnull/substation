#!/usr/bin/env swift

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Simple debug script to inspect server JSON response
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

struct CatalogEntry: Decodable {
    struct Endpoint: Decodable {
        let region: String
        let url: String
        let interface: String
    }
    let type: String
    let name: String
    let endpoints: [Endpoint]
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

// Authenticate
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
var catalog: [CatalogEntry] = []

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
        catalog = tokenResponse.token.catalog
    } catch {
        print("Failed to parse token response: \(error)")
    }
}.resume()

semaphore.wait()

guard let authToken = token else {
    print("Failed to get token")
    exit(1)
}

print("Authenticated successfully")

// Now fetch all resources to see which one is causing the issue
let resources = [
    ("servers", "/servers/detail"),
    ("networks", "/v2.0/networks"),
    ("volumes", "/volumes/detail"),
    ("images", "/v2/images")
]

let services = [
    ("servers", "compute"),
    ("networks", "network"),
    ("volumes", "volumev3"),
    ("images", "image")
]

for (resourceName, serviceName) in services {
    var serviceEndpoint: String?

    // Find endpoint
    for service in catalog {
        if service.type == serviceName {
            for ep in service.endpoints {
                if ep.region == region && ep.interface == "public" {
                    serviceEndpoint = ep.url
                    break
                }
            }
        }
    }

    guard let finalEndpoint = serviceEndpoint else {
        print("No \(serviceName) endpoint found")
        continue
    }

    let path = resources.first { $0.0 == resourceName }?.1 ?? ""
    let fullURL = finalEndpoint + path

    print("\nFetching \(resourceName) from: \(fullURL)")

    var resourceRequest = URLRequest(url: URL(string: fullURL)!)
    resourceRequest.httpMethod = "GET"
    resourceRequest.addValue(authToken, forHTTPHeaderField: "X-Auth-Token")
    resourceRequest.addValue("application/json", forHTTPHeaderField: "Accept")

    let resourceSemaphore = DispatchSemaphore(value: 0)

    URLSession.shared.dataTask(with: resourceRequest) { data, response, error in
        defer { resourceSemaphore.signal() }

        guard let httpResponse = response as? HTTPURLResponse,
              let data = data else {
            print("\(resourceName) request failed: \(error?.localizedDescription ?? "Unknown error")")
            print("Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            return
        }

        if httpResponse.statusCode != 200 {
            print("\(resourceName) request failed with status: \(httpResponse.statusCode)")
            if let errorStr = String(data: data, encoding: .utf8) {
                print("Error response: \(errorStr)")
            }
            return
        }

        // Try to parse as generic JSON to see structure
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for (key, value) in json {
                    if let array = value as? [[String: Any]] {
                        print("\n\(resourceName) -> \(key): \(array.count) items")

                        // Show first few items structure
                        for (index, item) in array.prefix(3).enumerated() {
                            print("  Item \(index):")
                            for (itemKey, itemValue) in item {
                                print("    \(itemKey): \(type(of: itemValue))")
                                if itemKey == "flavor" || itemKey == "image" {
                                    print("      Value: \(itemValue)")
                                }
                            }
                        }
                    } else {
                        print("\n\(resourceName) -> \(key): \(type(of: value))")
                    }
                }
            }
        } catch {
            print("Failed to parse \(resourceName) JSON: \(error)")
            // Print raw response for debugging
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Raw response: \(jsonString.prefix(500))")
            }
        }
    }.resume()

    resourceSemaphore.wait()
}