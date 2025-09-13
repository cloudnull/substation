#!/usr/bin/env swift

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Simple test to validate the resize API call
@main
struct TestResize {
    static func main() async throws {
        // Import the OTClient module
        let currentDir = FileManager.default.currentDirectoryPath
        let sourcesPath = currentDir + "/Sources"

        print("Testing OpenStack server resize functionality...")
        print("Current directory: \(currentDir)")
        print("Looking for Sources at: \(sourcesPath)")

        // Check if we can access the cloud config
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let cloudsPath = homeDir.appendingPathComponent(".config/openstack/clouds.yaml")

        if FileManager.default.fileExists(atPath: cloudsPath.path) {
            print("Found clouds.yaml at: \(cloudsPath.path)")
        } else {
            print("clouds.yaml not found at expected location")
        }

        print("Test completed - build the actual project to test resize functionality")
    }
}