import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OTConfig {
    public let authURL: URL
    public let region: String
    public let projectName: String

    public init(authURL: URL, region: String, projectName: String) {
        self.authURL = authURL
        self.region = region
        self.projectName = projectName
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
        return OTClient(token: token, catalog: tokenResponse.token.catalog, region: config.region, project: config.projectName)
    }

    // MARK: - Generic helpers

    private func endpointURL(for service: String) throws -> URL {
        guard let entry = catalog.first(where: { $0.type == service }),
              let endpoint = entry.endpoints.first(where: { $0.region == region }),
              let url = URL(string: endpoint.url) else {
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
        return (data, http)
    }

    private func request<T: Decodable>(service: String, method: String, path: String, body: Data? = nil, expected: Int) async throws -> T {
        let (data, http) = try await rawRequest(service: service, method: method, path: path, body: body)
        guard http.statusCode == expected else {
            throw OTError.unexpectedResponse
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func requestVoid(service: String, method: String, path: String, body: Data? = nil, expected: Int) async throws {
        let (_, http) = try await rawRequest(service: service, method: method, path: path, body: body)
        guard http.statusCode == expected else {
            throw OTError.unexpectedResponse
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
        let req = CreateServerRequest(server: .init(name: name, imageRef: imageRef, flavorRef: flavorRef))
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
        let resp: NetworkListResponse = try await request(service: "network", method: "GET", path: "/networks", expected: 200)
        return resp.networks
    }

    public func getNetwork(id: String) async throws -> Network {
        let resp: NetworkResponse = try await request(service: "network", method: "GET", path: "/networks/\(id)", expected: 200)
        return resp.network
    }

    public func createNetwork(name: String) async throws -> Network {
        let data = try JSONEncoder().encode(CreateNetworkRequest(network: .init(name: name)))
        let resp: NetworkResponse = try await request(service: "network", method: "POST", path: "/networks", body: data, expected: 201)
        return resp.network
    }

    public func updateNetwork(id: String, name: String) async throws -> Network {
        let data = try JSONEncoder().encode(UpdateNetworkRequest(network: .init(name: name)))
        let resp: NetworkResponse = try await request(service: "network", method: "PUT", path: "/networks/\(id)", body: data, expected: 200)
        return resp.network
    }

    public func deleteNetwork(id: String) async throws {
        try await requestVoid(service: "network", method: "DELETE", path: "/networks/\(id)", expected: 204)
    }

    public func listPorts() async throws -> [Port] {
        let resp: PortListResponse = try await request(service: "network", method: "GET", path: "/ports", expected: 200)
        return resp.ports
    }

    public func listSubnets() async throws -> [Subnet] {
        let resp: SubnetListResponse = try await request(service: "network", method: "GET", path: "/subnets", expected: 200)
        return resp.subnets
    }

    public func listRouters() async throws -> [Router] {
        let resp: RouterListResponse = try await request(service: "network", method: "GET", path: "/routers", expected: 200)
        return resp.routers
    }

    public func listFloatingIPs() async throws -> [FloatingIP] {
        let resp: FloatingIPListResponse = try await request(service: "network", method: "GET", path: "/floatingips", expected: 200)
        return resp.floatingips
    }

    public func listSecurityGroups() async throws -> [SecurityGroup] {
        let resp: SecurityGroupListResponse = try await request(service: "network", method: "GET", path: "/security-groups", expected: 200)
        return resp.securityGroups
    }

    // MARK: - Volumes (Cinder)

    public func listVolumes() async throws -> [Volume] {
        let resp: VolumeListResponse = try await request(service: "volumev3", method: "GET", path: "/volumes", expected: 200)
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

    public func attachPort(serverID: String, portID: String) async throws {
        let payload = AttachPortRequest(interfaceAttachment: .init(portID: portID))
        let data = try JSONEncoder().encode(payload)
        try await requestVoid(service: "compute", method: "POST", path: "/servers/\(serverID)/os-interface", body: data, expected: 200)
    }

    public func createFloatingIP(networkID: String, portID: String? = nil) async throws -> FloatingIP {
        let data = try JSONEncoder().encode(CreateFloatingIPRequest(floatingip: .init(floatingNetworkID: networkID, portID: portID)))
        let resp: FloatingIPResponse = try await request(service: "network", method: "POST", path: "/floatingips", body: data, expected: 201)
        return resp.floatingip
    }

    public func updateFloatingIP(id: String, portID: String?) async throws -> FloatingIP {
        let data = try JSONEncoder().encode(UpdateFloatingIPRequest(floatingip: .init(portID: portID)))
        let resp: FloatingIPResponse = try await request(service: "network", method: "PUT", path: "/floatingips/\(id)", body: data, expected: 200)
        return resp.floatingip
    }

    public func deleteFloatingIP(id: String) async throws {
        try await requestVoid(service: "network", method: "DELETE", path: "/floatingips/\(id)", expected: 204)
    }

    public func createSecurityGroupRule(securityGroupID: String, direction: String, protocol proto: String?, portRangeMin: Int?, portRangeMax: Int?, remoteIPPrefix: String?) async throws -> SecurityGroupRule {
        let payload = CreateSecurityGroupRuleRequest(securityGroupRule: .init(securityGroupID: securityGroupID, direction: direction, protocol: proto, portRangeMin: portRangeMin, portRangeMax: portRangeMax, remoteIPPrefix: remoteIPPrefix))
        let data = try JSONEncoder().encode(payload)
        let resp: SecurityGroupRuleResponse = try await request(service: "network", method: "POST", path: "/security-group-rules", body: data, expected: 201)
        return resp.securityGroupRule
    }

    public func deleteSecurityGroupRule(id: String) async throws {
        try await requestVoid(service: "network", method: "DELETE", path: "/security-group-rules/\(id)", expected: 204)
    }
}

public enum OTError: Error {
    case authenticationFailed
    case endpointNotFound
    case unexpectedResponse
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
            scope: Scope(project: Project(name: config.projectName))
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
    public let name: String
}

struct ServerResponse: Decodable {
    let server: Server
}

struct CreateServerRequest: Encodable {
    struct NewServer: Encodable {
        let name: String
        let imageRef: String
        let flavorRef: String
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

// MARK: Volume Models

public struct Volume: Decodable, Sendable {
    public let id: String
    public var name: String?
    public let attachments: [Attachment]

    public struct Attachment: Decodable, Sendable {
        public let serverId: String?

        enum CodingKeys: String, CodingKey {
            case serverId = "server_id"
        }
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
