import Foundation
import OTClient

@main
struct OTUI {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        guard let authURLString = env["OS_AUTH_URL"],
              let authURL = URL(string: authURLString),
              let username = env["OS_USERNAME"],
              let password = env["OS_PASSWORD"],
              let projectName = env["OS_PROJECT_NAME"],
              let region = env["OS_REGION_NAME"] ?? env["OS_REGION"] else {
            printError("Missing required OpenStack environment variables")
            exit(1)
        }
        let userDomain = env["OS_USER_DOMAIN_NAME"] ?? "Default"
        let projectDomain = env["OS_PROJECT_DOMAIN_NAME"] ?? "Default"
        let config = OTConfig(authURL: authURL, region: region, projectName: projectName)
        let credentials: OTCredentials = .password(username: username, password: password, userDomain: userDomain, projectDomain: projectDomain)
        do {
            let client = try await OTClient.connect(config: config, credentials: credentials)
            let tui = TUI(client: client)
            await tui.run()
        } catch {
            printError("Error: \(error)")
            exit(1)
        }
    }

    static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
