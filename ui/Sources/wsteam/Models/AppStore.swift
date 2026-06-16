import SwiftUI
import Combine

@MainActor
final class AppStore: ObservableObject {
    @Published var status: StatusPayload?
    @Published var games: [GameInfo] = []
    @Published var isLoading = false
    @Published var setupProgress: SetupProgress = .idle
    @Published var errorMessage: String?
    @Published var appState: AppState = .launching

    private let client = DaemonClient()
    private var daemonProcess: Process?

    enum AppState {
        case launching          // first seconds — starting daemon
        case needsSetup         // wine/steam not installed
        case ready              // everything installed, show library
    }

    enum SetupProgress {
        case idle
        case running(step: String, pct: Double)
        case done
        case failed(String)
    }

    init() {
        Task { await boot() }
    }

    // MARK: - Boot sequence

    private func boot() async {
        appState = .launching
        startDaemonProcess()
        // Give daemon time to start
        try? await Task.sleep(nanoseconds: 1_800_000_000)
        await refreshStatus()

        if let s = status, s.wineInstalled && s.steamInstalled {
            appState = .ready
            await refreshLibrary()
        } else {
            appState = .needsSetup
        }
    }

    private func startDaemonProcess() {
        // Kill stale daemon first
        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        kill.arguments = ["-x", "wsteamd"]
        try? kill.run()

        let candidates = [
            Bundle.main.bundlePath + "/Contents/MacOS/wsteamd",
            "/usr/local/bin/wsteamd",
            FileManager.default.currentDirectoryPath + "/target/release/wsteamd",
        ]

        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            errorMessage = "wsteamd not found. Run `make install` once from Terminal."
            return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice
        try? p.run()
        daemonProcess = p
    }

    // MARK: - Status

    func refreshStatus() async {
        status = try? await client.getStatus()
    }

    // MARK: - Setup

    func runFullSetup() async {
        isLoading = true
        setupProgress = .running(step: "Downloading Wine Crossover...", pct: 5)
        do {
            try await client.setupWine()
            setupProgress = .running(step: "Creating Windows prefix...", pct: 38)
            try await client.setupSteam()
            setupProgress = .running(step: "Installing DXVK + MoltenVK...", pct: 78)
            try await client.setupDxvk()
            setupProgress = .done
            await refreshStatus()
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            appState = .ready
            await refreshLibrary()
        } catch {
            setupProgress = .failed(error.localizedDescription)
        }
        isLoading = false
    }

    // MARK: - Library

    func refreshLibrary() async {
        games = (try? await client.scanLibrary()) ?? []
    }

    // MARK: - Game actions

    func launchSteam() async {
        isLoading = true
        do { try await client.launchSteam() }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    func launch(game: GameInfo) async {
        isLoading = true
        do { try await client.launchGame(game.appId) }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    func killWineserver() async {
        try? await client.killWineserver()
    }

    func clearError() { errorMessage = nil }

    // MARK: - Folder access

    func openGameFolder(_ game: GameInfo) async {
        do {
            let f = try await client.getGameFolder(game.appId)
            if f.exists { try await client.openInFinder(path: f.path) }
            else { errorMessage = "Folder not found. Install the game in Steam first.\n\(f.path)" }
        } catch { errorMessage = error.localizedDescription }
    }

    func openSteamFolder() async {
        do {
            let f = try await client.getSteamFolder()
            if f.exists { try await client.openInFinder(path: f.path) }
            else { errorMessage = "steamapps/common not found. Install Steam first." }
        } catch { errorMessage = error.localizedDescription }
    }

    func openPrefixFolder() async {
        do {
            let f = try await client.getPrefixFolder()
            try await client.openInFinder(path: f.path)
        } catch { errorMessage = error.localizedDescription }
    }

    func copyFolderPath(for game: GameInfo) async -> String? {
        try? await client.getGameFolder(game.appId).path
    }
}
