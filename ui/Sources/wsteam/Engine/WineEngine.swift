import AppKit
import Foundation

// MARK: - Paths

struct WsteamPaths {
    static let home      = URL(fileURLWithPath: NSHomeDirectory())
    static let base      = home.appendingPathComponent(".wsteam")
    static let downloads = base.appendingPathComponent("downloads")

    // CrossOver app locations
    private static let cxAppCandidates: [URL] = [
        home.appendingPathComponent("Applications/CrossOver.app"),
        URL(fileURLWithPath: "/Applications/CrossOver.app")
    ]

    static var cxApp: URL? { cxAppCandidates.first { fm.fileExists(atPath: $0.path) } }

    static var cxStart: URL? {
        cxApp.map { $0.appendingPathComponent("Contents/SharedSupport/CrossOver/bin/cxstart") }
    }

    static var cxBottlesRoot: URL? {
        cxApp.map { _ in home.appendingPathComponent("Library/Application Support/CrossOver/Bottles") }
    }

    // CrossOver bottle that has Steam installed
    static var cxSteamBottle: (name: String, url: URL)? {
        guard let root = cxBottlesRoot else { return nil }
        let candidates = ["Steam", "Among Us", "Among Us-2", "wsteam"]
        for name in candidates {
            let bottleURL = root.appendingPathComponent(name)
            let steamExe  = bottleURL.appendingPathComponent("drive_c/Program Files (x86)/Steam/Steam.exe")
            if fm.fileExists(atPath: steamExe.path) { return (name, bottleURL) }
        }
        // Any bottle with Steam
        if let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for entry in entries {
                let steamExe = entry.appendingPathComponent("drive_c/Program Files (x86)/Steam/Steam.exe")
                if fm.fileExists(atPath: steamExe.path) { return (entry.lastPathComponent, entry) }
            }
        }
        return nil
    }

    static var steamExe: URL? { cxSteamBottle.map { $0.url.appendingPathComponent("drive_c/Program Files (x86)/Steam/Steam.exe") } }
    static var steamapps: URL? { cxSteamBottle.map { $0.url.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps/common") } }

    private static let fm = FileManager.default
    static func ready() { try? fm.createDirectory(at: downloads, withIntermediateDirectories: true) }
}

// MARK: - Engine

@MainActor
final class WineEngine: ObservableObject {
    @Published var log: [LogLine] = []
    @Published var stage: Stage = .idle

    enum Stage: Equatable {
        case idle, checking, ready, error(String)
    }

    struct LogLine: Identifiable {
        let id = UUID(); let text: String; let isError: Bool
    }

    var cxAvailable: Bool    { WsteamPaths.cxStart != nil }
    var steamInstalled: Bool { WsteamPaths.steamExe != nil }

    // MARK: Setup check

    func runSetup() async {
        WsteamPaths.ready()
        stage = .checking
        info("Checking CrossOver + Steam...")

        guard cxAvailable else {
            setError("CrossOver not found. Install CrossOver from codeweavers.com then reopen wsteam.")
            return
        }
        info("CrossOver found ✓")

        guard steamInstalled, let bottle = WsteamPaths.cxSteamBottle else {
            setError("Steam not found in any CrossOver bottle. Open CrossOver → install Steam → reopen wsteam.")
            return
        }
        info("Steam found in bottle '\(bottle.name)' ✓")
        stage = .ready
        info("=== Ready to play ===")
    }

    // MARK: Launch

    func launchSteam() {
        guard let cx = WsteamPaths.cxStart, let bottle = WsteamPaths.cxSteamBottle else {
            setError("CrossOver or Steam not found"); return
        }
        info("Launching Steam (bottle: \(bottle.name))...")
        spawnCX(cx, bottle: bottle.name, exe: "C:\\Program Files (x86)\\Steam\\Steam.exe")
    }

    func launchGame(appId: Int) {
        guard let cx = WsteamPaths.cxStart, let bottle = WsteamPaths.cxSteamBottle else {
            setError("CrossOver or Steam not found"); return
        }
        info("Launching app \(appId)...")
        spawnCX(cx, bottle: bottle.name, exe: "C:\\Program Files (x86)\\Steam\\Steam.exe", extra: ["-applaunch", "\(appId)"])
    }

    private func spawnCX(_ cxstart: URL, bottle: String, exe: String, extra: [String] = []) {
        let p = Process()
        p.executableURL = cxstart
        p.arguments = ["--bottle", bottle, "--"] + [exe] + extra
        try? p.run()
    }

    // MARK: Utilities

    func openFolder(_ url: URL) { NSWorkspace.shared.open(url) }

    func killWineserver() {
        // CrossOver manages its own wineserver — just tell it to quit
        if let cx = WsteamPaths.cxApp {
            let kill = cx.appendingPathComponent("Contents/SharedSupport/CrossOver/CrossOver-Hosted Application/wineserver")
            let p = Process()
            p.executableURL = kill
            p.arguments = ["-k"]
            try? p.run()
        }
        info("Wineserver killed")
    }

    func scanGames() -> [GameEntry] {
        guard let steamapps = WsteamPaths.steamapps,
              let acfDir = WsteamPaths.cxSteamBottle.map({ $0.url.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps") }),
              let acfs = try? FileManager.default.contentsOfDirectory(at: acfDir, includingPropertiesForKeys: nil)
        else { return [] }
        return acfs.filter { $0.pathExtension == "acf" }.compactMap { parseACF($0) }
    }

    // MARK: Logging

    private func info(_ msg: String)     { log.append(LogLine(text: msg, isError: false)) }
    private func setError(_ msg: String) { log.append(LogLine(text: "ERROR: \(msg)", isError: true)); stage = .error(msg) }

    // MARK: ACF parser

    private func parseACF(_ url: URL) -> GameEntry? {
        guard let txt = try? String(contentsOf: url) else { return nil }
        func field(_ key: String) -> String? {
            for line in txt.split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("\"\(key)\"") else { continue }
                let after = t.dropFirst(key.count + 2).trimmingCharacters(in: .whitespaces)
                if after.hasPrefix("\"") { return String(after.dropFirst().prefix(while: { $0 != "\"" })) }
            }
            return nil
        }
        guard let id   = field("appid").flatMap(Int.init),
              let name = field("name"),
              let dir  = field("installdir"),
              let base = WsteamPaths.steamapps else { return nil }
        return GameEntry(appId: id, name: name, installDir: base.appendingPathComponent(dir))
    }
}

struct GameEntry: Identifiable {
    var id: Int { appId }
    let appId: Int; let name: String; let installDir: URL
}
