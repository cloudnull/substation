#!/usr/bin/env swift

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Test script to verify all endpoints work
struct TestResult {
    let service: String
    let success: Bool
    let count: Int
    let error: String?
}

// Copy auth structures
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

print("🧪 Testing OpenStack API endpoints...")

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
        print("❌ Auth failed")
        return
    }
    
    token = authToken
    
    do {
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        catalog = tokenResponse.token.catalog
    } catch {
        print("❌ Failed to parse token response: \(error)")
    }
}.resume()

semaphore.wait()

guard let authToken = token else {
    print("❌ Failed to get token")
    exit(1)
}

print("✅ Authentication successful")

// Test each service
let tests = [
    ("servers", "compute", "/servers/detail"),
    ("networks", "network", "/v2.0/networks"),
    ("volumes", "volumev3", "/volumes/detail"),
    ("images", "image", "/v2/images")
]

var results: [TestResult] = []

for (resourceName, serviceName, path) in tests {
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
    
    guard let endpoint = serviceEndpoint else {
        results.append(TestResult(service: resourceName, success: false, count: 0, error: "No endpoint found"))
        continue
    }
    
    let fullURL = endpoint + path
    print("🔍 Testing \(resourceName) at: \(fullURL)")
    
    var resourceRequest = URLRequest(url: URL(string: fullURL)!)
    resourceRequest.httpMethod = "GET"
    resourceRequest.addValue(authToken, forHTTPHeaderField: "X-Auth-Token")
    resourceRequest.addValue("application/json", forHTTPHeaderField: "Accept")
    
    let resourceSemaphore = DispatchSemaphore(value: 0)
    
    URLSession.shared.dataTask(with: resourceRequest) { data, response, error in
        defer { resourceSemaphore.signal() }
        
        guard let httpResponse = response as? HTTPURLResponse,
              let data = data else {
            results.append(TestResult(service: resourceName, success: false, count: 0, error: "Request failed"))
            return
        }
        
        if httpResponse.statusCode != 200 {
            results.append(TestResult(service: resourceName, success: false, count: 0, error: "HTTP \(httpResponse.statusCode)"))
            return
        }
        
        // Parse JSON to count items
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var count = 0
                
                // Find the main array in the response
                for (key, value) in json {
                    if let array = value as? [[String: Any]] {
                        count = array.count
                        break
                    }
                }
                
                results.append(TestResult(service: resourceName, success: true, count: count, error: nil))
            } else {
                results.append(TestResult(service: resourceName, success: false, count: 0, error: "Invalid JSON"))
            }
        } catch {
            results.append(TestResult(service: resourceName, success: false, count: 0, error: "JSON parse error"))
        }
    }.resume()
    
    resourceSemaphore.wait()
}

// Print results
print("\n📊 Test Results:")
print("================")

for result in results {
    let status = result.success ? "✅" : "❌"
    let message = result.success ? "\(result.count) items" : result.error ?? "Unknown error"
    print("\(status) \(result.service.capitalized): \(message)")
}

let successCount = results.filter { $0.success }.count
print("\n🎯 Summary: \(successCount)/\(results.count) services working correctly")

if successCount == results.count {
    print("🎉 All OpenStack API endpoints are working!")
} else {
    print("⚠️  Some services need attention")
}