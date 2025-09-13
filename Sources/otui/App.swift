import Foundation
import OTClient

@main
struct OTUI {
    static func main() async {
        // Parse command line arguments
        let arguments = CommandLine.arguments
        var cloudName: String?
        var configPath: String?
        var listClouds = false
        var showHelp = false

        // Simple argument parsing - process all arguments first
        var i = 1
        while i < arguments.count {
            let arg = arguments[i]
            switch arg {
            case "--cloud", "-c":
                if i + 1 < arguments.count {
                    cloudName = arguments[i + 1]
                    i += 1
                } else {
                    printError("--cloud option requires a cloud name")
                    printUsage()
                    exit(1)
                }
            case "--config":
                if i + 1 < arguments.count {
                    configPath = arguments[i + 1]
                    i += 1
                } else {
                    printError("--config option requires a file path")
                    printUsage()
                    exit(1)
                }
            case "--list-clouds":
                listClouds = true
            case "--help", "-h":
                showHelp = true
            default:
                if !arg.hasPrefix("-") && cloudName == nil {
                    cloudName = arg
                } else {
                    printError("Unknown option: \(arg)")
                    printUsage()
                    exit(1)
                }
            }
            i += 1
        }

        // Handle special actions after all arguments are parsed
        if showHelp {
            printUsage()
            return
        }

        if listClouds {
            await listCloudsAction(configPath: configPath)
            return
        }

        let configManager = CloudConfigManager()

        // If no cloud specified, try to use first available cloud
        if cloudName == nil {
            do {
                let availableClouds = try configManager.listAvailableClouds(path: configPath)
                if availableClouds.isEmpty {
                    printError("No clouds found in configuration file")
                    printUsage()
                    exit(1)
                } else if availableClouds.count == 1 {
                    cloudName = availableClouds.first
                    print("Using cloud: \(cloudName!)")
                } else {
                    printError("Multiple clouds available. Please specify one with --cloud option.")
                    print("Available clouds: \(availableClouds.joined(separator: ", "))")
                    printUsage()
                    exit(1)
                }
            } catch {
                printError("Failed to load clouds configuration: \(error)")
                printUsage()
                exit(1)
            }
        }

        guard let selectedCloud = cloudName else {
            printError("No cloud specified")
            printUsage()
            exit(1)
        }

        // Load cloud configuration
        let cloudConfig: CloudConfig
        do {
            cloudConfig = try configManager.getCloudConfig(selectedCloud, path: configPath)
        } catch {
            printError("Failed to load cloud configuration: \(error)")
            printUsage()
            exit(1)
        }

        // Validate and convert configuration
        guard var authURL = URL(string: cloudConfig.auth.auth_url) else {
            printError("Invalid auth_url in cloud configuration: \(cloudConfig.auth.auth_url)")
            exit(1)
        }

        if authURL.path.isEmpty {
            authURL.appendPathComponent("v3")
        }

        guard let projectName = cloudConfig.auth.project_name else {
            printError("Missing project_name in cloud configuration")
            exit(1)
        }

        let region = cloudConfig.region_name ?? "RegionOne"
        let projectDomain = cloudConfig.auth.project_domain_name ?? "Default"
        let userDomain = cloudConfig.auth.user_domain_name ?? "Default"
        let interface = cloudConfig.interface ?? "public"

        let config = OTConfig(authURL: authURL, region: region, projectName: projectName, projectDomain: projectDomain, interface: interface)

        // Create credentials
        let credentials: OTCredentials
        if let appCredId = cloudConfig.auth.application_credential_id,
           let appCredSecret = cloudConfig.auth.application_credential_secret {
            credentials = .applicationCredential(id: appCredId, secret: appCredSecret)
        } else if let username = cloudConfig.auth.username,
                  let password = cloudConfig.auth.password {
            credentials = .password(username: username, password: password, userDomain: userDomain, projectDomain: projectDomain)
        } else {
            printError("Missing authentication credentials. Provide either username/password or application_credential_id/secret")
            exit(1)
        }

        do {
            print("\nConnecting to OpenStack cloud '\(selectedCloud)' at \(authURL)...\n")
            let client = try await OTClient.connect(config: config, credentials: credentials)

            let tui = TUI(client: client)
            await tui.run()
        } catch OTError.authenticationFailed {
            printError("Authentication failed. Please check your credentials in the clouds.yaml file.")
            printUsage()
            exit(1)
        } catch OTError.endpointNotFound {
            printError("Service endpoint not found. Please check your OpenStack region and service catalog.")
            exit(1)
        } catch {
            printError("Connection error: \(error)")
            exit(1)
        }
    }

    static func listCloudsAction(configPath: String?) async {
        let configManager = CloudConfigManager()
        do {
            let clouds = try configManager.listAvailableClouds(path: configPath)
            print("Available clouds:")
            for cloud in clouds {
                print("  \(cloud)")
            }
        } catch {
            printError("Failed to list clouds: \(error)")
            exit(1)
        }
    }

    static func printError(_ message: String) {
        FileHandle.standardError.write(Data("ERROR: \(message)\n".utf8))
    }

    static func printUsage() {
        let usage = """

        OTUI - OpenStack Terminal User Interface

        Usage:
          otui [options] [cloud-name]
          otui --list-clouds

        Options:
          -c, --cloud <name>     Specify cloud name from clouds.yaml
          --config <path>        Path to clouds.yaml file (default: ~/.config/openstack/clouds.yaml)
          --list-clouds          List available clouds in configuration
          -h, --help            Show this help message

        Configuration:
          OTUI uses the standard OpenStack clouds.yaml configuration file.
          Default location: ~/.config/openstack/clouds.yaml

        Example clouds.yaml:
          clouds:
            mycloud:
              auth:
                auth_url: https://identity.example.com:5000/v3
                username: admin
                password: secretpassword
                project_name: admin
                user_domain_name: Default
                project_domain_name: Default
              region_name: RegionOne

        Examples:
          otui                     # Use first/only cloud in configuration
          otui mycloud             # Use specific cloud
          otui --cloud mycloud     # Use specific cloud (alternative syntax)
          otui --list-clouds       # List available clouds
          otui --config ./my-clouds.yaml mycloud  # Use custom config file

        """
        print(usage)
    }
}
