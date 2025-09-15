import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OTConfig {
    public let authURL: URL
    public let region: String
    public let projectName: String
    public let projectDomain: String
    public let interface: String

    public init(authURL: URL, region: String, projectName: String, projectDomain: String, interface: String = "public") {
        self.authURL = authURL
        self.region = region
        self.projectName = projectName
        self.projectDomain = projectDomain
        self.interface = interface
    }
}

public enum OTCredentials {
    case password(username: String, password: String, userDomain: String, projectDomain: String)
    case applicationCredential(id: String, secret: String)
}

public struct OTClient: Sendable {
    public let token: String
    public let catalog: [CatalogEntry]
    public let region: String
    public let project: String
    public let preferredInterface: String

    public static func connect(config: OTConfig, credentials: OTCredentials) async throws -> OTClient {
        var request = URLRequest(url: config.authURL.appending(path: "/auth/tokens"))
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(AuthRequest(config: config, credentials: credentials))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201,
              let token = http.value(forHTTPHeaderField: "X-Subject-Token") else {
            throw OTError.authenticationFailed
        }
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        return OTClient(token: token, catalog: tokenResponse.token.catalog, region: config.region, project: config.projectName, preferredInterface: config.interface)
    }

    // MARK: - Generic helpers

    private func endpointURL(for service: String) throws -> URL {
        guard let entry = catalog.first(where: { $0.type == service }) else {
            throw OTError.endpointNotFound
        }

        let regionEndpoints = entry.endpoints.filter { $0.region == region }
        guard !regionEndpoints.isEmpty else {
            throw OTError.endpointNotFound
        }

        // Use preferred interface first, then fallback to public, internal, admin
        let endpoint = regionEndpoints.first { $0.interface == preferredInterface } ??
                      regionEndpoints.first { $0.interface == "public" } ??
                      regionEndpoints.first { $0.interface == "internal" } ??
                      regionEndpoints.first

        guard let finalEndpoint = endpoint else {
            throw OTError.endpointNotFound
        }

        guard let url = URL(string: finalEndpoint.url) else {
            throw OTError.endpointNotFound
        }

        return url
    }

    private func rawRequest(service: String, method: String, path: String, body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        var url = try endpointURL(for: service)
        url = url.appending(path: path)

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.addValue(token, forHTTPHeaderField: "X-Auth-Token")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        if let body = body {
            request.httpBody = body
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OTError.unexpectedResponse
        }

        guard http.statusCode < 400 else {
            throw OTError.httpError(http.statusCode)
        }

        return (data, http)
    }

