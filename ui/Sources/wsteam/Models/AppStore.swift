import SwiftUI

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
        case launching
        case needsSetup
        case ready
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

    // MARK: - Boot

    func boot() async {
        appState = .launching
        killStaleDaemon()
        guard let daemonURL = findDaemon() else {
            // Daemon not bundled — show a friendly one-time setup message
            appState = .needsSetup
            setupProgress = .failed(
                "wsteamd binary not found next to the app.\n" +
                "Run once in Terminal:\n\n  make install\n\nThen reopen the app."
            )
            return
        }

        startDaemon(at: daemonURL)
        // Poll until daemon responds (max 5 s)
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if let s = try? await client.getStatus() {
                status = s
                break
            }
        }

        if status == nil {
            appState = .needsSetup
            setupProgress = .failed("Daemon started but isn't responding. Try quitting and reopening the app.")
            return
        }

        if let s = status, s.wineInstalled && s.steamInstalled {
            appState = .ready
            await refreshLibrary()
        } else {
            appState = .needsSetup
        }
    }

    private func findDaemon() -> URL? {
        // 1. Same directory as this executable (inside the .app bundle)
        if let exe = Bundle.main.executableURL {
            let bundled = exe.deletingLastPathComponent().appendingPathComponent("wsteamd")
            if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        }
        // 2. Installed via `make install`
        let installed = URL(fileURLWithPath: "/usr/local/bin/wsteamd")
        if FileManager.default.fileExists(atPath: installed.path) { return installed }

        // 3. Dev: built in the project's target/release
        let devPath = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Desktop/wsteam/target/release/wsteamd")
        if FileManager.default.fileExists(atPath: devPath.path) { return devPath }

        return nil
    }

    private func killStaleDaemon() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-x", "wsteamd"]
        try? p.run(); p.waitUntilExit()
    }

    private func startDaemon(at url: URL) {
        let p = Process()
        p.executableURL = url
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice
        try? p.run()
        daemonProcess = p
    }

    // MARK: - Setup

    func runFullSetup() async {
        isLoading = true
        setupProgress = .running(step: "Downloading Wine Crossover…", pct: 5)
        do {
            try await client.setupWine()
            setupProgress = .running(step: "Creating Windows prefix…", pct: 38)
            try await client.setupSteam()
            setupProgress = .running(step: "Installing DXVK + MoltenVK…", pct: 78)
            try await client.setupDxvk()
            setupProgress = .done
            status = try? await client.getStatus()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
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

    func refreshStatus() async {
        status = try? await client.getStatus()
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

    func killWineserver() async { try? await client.killWineserver() }
    func clearError() { errorMessage = nil }

    // MARK: - Folder access

    func openGameFolder(_ game: GameInfo) async {
        do {
            let f = try await client.getGameFolder(game.appId)
            if f.exists { try await client.openInFinder(path: f.path) }
            else { errorMessage = "Install the game in Steam first.\n\(f.path)" }
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
