import Foundation

// JSON-RPC over Unix socket to wsteamd
actor DaemonClient {
    private let socketPath = "/tmp/wsteam.sock"
    private var connection: FileHandle?

    func sendCommand(_ cmd: WCommand) async throws -> WResponse {
        let data = try JSONEncoder().encode(cmd)
        var json = String(data: data, encoding: .utf8)!
        json += "\n"

        guard let jsonData = json.data(using: .utf8) else {
            throw WsteamError.encodingFailed
        }

        // Connect via BSD socket
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw WsteamError.connectionFailed }

        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        // Use withUnsafeMutableBytes to set sun_path without exclusivity conflict
        let pathBytes = Array(socketPath.utf8) + [UInt8(0)]
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            buf.copyBytes(from: pathBytes.prefix(buf.count))
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { throw WsteamError.connectionFailed }

        // Send command
        let sent = jsonData.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard sent > 0 else { throw WsteamError.writeFailed }

        // Read response line
        var responseData = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            responseData.append(contentsOf: buf[0..<n])
            if responseData.contains(0x0A) { break } // newline
        }

        // Strip newline
        if let nl = responseData.firstIndex(of: 0x0A) {
            responseData = responseData[responseData.startIndex..<nl]
        }

        return try JSONDecoder().decode(WResponse.self, from: responseData)
    }

    // Convenience helpers
    func getStatus() async throws -> StatusPayload {
        let resp = try await sendCommand(.getStatus)
        guard case .status(let s) = resp else { throw WsteamError.unexpectedResponse }
        return s
    }

    func fullSetup() async throws {
        let resp = try await sendCommand(.fullSetup)
        if case .error(let msg) = resp { throw WsteamError.remote(msg) }
    }

    func setupWine() async throws {
        let resp = try await sendCommand(.setupWine)
        if case .error(let msg) = resp { throw WsteamError.remote(msg) }
    }

    func setupSteam() async throws {
        let resp = try await sendCommand(.setupSteam)
        if case .error(let msg) = resp { throw WsteamError.remote(msg) }
    }

    func setupDxvk() async throws {
        let resp = try await sendCommand(.setupDxvk)
        if case .error(let msg) = resp { throw WsteamError.remote(msg) }
    }

    func launchSteam() async throws {
        let resp = try await sendCommand(.launchSteam)
        if case .error(let msg) = resp { throw WsteamError.remote(msg) }
    }

    func launchGame(_ appId: UInt64) async throws {
        let resp = try await sendCommand(.launchGame(appId: appId))
        if case .error(let msg) = resp { throw WsteamError.remote(msg) }
    }

    func scanLibrary() async throws -> [GameInfo] {
        let resp = try await sendCommand(.scanLibrary)
        guard case .library(let games) = resp else { throw WsteamError.unexpectedResponse }
        return games
    }

    func killWineserver() async throws {
        _ = try await sendCommand(.killWineserver)
    }
}

// MARK: - IPC Types

enum WCommand: Encodable {
    case getStatus
    case setupWine
    case setupSteam
    case setupDxvk
    case fullSetup
    case launchSteam
    case launchGame(appId: UInt64)
    case scanLibrary
    case killWineserver
    case getGameFolder(appId: UInt64)
    case getPrefixFolder
    case getSteamFolder
    case openInFinder(path: String)

    enum CodingKeys: String, CodingKey { case cmd, data }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .getStatus:   try c.encode("GetStatus", forKey: .cmd)
        case .setupWine:   try c.encode("SetupWine", forKey: .cmd)
        case .setupSteam:  try c.encode("SetupSteam", forKey: .cmd)
        case .setupDxvk:   try c.encode("SetupDxvk", forKey: .cmd)
        case .fullSetup:   try c.encode("FullSetup", forKey: .cmd)
        case .launchSteam: try c.encode("LaunchSteam", forKey: .cmd)
        case .launchGame(let id):
            try c.encode("LaunchGame", forKey: .cmd)
            var d = c.nestedContainer(keyedBy: GameDataKeys.self, forKey: .data)
            try d.encode(id, forKey: .appId)
        case .scanLibrary:    try c.encode("ScanLibrary", forKey: .cmd)
        case .killWineserver: try c.encode("KillWineserver", forKey: .cmd)
        case .getGameFolder(let id):
            try c.encode("GetGameFolder", forKey: .cmd)
            var d = c.nestedContainer(keyedBy: GameDataKeys.self, forKey: .data)
            try d.encode(id, forKey: .appId)
        case .getPrefixFolder:  try c.encode("GetPrefixFolder", forKey: .cmd)
        case .getSteamFolder:   try c.encode("GetSteamFolder", forKey: .cmd)
        case .openInFinder(let path):
            try c.encode("OpenFolderInFinder", forKey: .cmd)
            var d = c.nestedContainer(keyedBy: PathKeys.self, forKey: .data)
            try d.encode(path, forKey: .path)
        }
    }

    private enum GameDataKeys: String, CodingKey { case appId = "app_id" }
    private enum PathKeys: String, CodingKey { case path }
}

