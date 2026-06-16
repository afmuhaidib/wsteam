import AppKit
import Foundation

// MARK: - Constants
enum WineSource {
    // gcenx wine-staging — verified 200 OK
    static let url = "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.10/wine-staging-11.10-osx64.tar.xz"
    static let tarName = "wine-staging-11.10-osx64.tar.xz"
    static let extractedDir = "wine-staging-11.10"
    static let version = "11.10"
}
enum SteamSource {
    static let url = "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe"
}
enum DxvkSource {
    static let url = "https://github.com/Gcenx/DXVK-macOS/releases/download/v1.10.3-20230507-repack/dxvk-macOS-async-v1.10.3-20230507-repack.tar.gz"
    static let extractedDir = "dxvk-macOS-async-v1.10.3-20230507-repack"
}

// MARK: - Paths
struct WsteamPaths {
    static let base      = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".wsteam")
    static let wineDir   = base.appendingPathComponent("wine")
    static let prefix    = base.appendingPathComponent("prefix")
    static let dxvkDir   = base.appendingPathComponent("dxvk")
    static let downloads = base.appendingPathComponent("downloads")

    // Firewall-trusted Wine candidates (CrossOver, Among Us) preferred over our own download
    private static let trustedWineCandidates: [String] = [
        "/Users/\(NSUserName())/Applications/Among Us.app/Contents/SharedSupport/wine/bin/wine64",
        "/Applications/Among Us.app/Contents/SharedSupport/wine/bin/wine64",
        "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib/wine/wine64",
    ]

    static var wine64: URL { wineDir.appendingPathComponent("bin/wine64") }
    static var wine32: URL { wineDir.appendingPathComponent("bin/wine") }
    // Prefer a firewall-trusted binary so macOS does not block network access
    static var wineBin: URL {
        for path in trustedWineCandidates {
            if fm.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return fm.fileExists(atPath: wine64.path) ? wine64 : wine32
    }
    static var wineServer: URL {
        let candidate = wineBin.deletingLastPathComponent().appendingPathComponent("wineserver")
        return fm.fileExists(atPath: candidate.path) ? candidate : wineDir.appendingPathComponent("bin/wineserver")
    }
    static var steamExe: URL { prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/Steam.exe") }
    static var steamapps: URL { prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps/common") }
    static var driveC: URL   { prefix.appendingPathComponent("drive_c") }

    private static let fm = FileManager.default
    static func ready() { [base, wineDir, prefix, dxvkDir, downloads].forEach { try? fm.createDirectory(at: $0, withIntermediateDirectories: true) } }
}

// MARK: - Step result
enum StepResult { case ok, skipped, failed(String) }

// MARK: - Engine
@MainActor
final class WineEngine: ObservableObject {
    @Published var log: [LogLine] = []
    @Published var stage: Stage = .idle
    @Published var downloadProgress: Double = 0

    enum Stage: Equatable {
        case idle, downloading(String), extracting, creatingPrefix
        case downloadingSteam, installingSteam, ready, error(String)
    }

    struct LogLine: Identifiable {
        let id = UUID(); let text: String; let isError: Bool
    }

    var wineInstalled: Bool { FileManager.default.fileExists(atPath: WsteamPaths.wine64.path) || FileManager.default.fileExists(atPath: WsteamPaths.wine32.path) }
    var steamInstalled: Bool { FileManager.default.fileExists(atPath: WsteamPaths.steamExe.path) }
    var dxvkInstalled: Bool { FileManager.default.fileExists(atPath: WsteamPaths.dxvkDir.appendingPathComponent("x64/d3d11.dll").path) }

    // MARK: Full setup

    func runSetup() async {
        WsteamPaths.ready()
        info("=== wsteam setup starting ===")

        if !wineInstalled {
            await downloadAndExtractWine()
            guard wineInstalled else { return }
        } else { info("Wine already installed — skipping") }

        if !FileManager.default.fileExists(atPath: WsteamPaths.prefix.appendingPathComponent("system.reg").path) {
            await createPrefix()
        } else { info("Prefix already exists — skipping") }

        if !dxvkInstalled { await installDxvk() }
        else { info("DXVK already installed — skipping") }

        if !steamInstalled {
            await downloadAndInstallSteam()
            guard steamInstalled else { return }
        } else { info("Steam already installed — skipping") }

        stage = .ready
        info("=== Setup complete! ===")
    }

    // MARK: Wine download + extract

    private func downloadAndExtractWine() async {
        let dest = WsteamPaths.downloads.appendingPathComponent(WineSource.tarName)
        if !FileManager.default.fileExists(atPath: dest.path) {
            stage = .downloading("Wine \(WineSource.version)")
            info("Downloading Wine \(WineSource.version)...")
            guard await download(url: WineSource.url, to: dest, label: "Wine") else {
                setError("Wine download failed"); return
            }
        } else { info("Wine archive cached") }

        stage = .extracting
        info("Extracting Wine (this takes ~30 seconds)...")
        let result = await shell("tar", "-xJf", dest.path, "-C", WsteamPaths.base.path)
        if !result.ok { setError("Wine extraction failed: \(result.err)"); return }

        // Rename extracted folder → wine/
        let extracted = WsteamPaths.base.appendingPathComponent(WineSource.extractedDir)
        if FileManager.default.fileExists(atPath: extracted.path) {
            try? FileManager.default.removeItem(at: WsteamPaths.wineDir)
            try? FileManager.default.moveItem(at: extracted, to: WsteamPaths.wineDir)
        }

        if wineInstalled { info("Wine installed ✓") }
        else { setError("Wine extracted but binary not found — check ~/.wsteam/wine/bin/") }
    }

    // MARK: Prefix

    private func createPrefix() async {
        stage = .creatingPrefix
        info("Creating Windows 10 prefix...")
        var env = baseEnv()
        env["WINEARCH"] = "win64"
        let r = await shellEnv(env, WsteamPaths.wineBin.path, "wineboot", "--init")
        if r.ok { info("Prefix created ✓") } else { info("Prefix init warning: \(r.err)") }

        // Set Windows version to win10
        _ = await shellEnv(baseEnv(), WsteamPaths.wineBin.path, "winecfg", "-v", "win10")
    }

    // MARK: DXVK

    private func installDxvk() async {
        let dest = WsteamPaths.downloads.appendingPathComponent("dxvk.tar.gz")
        if !FileManager.default.fileExists(atPath: dest.path) {
            stage = .downloading("DXVK")
            info("Downloading DXVK...")
            guard await download(url: DxvkSource.url, to: dest, label: "DXVK") else {
                info("DXVK download failed — continuing without it"); return
            }
        }
        let r = await shell("tar", "-xzf", dest.path, "-C", WsteamPaths.base.path)
        guard r.ok else { info("DXVK extract failed"); return }

        let extracted = WsteamPaths.base.appendingPathComponent(DxvkSource.extractedDir)
        try? FileManager.default.removeItem(at: WsteamPaths.dxvkDir)
        try? FileManager.default.moveItem(at: extracted, to: WsteamPaths.dxvkDir)

        // Copy DLLs into prefix
        let sys32 = WsteamPaths.prefix.appendingPathComponent("drive_c/windows/system32")
        let wow64 = WsteamPaths.prefix.appendingPathComponent("drive_c/windows/syswow64")
        try? FileManager.default.createDirectory(at: sys32, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: wow64, withIntermediateDirectories: true)
        for dll in ["d3d10core.dll", "d3d11.dll"] {
            let s64 = WsteamPaths.dxvkDir.appendingPathComponent("x64/\(dll)")
            let s32 = WsteamPaths.dxvkDir.appendingPathComponent("x32/\(dll)")
            if FileManager.default.fileExists(atPath: s64.path) { try? FileManager.default.copyItem(at: s64, to: sys32.appendingPathComponent(dll)) }
            if FileManager.default.fileExists(atPath: s32.path) { try? FileManager.default.copyItem(at: s32, to: wow64.appendingPathComponent(dll)) }
        }
        // DLL overrides via reg
        let env = baseEnv()
        for dll in ["d3d10core", "d3d11"] {
            let key = #"HKEY_CURRENT_USER\Software\Wine\DllOverrides"#
            _ = await shellEnv(env, WsteamPaths.wineBin.path, "reg", "add", key, "/v", dll, "/d", "native,builtin", "/f")
        }
        info("DXVK installed ✓")
    }

    // MARK: Steam

    private func downloadAndInstallSteam() async {
        let dest = WsteamPaths.downloads.appendingPathComponent("SteamSetup.exe")
        if !FileManager.default.fileExists(atPath: dest.path) {
            stage = .downloadingSteam
            info("Downloading Steam installer...")
            guard await download(url: SteamSource.url, to: dest, label: "Steam") else {
                setError("Steam download failed"); return
            }
        }
        stage = .installingSteam
        info("Installing Steam (a window may appear)...")
        var env = baseEnv()
        env["DXVK_ASYNC"] = "1"
        let r = await shellEnv(env, WsteamPaths.wineBin.path, dest.path, "/S")
        if steamInstalled { info("Steam installed ✓") }
        else { info("Steam silent install may have failed — trying to launch normally...") }
    }

    // MARK: Launch Steam

    // Steam black screen fix:
    // -no-browser      disables Chromium/CEF UI (main cause of black screen)
    // -nofriendsui     disables friends overlay renderer
    // -noreactlogin    uses old login dialog instead of web-based one
    // WINEDLLOVERRIDES disables Steam's broken CEF GPU process
    private func steamEnv() -> [String: String] {
        var env = baseEnv()
        env["DXVK_ASYNC"] = "1"
        env["STEAM_FRAME_FORCE_CLOSE"] = "1"
        env["WINEDLLOVERRIDES"] = "d3d11=n,b;d3d10core=n,b;dxgi=n,b"
        return env
    }

    private let steamExePath = #"C:\Program Files (x86)\Steam\Steam.exe"#
    private let steamBlackScreenArgs = ["-no-browser", "-nofriendsui", "-noreactlogin", "-skipinitialbootstrap"]

    func launchSteam() {
        guard wineInstalled else { setError("Wine not installed"); return }
        guard steamInstalled else { setError("Steam not installed — run setup first"); return }
        info("Launching Steam (black screen fix enabled)...")
        spawnWine([steamExePath] + steamBlackScreenArgs, env: steamEnv())
    }

    func launchGame(appId: Int) {
        guard wineInstalled && steamInstalled else { setError("Setup incomplete"); return }
        info("Launching app \(appId)...")
        spawnWine([steamExePath, "-applaunch", "\(appId)"] + steamBlackScreenArgs, env: steamEnv())
    }

    private func spawnWine(_ args: [String], env: [String: String]) {
        let p = Process()
        p.executableURL = WsteamPaths.wineBin
        p.arguments = args
        p.environment = env
        try? p.run()
    }

    func openFolder(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func killWineserver() {
        let p = Process()
        p.executableURL = WsteamPaths.wineServer
        p.arguments = ["-k"]
        p.environment = baseEnv()
        try? p.run()
        info("Wineserver killed")
    }

    func scanGames() -> [GameEntry] {
        let common = WsteamPaths.steamapps
        guard let items = try? FileManager.default.contentsOfDirectory(at: common, includingPropertiesForKeys: nil) else { return [] }
        let acfDir = WsteamPaths.prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps")
        var games: [GameEntry] = []
        if let acfs = try? FileManager.default.contentsOfDirectory(at: acfDir, includingPropertiesForKeys: nil) {
            for acf in acfs where acf.pathExtension == "acf" {
                if let g = parseACF(acf) { games.append(g) }
            }
        }
        return games
    }

    // MARK: Helpers

    private func baseEnv() -> [String: String] {
        var e = ProcessInfo.processInfo.environment
        e["WINEPREFIX"]  = WsteamPaths.prefix.path
        e["WINEDEBUG"]   = "-all"
        e["DXVK_ASYNC"]  = "1"
        e["WINEMSYNC"]   = "1"   // macOS-native mutex sync (required for network + stability)
        e["WINEESYNC"]   = "1"   // eventfd sync fallback
        e["GST_DEBUG"]   = "1"
        return e
    }

    private func download(url: String, to dest: URL, label: String) async -> Bool {
        await withCheckedContinuation { cont in
            guard let u = URL(string: url) else { cont.resume(returning: false); return }
            let task = URLSession.shared.downloadTask(with: u) { tmp, resp, err in
                if let err { Task { @MainActor in self.info("Download error: \(err.localizedDescription)") }; cont.resume(returning: false); return }
                guard let tmp else { cont.resume(returning: false); return }
                try? FileManager.default.moveItem(at: tmp, to: dest)
                cont.resume(returning: FileManager.default.fileExists(atPath: dest.path))
            }
            let obs = task.progress.observe(\.fractionCompleted) { p, _ in
                Task { @MainActor in self.downloadProgress = p.fractionCompleted }
            }
            task.resume()
            // keep obs alive
            objc_setAssociatedObject(task, &AssocKey.obs, obs, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    struct ShellResult { let ok: Bool; let out: String; let err: String }

    private func shell(_ args: String...) async -> ShellResult {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = args
            let out = Pipe(); let err = Pipe()
            p.standardOutput = out; p.standardError = err
            p.terminationHandler = { proc in
                let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                cont.resume(returning: ShellResult(ok: proc.terminationStatus == 0, out: o, err: e))
            }
            try? p.run()
        }
    }

    private func shellEnv(_ env: [String: String], _ exe: String, _ args: String...) async -> ShellResult {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            p.environment = env
            let out = Pipe(); let err = Pipe()
            p.standardOutput = out; p.standardError = err
            p.terminationHandler = { proc in
                let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                cont.resume(returning: ShellResult(ok: proc.terminationStatus == 0, out: o, err: e))
            }
            try? p.run()
        }
    }

    private func info(_ msg: String) { log.append(LogLine(text: msg, isError: false)) }
    private func setError(_ msg: String) { log.append(LogLine(text: "ERROR: \(msg)", isError: true)); stage = .error(msg) }

    private func parseACF(_ url: URL) -> GameEntry? {
        guard let txt = try? String(contentsOf: url) else { return nil }
        func field(_ key: String) -> String? {
            for line in txt.lines {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("\"\(key)\"") else { continue }
                let after = t.dropFirst(key.count + 2).trimmingCharacters(in: .whitespaces)
                if after.hasPrefix("\"") { return String(after.dropFirst().prefix(while: { $0 != "\"" })) }
            }
            return nil
        }
        guard let id = field("appid").flatMap(Int.init),
              let name = field("name"),
              let dir = field("installdir") else { return nil }
        let installURL = WsteamPaths.steamapps.appendingPathComponent(dir)
        return GameEntry(appId: id, name: name, installDir: installURL)
    }
}

struct GameEntry: Identifiable {
    var id: Int { appId }
    let appId: Int; let name: String; let installDir: URL
}

private enum AssocKey { static var obs = 0 }

extension StringProtocol {
    var lines: [SubSequence] { split(separator: "\n", omittingEmptySubsequences: false) }
}