    private func request<T: Decodable>(service: String, method: String, path: String, body: Data? = nil, expected: Int) async throws -> T {
        let (data, http) = try await rawRequest(service: service, method: method, path: path, body: body)
        guard http.statusCode == expected else {
            // For debugging, try to decode error message if possible
            if let errorString = String(data: data, encoding: .utf8) {
                print("HTTP \(http.statusCode) Error Response: \(errorString)")
            }
            throw OTError.httpError(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Enhanced debugging for JSON decode errors
            if let responseString = String(data: data, encoding: .utf8) {
                print("JSON Decode Error - Response: \(responseString)")
                print("Expected Type: \(T.self)")
                print("Decode Error: \(error)")
            }
            throw error
        }
    }

    private func requestVoid(service: String, method: String, path: String, body: Data? = nil, expected: Int) async throws {
        let (data, http) = try await rawRequest(service: service, method: method, path: path, body: body)
        guard http.statusCode == expected else {
            // For debugging, try to decode error message if possible
            if let errorString = String(data: data, encoding: .utf8) {
                print("HTTP \(http.statusCode) Error Response: \(errorString)")
            }
            throw OTError.httpError(http.statusCode)
        }
    }

    // MARK: - Servers (Nova)

    public func listServers() async throws -> [Server] {
        let decoded: ServerListResponse = try await request(service: "compute", method: "GET", path: "/servers/detail", expected: 200)
        return decoded.servers
    }

    public func getServer(id: String) async throws -> Server {
        let resp: ServerResponse = try await request(service: "compute", method: "GET", path: "/servers/\(id)", expected: 200)
        return resp.server
    }

    public func createServer(name: String, imageRef: String, flavorRef: String) async throws -> Server {
        return try await createServer(name: name, imageRef: imageRef, flavorRef: flavorRef, networkId: nil, keyPairName: nil)
    }

    public func createServer(name: String, imageRef: String, flavorRef: String, networkId: String?, keyPairName: String?) async throws -> Server {
        // Build networks array - only include if networkId is provided
        let networks: [CreateServerRequest.NetworkRef]? = networkId.map { [CreateServerRequest.NetworkRef(uuid: $0)] }

        let req = CreateServerRequest(server: .init(
            name: name,
            imageRef: imageRef,
            flavorRef: flavorRef,
            networks: networks,
            keyName: keyPairName
        ))

        let data = try JSONEncoder().encode(req)

        let resp: ServerResponse = try await request(service: "compute", method: "POST", path: "/servers", body: data, expected: 202)
        return resp.server
    }

    public func updateServer(id: String, name: String) async throws -> Server {
        let req = UpdateServerRequest(server: .init(name: name))
        let data = try JSONEncoder().encode(req)
        let resp: ServerResponse = try await request(service: "compute", method: "PUT", path: "/servers/\(id)", body: data, expected: 200)
        return resp.server
    }

    public func deleteServer(id: String) async throws {
        try await requestVoid(service: "compute", method: "DELETE", path: "/servers/\(id)", expected: 204)
    }

    // MARK: - Networks (Neutron)

    public func listNetworks() async throws -> [Network] {
        let resp: NetworkListResponse = try await request(service: "network", method: "GET", path: "/v2.0/networks", expected: 200)
        return resp.networks
    }

    public func getNetwork(id: String) async throws -> Network {
        let resp: NetworkResponse = try await request(service: "network", method: "GET", path: "/v2.0/networks/\(id)", expected: 200)
        return resp.network
    }

    public func createNetwork(name: String) async throws -> Network {
        let data = try JSONEncoder().encode(CreateNetworkRequest(network: .init(name: name)))
        let resp: NetworkResponse = try await request(service: "network", method: "POST", path: "/v2.0/networks", body: data, expected: 201)
        return resp.network
    }

    public func updateNetwork(id: String, name: String) async throws -> Network {
        let data = try JSONEncoder().encode(UpdateNetworkRequest(network: .init(name: name)))
        let resp: NetworkResponse = try await request(service: "network", method: "PUT", path: "/v2.0/networks/\(id)", body: data, expected: 200)
        return resp.network
    }

    public func deleteNetwork(id: String) async throws {
        try await requestVoid(service: "network", method: "DELETE", path: "/v2.0/networks/\(id)", expected: 204)
    }

    public func listPorts() async throws -> [Port] {
        let resp: PortListResponse = try await request(service: "network", method: "GET", path: "/v2.0/ports", expected: 200)
        return resp.ports
    }

    public func listSubnets() async throws -> [Subnet] {
        let resp: SubnetListResponse = try await request(service: "network", method: "GET", path: "/v2.0/subnets", expected: 200)
        return resp.subnets
    }

    public func listRouters() async throws -> [Router] {
        let resp: RouterListResponse = try await request(service: "network", method: "GET", path: "/v2.0/routers", expected: 200)
        return resp.routers
    }

    public func listFloatingIPs() async throws -> [FloatingIP] {
        let resp: FloatingIPListResponse = try await request(service: "network", method: "GET", path: "/v2.0/floatingips", expected: 200)
        return resp.floatingips
    }

    public func listSecurityGroups() async throws -> [SecurityGroup] {
        let resp: SecurityGroupListResponse = try await request(service: "network", method: "GET", path: "/v2.0/security-groups", expected: 200)
        return resp.securityGroups
    }

    // MARK: - Volumes (Cinder)

    public func listVolumes() async throws -> [Volume] {
        let resp: VolumeListResponse = try await request(service: "volumev3", method: "GET", path: "/volumes/detail", expected: 200)
        return resp.volumes
    }

    public func getVolume(id: String) async throws -> Volume {
        let resp: VolumeResponse = try await request(service: "volumev3", method: "GET", path: "/volumes/\(id)", expected: 200)
        return resp.volume
    }

    public func createVolume(name: String, size: Int) async throws -> Volume {
        let data = try JSONEncoder().encode(CreateVolumeRequest(volume: .init(name: name, size: size)))
        let resp: VolumeResponse = try await request(service: "volumev3", method: "POST", path: "/volumes", body: data, expected: 202)
        return resp.volume
    }

    public func updateVolume(id: String, name: String) async throws -> Volume {
        let data = try JSONEncoder().encode(UpdateVolumeRequest(volume: .init(name: name)))
        let resp: VolumeResponse = try await request(service: "volumev3", method: "PUT", path: "/volumes/\(id)", body: data, expected: 200)
        return resp.volume
    }

    public func deleteVolume(id: String) async throws {
        try await requestVoid(service: "volumev3", method: "DELETE", path: "/volumes/\(id)", expected: 202)
    }

    // MARK: - Images (Glance)

    public func listImages() async throws -> [Image] {
        let resp: ImageListResponse = try await request(service: "image", method: "GET", path: "/v2/images", expected: 200)
        return resp.images
    }

    public func getImage(id: String) async throws -> Image {
        try await request(service: "image", method: "GET", path: "/v2/images/\(id)", expected: 200)
    }

    public func createImage(name: String) async throws -> Image {
        let data = try JSONEncoder().encode(CreateImageRequest(name: name))
        return try await request(service: "image", method: "POST", path: "/v2/images", body: data, expected: 201)
    }

    public func updateImage(id: String, name: String) async throws -> Image {
        let ops = [ImagePatch(op: "replace", path: "/name", value: name)]
        let data = try JSONEncoder().encode(ops)
        return try await request(service: "image", method: "PATCH", path: "/v2/images/\(id)", body: data, expected: 200)
    }

    public func deleteImage(id: String) async throws {
        try await requestVoid(service: "image", method: "DELETE", path: "/v2/images/\(id)", expected: 204)
    }

    // MARK: - Day-2 Operations

    public func startServer(id: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["os-start": NSNull()], options: [])
        try await requestVoid(service: "compute", method: "POST", path: "/servers/\(id)/action", body: body, expected: 202)
    }