enum WResponse: Decodable {
    case ok
    case status(StatusPayload)
    case library([GameInfo])
    case config(String)
    case error(String)
    case progress(step: String, pct: Int)
    case folder(FolderPayload)

    enum CodingKeys: String, CodingKey { case type, data }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let t = try c.decode(String.self, forKey: .type)
        switch t {
        case "Ok":       self = .ok
        case "Status":   self = .status(try c.decode(StatusPayload.self, forKey: .data))
        case "Library":  self = .library(try c.decode([GameInfo].self, forKey: .data))
        case "Error":
            let d = try c.decode(ErrorData.self, forKey: .data)
            self = .error(d.message)
        case "Folder":
            self = .folder(try c.decode(FolderPayload.self, forKey: .data))
        default:         self = .ok
        }
    }

    private struct ErrorData: Decodable { let message: String }
}

extension WResponse {
    var folderPayload: FolderPayload? {
        if case .folder(let f) = self { return f }
        return nil
    }
}

struct StatusPayload: Decodable {
    let wineInstalled: Bool
    let wineVersion: String
    let steamInstalled: Bool
    let dxvkInstalled: Bool
    let moltenVkInstalled: Bool
    let prefixExists: Bool
    let daemonVersion: String

    enum CodingKeys: String, CodingKey {
        case wineInstalled = "wine_installed"
        case wineVersion = "wine_version"
        case steamInstalled = "steam_installed"
        case dxvkInstalled = "dxvk_installed"
        case moltenVkInstalled = "moltenvk_installed"
        case prefixExists = "prefix_exists"
        case daemonVersion = "daemon_version"
    }
}

struct GameInfo: Decodable, Identifiable {
    var id: UInt64 { appId }
    let appId: UInt64
    let name: String
    let installDir: String

    enum CodingKeys: String, CodingKey {
        case appId = "app_id"
        case name
        case installDir = "install_dir"
    }
}

enum WsteamError: LocalizedError {
    case connectionFailed
    case encodingFailed
    case writeFailed
    case unexpectedResponse
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed:    return "Cannot connect to wsteamd. Make sure the daemon is running."
        case .encodingFailed:      return "Failed to encode command"
        case .writeFailed:         return "Failed to send command"
        case .unexpectedResponse:  return "Unexpected response from daemon"
        case .remote(let msg):     return msg
        }
    }
}

struct FolderPayload: Decodable {
    let path: String
    let exists: Bool
    let label: String
}

// MARK: - DaemonClient folder helpers
extension DaemonClient {
    func getGameFolder(_ appId: UInt64) async throws -> FolderPayload {
        let resp = try await sendCommand(.getGameFolder(appId: appId))
        guard let f = resp.folderPayload else { throw WsteamError.unexpectedResponse }
        return f
    }

    func getPrefixFolder() async throws -> FolderPayload {
        let resp = try await sendCommand(.getPrefixFolder)
        guard let f = resp.folderPayload else { throw WsteamError.unexpectedResponse }
        return f
    }

    func getSteamFolder() async throws -> FolderPayload {
        let resp = try await sendCommand(.getSteamFolder)
        guard let f = resp.folderPayload else { throw WsteamError.unexpectedResponse }
        return f
    }

    func openInFinder(path: String) async throws {
        _ = try await sendCommand(.openInFinder(path: path))
    }
}
