import SwiftUI
import Combine

@MainActor
final class AppStore: ObservableObject {
    @Published var status: StatusPayload?
    @Published var games: [GameInfo] = []
    @Published var isLoading = false
    @Published var setupProgress: SetupProgress = .idle
    @Published var errorMessage: String?
    @Published var daemonRunning = false

    private let client = DaemonClient()
    private var daemonProcess: Process?

    init() {
        Task { await checkDaemon() }
    }

    // MARK: - Daemon management

    func checkDaemon() async {
        do {
            status = try await client.getStatus()
            daemonRunning = true
            await refreshLibrary()
        } catch {
            daemonRunning = false
        }
    }

    func startDaemon() {
        guard !daemonRunning else { return }
        let daemonPath = Bundle.main.bundlePath
            .appending("/Contents/MacOS/wsteamd")

        let altPath = "/usr/local/bin/wsteamd"
        let path = FileManager.default.fileExists(atPath: daemonPath)
            ? daemonPath : altPath

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.launch()
        daemonProcess = process

        // Poll until connected
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await checkDaemon()
        }
    }

    // MARK: - Setup

    enum SetupProgress {
        case idle
        case running(step: String, pct: Double)
        case done
        case failed(String)
    }

    func runFullSetup() async {
        isLoading = true
        setupProgress = .running(step: "Starting setup...", pct: 0)
        do {
            setupProgress = .running(step: "Installing Wine...", pct: 10)
            try await client.setupWine()
            setupProgress = .running(step: "Creating Wine prefix...", pct: 40)
            try await client.setupSteam()
            setupProgress = .running(step: "Installing DXVK + MoltenVK...", pct: 80)
            try await client.setupDxvk()
            setupProgress = .done
            status = try? await client.getStatus()
        } catch {
            setupProgress = .failed(error.localizedDescription)
        }
        isLoading = false
    }

    // MARK: - Library

    func refreshLibrary() async {
        do {
            games = try await client.scanLibrary()
        } catch {
            // Non-fatal: games just stay empty
        }
    }

    func refreshStatus() async {
        do {
            status = try await client.getStatus()
        } catch {
            daemonRunning = false
        }
    }

    // MARK: - Game actions

    func launchSteam() async {
        isLoading = true
        do {
            try await client.launchSteam()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func launch(game: GameInfo) async {
        isLoading = true
        do {
            try await client.launchGame(game.appId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func killWineserver() async {
        try? await client.killWineserver()
    }

    func clearError() { errorMessage = nil }
}