    public func stopServer(id: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["os-stop": NSNull()], options: [])
        try await requestVoid(service: "compute", method: "POST", path: "/servers/\(id)/action", body: body, expected: 202)
    }

    public func rebootServer(id: String, type: String = "SOFT") async throws {
        let body = try JSONSerialization.data(withJSONObject: ["reboot": ["type": type]], options: [])
        try await requestVoid(service: "compute", method: "POST", path: "/servers/\(id)/action", body: body, expected: 202)
    }

    public func resizeServer(id: String, flavorRef: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["resize": ["flavorRef": flavorRef]], options: [])
        try await requestVoid(service: "compute", method: "POST", path: "/servers/\(id)/action", body: body, expected: 202)
    }

    public func getConsoleOutput(id: String, length: Int? = nil) async throws -> String {
        var requestData: [String: Any] = ["os-getConsoleOutput": [:]]
        if let length = length {
            requestData["os-getConsoleOutput"] = ["length": length]
        }
        let body = try JSONSerialization.data(withJSONObject: requestData, options: [])
        let response: ConsoleOutputResponse = try await request(service: "compute", method: "POST", path: "/servers/\(id)/action", body: body, expected: 200)
        return response.output
    }

    public func addSecurityGroup(serverID: String, securityGroupName: String) async throws {
        let payload = ["addSecurityGroup": ["name": securityGroupName]]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        try await requestVoid(service: "compute", method: "POST", path: "/servers/\(serverID)/action", body: data, expected: 202)
    }

    public func removeSecurityGroup(serverID: String, securityGroupName: String) async throws {
        let payload = ["removeSecurityGroup": ["name": securityGroupName]]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        try await requestVoid(service: "compute", method: "POST", path: "/servers/\(serverID)/action", body: data, expected: 202)
    }

    public func getServerSecurityGroups(serverID: String) async throws -> [SecurityGroup] {
        let resp: ServerSecurityGroupsResponse = try await request(service: "compute", method: "GET", path: "/servers/\(serverID)/os-security-groups", expected: 200)
        return resp.securityGroups
    }

    public func attachPort(serverID: String, portID: String) async throws {
        let payload = AttachPortRequest(interfaceAttachment: .init(portID: portID))
        let data = try JSONEncoder().encode(payload)
        try await requestVoid(service: "compute", method: "POST", path: "/servers/\(serverID)/os-interface", body: data, expected: 200)
    }

    public func detachPort(serverID: String, portID: String) async throws {
        try await requestVoid(service: "compute", method: "DELETE", path: "/servers/\(serverID)/os-interface/\(portID)", expected: 202)
    }

    public func getServerInterfaces(serverID: String) async throws -> [ServerInterface] {
        let resp: ServerInterfacesResponse = try await request(service: "compute", method: "GET", path: "/servers/\(serverID)/os-interface", expected: 200)
        return resp.interfaceAttachments
    }

    public func createFloatingIP(networkID: String, portID: String? = nil) async throws -> FloatingIP {
        let data = try JSONEncoder().encode(CreateFloatingIPRequest(floatingip: .init(floatingNetworkID: networkID, portID: portID)))
        let resp: FloatingIPResponse = try await request(service: "network", method: "POST", path: "/v2.0/floatingips", body: data, expected: 201)
        return resp.floatingip
    }

    public func updateFloatingIP(id: String, portID: String?) async throws -> FloatingIP {
        let data = try JSONEncoder().encode(UpdateFloatingIPRequest(floatingip: .init(portID: portID)))
        let resp: FloatingIPResponse = try await request(service: "network", method: "PUT", path: "/v2.0/floatingips/\(id)", body: data, expected: 200)
        return resp.floatingip
    }

    public func deleteFloatingIP(id: String) async throws {
        try await requestVoid(service: "network", method: "DELETE", path: "/v2.0/floatingips/\(id)", expected: 204)
    }

    public func createSecurityGroupRule(securityGroupID: String, direction: String, protocol proto: String?, portRangeMin: Int?, portRangeMax: Int?, remoteIPPrefix: String?) async throws -> SecurityGroupRule {
        let payload = CreateSecurityGroupRuleRequest(securityGroupRule: .init(securityGroupID: securityGroupID, direction: direction, protocol: proto, portRangeMin: portRangeMin, portRangeMax: portRangeMax, remoteIPPrefix: remoteIPPrefix))
        let data = try JSONEncoder().encode(payload)
        let resp: SecurityGroupRuleResponse = try await request(service: "network", method: "POST", path: "/v2.0/security-group-rules", body: data, expected: 201)
        return resp.securityGroupRule
    }

    public func deleteSecurityGroupRule(id: String) async throws {
        try await requestVoid(service: "network", method: "DELETE", path: "/v2.0/security-group-rules/\(id)", expected: 204)
    }

    // MARK: - Quotas

    public func getComputeLimits() async throws -> ComputeLimits {
        let resp: ComputeLimitsResponse = try await request(service: "compute", method: "GET", path: "/limits", expected: 200)
        return resp.limits
    }

    public func getComputeQuotas(projectID: String? = nil) async throws -> ComputeQuotas {
        let path = projectID != nil ? "/os-quota-sets/\(projectID!)" : "/os-quota-sets/defaults"
        let resp: ComputeQuotaResponse = try await request(service: "compute", method: "GET", path: path, expected: 200)
        return resp.quotaSet
    }

    public func getNetworkQuotas(projectID: String? = nil) async throws -> NetworkQuotas {
        let path = projectID != nil ? "/v2.0/quotas/\(projectID!)" : "/v2.0/quotas/default"
        let resp: NetworkQuotaResponse = try await request(service: "network", method: "GET", path: path, expected: 200)
        return resp.quota
    }

    public func getVolumeQuotas(projectID: String? = nil) async throws -> VolumeQuotas {
        let path = projectID != nil ? "/os-quota-sets/\(projectID!)" : "/os-quota-sets/defaults"
        let resp: VolumeQuotaResponse = try await request(service: "volumev3", method: "GET", path: path, expected: 200)
        return resp.quotaSet
    }

    // MARK: - Flavors

    public func listFlavors() async throws -> [Flavor] {
        let resp: FlavorListResponse = try await request(service: "compute", method: "GET", path: "/flavors/detail", expected: 200)
        return resp.flavors
    }

    public func getFlavor(id: String) async throws -> Flavor {
        let resp: FlavorResponse = try await request(service: "compute", method: "GET", path: "/flavors/\(id)", expected: 200)
        return resp.flavor
    }

    public func listKeyPairs() async throws -> [KeyPair] {
        let resp: KeyPairListResponse = try await request(service: "compute", method: "GET", path: "/os-keypairs", expected: 200)
        return resp.keypairs.map { $0.keypair }
    }

    public func getKeyPair(name: String) async throws -> KeyPair {
        let resp: KeyPairResponse = try await request(service: "compute", method: "GET", path: "/os-keypairs/\(name)", expected: 200)
        return resp.keypair
    }
}

