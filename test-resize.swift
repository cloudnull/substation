#!/usr/bin/env swift

import Foundation
import OTClient

@main
struct TestResize {
    static func main() async {
        do {
            // Load cloud configuration
            guard let home = ProcessInfo.processInfo.environment["HOME"] else {
                print("❌ Could not determine home directory")
                return
            }

            let configPath = "\(home)/.config/openstack/clouds.yaml"
            let config = try CloudConfig.load(from: configPath)

            guard let cloud = config.clouds["rxt-sjc-mine-free"] else {
                print("❌ Cloud 'rxt-sjc-mine-free' not found in configuration")
                return
            }

            print("🔍 Connecting to cloud: rxt-sjc-mine-free")

            // Initialize client
            let client = OTClient(cloud: cloud)

            // Get servers to find the Test server
            print("📋 Fetching servers...")
            let servers = try await client.getServers()

            guard let testServer = servers.first(where: { $0.name == "Test" }) else {
                print("❌ Test server not found")
                print("Available servers:")
                for server in servers {
                    print("  - \(server.name ?? "unnamed") (\(server.id))")
                }
                return
            }

            print("✅ Found Test server: \(testServer.id)")
            print("   Status: \(testServer.status ?? "unknown")")
            if let flavor = testServer.flavor {
                print("   Current Flavor ID: \(flavor.id)")
            }

            // Get flavors to find target flavors
            print("📋 Fetching flavors...")
            let flavors = try await client.getFlavors()

            guard let currentFlavor = flavors.first(where: { $0.name == "gp.0.2.2" }) else {
                print("❌ Current flavor gp.0.2.2 not found")
                return
            }

            guard let targetFlavor = flavors.first(where: { $0.name == "gp.0.2.4" }) else {
                print("❌ Target flavor gp.0.2.4 not found")
                return
            }

            print("✅ Found current flavor: \(currentFlavor.name) (\(currentFlavor.id))")
            print("   vCPUs: \(currentFlavor.vcpus ?? 0), RAM: \(currentFlavor.ram ?? 0)MB")

            print("✅ Found target flavor: \(targetFlavor.name) (\(targetFlavor.id))")
            print("   vCPUs: \(targetFlavor.vcpus ?? 0), RAM: \(targetFlavor.ram ?? 0)MB")

            // Check if server is in correct state
            guard let status = testServer.status, ["ACTIVE", "SHUTOFF"].contains(status) else {
                print("❌ Server must be ACTIVE or SHUTOFF to resize (current: \(testServer.status ?? "unknown"))")
                return
            }

            print("🔄 Attempting to resize server from \(currentFlavor.name) to \(targetFlavor.name)...")

            // Perform the resize
            try await client.resizeServer(id: testServer.id, flavorRef: targetFlavor.id)

            print("✅ Resize request sent successfully!")
            print("🔍 Checking server status after resize request...")

            // Wait a moment for the status to update
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

            // Check the server status
            let updatedServers = try await client.getServers()
            if let updatedServer = updatedServers.first(where: { $0.id == testServer.id }) {
                print("📊 Updated server status: \(updatedServer.status ?? "unknown")")
                if let flavor = updatedServer.flavor {
                    print("   Flavor ID after resize: \(flavor.id)")
                    if let flavorDetails = flavors.first(where: { $0.id == flavor.id }) {
                        print("   Flavor name: \(flavorDetails.name)")
                    }
                }
            }

        } catch {
            print("❌ Error: \(error)")
            if let error = error as? OTError {
                switch error {
                case .httpError(let code):
                    print("   HTTP Error Code: \(code)")
                case .authenticationFailed:
                    print("   Authentication failed")
                case .endpointNotFound:
                    print("   Endpoint not found")
                case .unexpectedResponse:
                    print("   Unexpected response")
                }
            }
        }
    }
}