import Foundation
import OTClient

let env = ProcessInfo.processInfo.environment
guard let authURLString = env["OS_AUTH_URL"],
      let authURL = URL(string: authURLString),
      let username = env["OS_USERNAME"],
      let password = env["OS_PASSWORD"],
      let projectName = env["OS_PROJECT_NAME"] else {
    print("Missing required environment variables")
    exit(1)
}

let region = env["OS_REGION_NAME"] ?? "RegionOne"
let userDomain = env["OS_USER_DOMAIN_NAME"] ?? "Default"
let projectDomain = env["OS_PROJECT_DOMAIN_NAME"] ?? "Default"

let config = OTConfig(authURL: authURL, region: region, projectName: projectName, projectDomain: projectDomain)
let credentials: OTCredentials = .password(username: username, password: password, userDomain: userDomain, projectDomain: projectDomain)

do {
    print("Connecting to OpenStack...")
    let client = try await OTClient.connect(config: config, credentials: credentials)
    print("Connected successfully!")

    print("Testing server list...")
    let servers = try await client.listServers()
    print("Got \(servers.count) servers")

    for server in servers.prefix(3) {
        print("  - \(server.name) (\(server.id))")
    }

} catch {
    print("Error: \(error)")
    exit(1)
}