public enum OTError: Error {
    case authenticationFailed
    case endpointNotFound
    case unexpectedResponse
    case httpError(Int)
}

struct AuthRequest: Encodable {
    struct Auth: Encodable {
        let identity: Identity
        let scope: Scope
    }
    let auth: Auth

    init(config: OTConfig, credentials: OTCredentials) {
        self.auth = Auth(
            identity: Identity(methods: credentials.methods,
                               password: credentials.passwordCredentials,
                               applicationCredential: credentials.applicationCredential),
            scope: Scope(project: Project(name: config.projectName,
                                          domain: Domain(name: config.projectDomain)))
        )
    }

    struct Identity: Encodable {
        let methods: [String]
        let password: PasswordCredentials?
        let applicationCredential: ApplicationCredential?
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
    struct ApplicationCredential: Encodable {
        let id: String
        let secret: String
    }
    struct Scope: Encodable {
        let project: Project
    }
    struct Project: Encodable {
        let name: String
        let domain: Domain
    }
}

extension OTCredentials {
    var methods: [String] {
        switch self {
        case .password:
            return ["password"]
        case .applicationCredential:
            return ["application_credential"]
        }
    }

    var passwordCredentials: AuthRequest.PasswordCredentials? {
        switch self {
        case let .password(username, password, userDomain, _):
            return AuthRequest.PasswordCredentials(user: .init(name: username, domain: .init(name: userDomain), password: password))
        default:
            return nil
        }
    }

    var applicationCredential: AuthRequest.ApplicationCredential? {
        switch self {
        case let .applicationCredential(id, secret):
            return .init(id: id, secret: secret)
        default:
            return nil
        }
    }
}

struct TokenResponse: Decodable {
    struct Token: Decodable {
        let catalog: [CatalogEntry]
    }
    let token: Token
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

struct ServerListResponse: Decodable {
    let servers: [Server]
}

public struct Server: Decodable, Sendable {
    public let id: String
    public let name: String?
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
        name = try container.decodeIfPresent(String.self, forKey: .name)
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

struct ServerResponse: Decodable {
    let server: Server
}

struct ConsoleOutputResponse: Decodable {
    let output: String
}

struct CreateServerRequest: Encodable {
    struct NewServer: Encodable {
        let name: String
        let imageRef: String
        let flavorRef: String
        let networks: [NetworkRef]?
        let keyName: String?

        enum CodingKeys: String, CodingKey {
            case name, imageRef, flavorRef, networks
            case keyName = "key_name"
        }
    }

    struct NetworkRef: Encodable {
        let uuid: String
    }

    let server: NewServer
}

struct UpdateServerRequest: Encodable {
    struct Update: Encodable {
        let name: String
    }
    let server: Update
}

// MARK: Network Models

public struct Network: Decodable, Sendable {
    public let id: String
    public var name: String
    public let status: String?
    public let adminStateUp: Bool?
    public let shared: Bool?
    public let external: Bool?
    public let tenantId: String?
    public let subnets: [String]?
    public let availabilityZones: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name, status, shared, subnets
        case adminStateUp = "admin_state_up"
        case external = "router:external"
        case tenantId = "tenant_id"
        case availabilityZones = "availability_zones"
    }
}

struct NetworkListResponse: Decodable {
    let networks: [Network]
}

struct NetworkResponse: Decodable {
    let network: Network
}

struct CreateNetworkRequest: Encodable {
    struct Payload: Encodable {
        let name: String
    }
    let network: Payload
}

struct UpdateNetworkRequest: Encodable {
    struct Payload: Encodable {
        let name: String
    }
    let network: Payload
}

// MARK: Extended Network Models

public struct Port: Decodable, Sendable {
    public let id: String
    public let name: String?
    public let networkID: String
    public let deviceID: String?
    public let fixedIPs: [FixedIP]
    public let securityGroups: [String]

    enum CodingKeys: String, CodingKey {
        case id, name
        case networkID = "network_id"
        case deviceID = "device_id"
        case fixedIPs = "fixed_ips"
        case securityGroups = "security_groups"
    }

    public struct FixedIP: Decodable, Sendable {
        public let subnetID: String
        public let ipAddress: String

        enum CodingKeys: String, CodingKey {
            case subnetID = "subnet_id"
            case ipAddress = "ip_address"
        }
    }
}

struct PortListResponse: Decodable {
    let ports: [Port]
}

public struct ServerInterface: Decodable, Sendable {
    public let portID: String
    public let portState: String?
    public let netID: String
    public let macAddr: String?
    public let fixedIPs: [FixedIP]?

    enum CodingKeys: String, CodingKey {
        case portID = "port_id"
        case portState = "port_state"
        case netID = "net_id"
        case macAddr = "mac_addr"
        case fixedIPs = "fixed_ips"
    }

    public struct FixedIP: Decodable, Sendable {
        public let subnetID: String
        public let ipAddress: String

        enum CodingKeys: String, CodingKey {
            case subnetID = "subnet_id"
            case ipAddress = "ip_address"
        }
    }
}

struct ServerInterfacesResponse: Decodable {
    let interfaceAttachments: [ServerInterface]

    enum CodingKeys: String, CodingKey {
        case interfaceAttachments = "interfaceAttachments"
    }
}

public struct Subnet: Decodable, Sendable {
    public let id: String
    public let name: String?
    public let networkID: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case networkID = "network_id"
    }
}

struct SubnetListResponse: Decodable {
    let subnets: [Subnet]
}

public struct Router: Decodable, Sendable {
    public let id: String
    public let name: String?
}

struct RouterListResponse: Decodable {
    let routers: [Router]
}

public struct FloatingIP: Decodable, Sendable {
    public let id: String
    public let floatingIPAddress: String
    public let portID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case floatingIPAddress = "floating_ip_address"
        case portID = "port_id"
    }
}

struct FloatingIPListResponse: Decodable {
    let floatingips: [FloatingIP]
}

public struct SecurityGroup: Decodable, Sendable {
    public let id: String
    public let name: String
}

struct SecurityGroupListResponse: Decodable {
    let securityGroups: [SecurityGroup]

    enum CodingKeys: String, CodingKey {
        case securityGroups = "security_groups"
    }
}

struct ServerSecurityGroupsResponse: Decodable {
    let securityGroups: [SecurityGroup]

    enum CodingKeys: String, CodingKey {
        case securityGroups = "security_groups"
    }
}

// MARK: Volume Models

public struct Volume: Decodable, Sendable {
    public let id: String
    public var name: String?
    public let status: String?
    public let size: Int?
    public let volumeType: String?
    public let attachments: [Attachment]
    public let availabilityZone: String?
    public let createdAt: String?
    public let bootable: String?
    public let encrypted: Bool?
    public let metadata: [String: String]?

    public struct Attachment: Decodable, Sendable {
        public let serverId: String?
        public let device: String?
        public let attachmentId: String?

        enum CodingKeys: String, CodingKey {
            case serverId = "server_id"
            case device
            case attachmentId = "attachment_id"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, status, size, attachments, metadata, encrypted, bootable
        case volumeType = "volume_type"
        case availabilityZone = "availability_zone"
        case createdAt = "created_at"
    }
}

struct VolumeListResponse: Decodable {
    let volumes: [Volume]
}

struct VolumeResponse: Decodable {
    let volume: Volume
}

struct CreateVolumeRequest: Encodable {
    struct Payload: Encodable {
        let name: String
        let size: Int
    }
    let volume: Payload
}

struct UpdateVolumeRequest: Encodable {
    struct Payload: Encodable {
        let name: String
    }
    let volume: Payload
}

// MARK: Image Models

public struct Image: Decodable, Sendable {
    public let id: String
    public var name: String?
    public let status: String?
    public let visibility: String?
    public let size: Int?
    public let diskFormat: String?
    public let containerFormat: String?
    public let createdAt: String?
    public let updatedAt: String?
    public let minDisk: Int?
    public let minRam: Int?
    public let isPublic: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, status, visibility, size
        case diskFormat = "disk_format"
        case containerFormat = "container_format"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case minDisk = "min_disk"
        case minRam = "min_ram"
        case isPublic = "is_public"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        visibility = try container.decodeIfPresent(String.self, forKey: .visibility)
        size = try container.decodeIfPresent(Int.self, forKey: .size)
        diskFormat = try container.decodeIfPresent(String.self, forKey: .diskFormat)
        containerFormat = try container.decodeIfPresent(String.self, forKey: .containerFormat)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        minDisk = try container.decodeIfPresent(Int.self, forKey: .minDisk)
        minRam = try container.decodeIfPresent(Int.self, forKey: .minRam)

        // Handle isPublic more carefully - it might not exist or be a different type
        if let isPublicValue = try? container.decodeIfPresent(Bool.self, forKey: .isPublic) {
            isPublic = isPublicValue
        } else if let isPublicString = try? container.decodeIfPresent(String.self, forKey: .isPublic) {
            isPublic = isPublicString.lowercased() == "true"
        } else {
            isPublic = nil
        }
    }
}

struct ImageListResponse: Decodable {
    let images: [Image]
}

struct CreateImageRequest: Encodable {
    let name: String
}

struct ImagePatch: Encodable {
    let op: String
    let path: String
    let value: String
}

// MARK: Day-2 Model Types

struct AttachPortRequest: Encodable {
    struct InterfaceAttachment: Encodable {
        let portID: String

        enum CodingKeys: String, CodingKey {
            case portID = "port_id"
        }
    }
    let interfaceAttachment: InterfaceAttachment
}

struct CreateFloatingIPRequest: Encodable {
    struct Payload: Encodable {
        let floatingNetworkID: String
        let portID: String?

        enum CodingKeys: String, CodingKey {
            case floatingNetworkID = "floating_network_id"
            case portID = "port_id"
        }
    }
    let floatingip: Payload
}

struct UpdateFloatingIPRequest: Encodable {
    struct Payload: Encodable {
        let portID: String?

        enum CodingKeys: String, CodingKey {
            case portID = "port_id"
        }
    }
    let floatingip: Payload
}

struct FloatingIPResponse: Decodable {
    let floatingip: FloatingIP
}

public struct SecurityGroupRule: Decodable, Sendable {
    public let id: String
    public let direction: String
    public let protocolType: String?
    public let portRangeMin: Int?
    public let portRangeMax: Int?
    public let remoteIPPrefix: String?

    enum CodingKeys: String, CodingKey {
        case id, direction
        case protocolType = "protocol"
        case portRangeMin = "port_range_min"
        case portRangeMax = "port_range_max"
        case remoteIPPrefix = "remote_ip_prefix"
    }
}

struct CreateSecurityGroupRuleRequest: Encodable {
    struct Payload: Encodable {
        let securityGroupID: String
        let direction: String
        let `protocol`: String?
        let portRangeMin: Int?
        let portRangeMax: Int?
        let remoteIPPrefix: String?

        enum CodingKeys: String, CodingKey {
            case securityGroupID = "security_group_id"
            case direction
            case `protocol`
            case portRangeMin = "port_range_min"
            case portRangeMax = "port_range_max"
            case remoteIPPrefix = "remote_ip_prefix"
        }
    }
    let securityGroupRule: Payload

    enum CodingKeys: String, CodingKey {
        case securityGroupRule = "security_group_rule"
    }
}

struct SecurityGroupRuleResponse: Decodable {
    let securityGroupRule: SecurityGroupRule

    enum CodingKeys: String, CodingKey {
        case securityGroupRule = "security_group_rule"
    }
}

// MARK: - Quota Models

public struct ComputeQuotas: Decodable, Sendable {
    public let instances: Int?
    public let cores: Int?
    public let ram: Int?
    public let floatingIPs: Int?
    public let fixedIPs: Int?
    public let metadataItems: Int?
    public let injectedFiles: Int?
    public let injectedFileContentBytes: Int?
    public let injectedFilePathBytes: Int?
    public let keyPairs: Int?
    public let securityGroups: Int?
    public let securityGroupRules: Int?
    public let serverGroups: Int?
    public let serverGroupMembers: Int?

    enum CodingKeys: String, CodingKey {
        case instances, cores, ram
        case floatingIPs = "floating_ips"
        case fixedIPs = "fixed_ips"
        case metadataItems = "metadata_items"
        case injectedFiles = "injected_files"
        case injectedFileContentBytes = "injected_file_content_bytes"
        case injectedFilePathBytes = "injected_file_path_bytes"
        case keyPairs = "key_pairs"
        case securityGroups = "security_groups"
        case securityGroupRules = "security_group_rules"
        case serverGroups = "server_groups"
        case serverGroupMembers = "server_group_members"
    }
}

public struct NetworkQuotas: Decodable, Sendable {
    public let network: Int?
    public let subnet: Int?
    public let port: Int?
    public let router: Int?
    public let floatingip: Int?
    public let securityGroup: Int?
    public let securityGroupRule: Int?
    public let rbacPolicy: Int?

    enum CodingKeys: String, CodingKey {
        case network, subnet, port, router, floatingip
        case securityGroup = "security_group"
        case securityGroupRule = "security_group_rule"
        case rbacPolicy = "rbac_policy"
    }
}

public struct VolumeQuotas: Decodable, Sendable {
    public let volumes: Int?
    public let snapshots: Int?
    public let gigabytes: Int?
    public let backups: Int?
    public let backupGigabytes: Int?

    enum CodingKeys: String, CodingKey {
        case volumes, snapshots, gigabytes, backups
        case backupGigabytes = "backup_gigabytes"
    }
}

public struct ComputeLimits: Decodable, Sendable {
    public let absolute: AbsoluteLimits

    public struct AbsoluteLimits: Decodable, Sendable {
        public let totalInstancesUsed: Int?
        public let totalCoresUsed: Int?
        public let totalRAMUsed: Int?
        public let totalFloatingIpsUsed: Int?
        public let totalSecurityGroupsUsed: Int?
        public let maxTotalInstances: Int?
        public let maxTotalCores: Int?
        public let maxTotalRAMSize: Int?
        public let maxTotalFloatingIps: Int?
        public let maxSecurityGroups: Int?

        enum CodingKeys: String, CodingKey {
            case totalInstancesUsed, totalCoresUsed, totalRAMUsed
            case totalFloatingIpsUsed, totalSecurityGroupsUsed
            case maxTotalInstances, maxTotalCores, maxTotalRAMSize
            case maxTotalFloatingIps, maxSecurityGroups
        }
    }
}

struct ComputeLimitsResponse: Decodable {
    let limits: ComputeLimits
}

struct ComputeQuotaResponse: Decodable {
    let quotaSet: ComputeQuotas

    enum CodingKeys: String, CodingKey {
        case quotaSet = "quota_set"
    }
}

struct NetworkQuotaResponse: Decodable {
    let quota: NetworkQuotas
}

struct VolumeQuotaResponse: Decodable {
    let quotaSet: VolumeQuotas

    enum CodingKeys: String, CodingKey {
        case quotaSet = "quota_set"
    }
}

// MARK: - Flavor Models

public struct Flavor: Decodable, Sendable {
    public let id: String
    public let name: String
    public let vcpus: Int?
    public let ram: Int?
    public let disk: Int?
    public let ephemeral: Int?
    public let swap: String?
    public let rxtxFactor: Double?
    public let isPublic: Bool?
    public let disabled: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, vcpus, ram, disk, ephemeral, swap, disabled
        case rxtxFactor = "rxtx_factor"
        case isPublic = "os-flavor-access:is_public"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)

        // Handle vcpus as either Int or String
        if let vcpusInt = try? container.decode(Int.self, forKey: .vcpus) {
            vcpus = vcpusInt
        } else if let vcpusString = try? container.decode(String.self, forKey: .vcpus),
                  let vcpusInt = Int(vcpusString) {
            vcpus = vcpusInt
        } else {
            vcpus = nil
        }

        // Handle ram as either Int or String
        if let ramInt = try? container.decode(Int.self, forKey: .ram) {
            ram = ramInt
        } else if let ramString = try? container.decode(String.self, forKey: .ram),
                  let ramInt = Int(ramString) {
            ram = ramInt
        } else {
            ram = nil
        }

        // Handle disk as either Int or String
        if let diskInt = try? container.decode(Int.self, forKey: .disk) {
            disk = diskInt
        } else if let diskString = try? container.decode(String.self, forKey: .disk),
                  let diskInt = Int(diskString) {
            disk = diskInt
        } else {
            disk = nil
        }

        // Handle ephemeral as either Int or String
        if let ephemeralInt = try? container.decode(Int.self, forKey: .ephemeral) {
            ephemeral = ephemeralInt
        } else if let ephemeralString = try? container.decode(String.self, forKey: .ephemeral),
                  let ephemeralInt = Int(ephemeralString) {
            ephemeral = ephemeralInt
        } else {
            ephemeral = nil
        }

        // Handle swap as String or Int
        if let swapString = try? container.decode(String.self, forKey: .swap) {
            swap = swapString
        } else if let swapInt = try? container.decode(Int.self, forKey: .swap) {
            swap = String(swapInt)
        } else {
            swap = nil
        }

        // Handle rxtxFactor
        if let factor = try? container.decode(Double.self, forKey: .rxtxFactor) {
            rxtxFactor = factor
        } else if let factorString = try? container.decode(String.self, forKey: .rxtxFactor),
                  let factor = Double(factorString) {
            rxtxFactor = factor
        } else {
            rxtxFactor = nil
        }

        // Handle isPublic - might not exist in all responses
        isPublic = try? container.decode(Bool.self, forKey: .isPublic)

        // Handle disabled - might not exist in all responses
        disabled = try? container.decode(Bool.self, forKey: .disabled)
    }
}

struct FlavorListResponse: Decodable {
    let flavors: [Flavor]
}

struct FlavorResponse: Decodable {
    let flavor: Flavor
}

public struct KeyPair: Decodable, Sendable {
    public let name: String
    public let publicKey: String?
    public let fingerprint: String?
    public let type: String?

    enum CodingKeys: String, CodingKey {
        case name, fingerprint, type
        case publicKey = "public_key"
    }
}

struct KeyPairListResponse: Decodable {
    let keypairs: [KeyPairWrapper]
}

struct KeyPairWrapper: Decodable {
    let keypair: KeyPair
}

struct KeyPairResponse: Decodable {
    let keypair: KeyPair
}
