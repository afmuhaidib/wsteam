import SwiftUI

struct SetupView: View {
    @EnvironmentObject var engine: WineEngine
    @State private var started = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "gamecontroller.fill").font(.title).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("wsteam").font(.title2.bold())
                Text("Windows Steam games on macOS").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if engine.wineInstalled && engine.steamInstalled {
                Button("Open Steam") { engine.launchSteam() }.buttonStyle(.borderedProminent)
            }
        }.padding(.horizontal, 24).padding(.vertical, 16)
    }

    private var content: some View {
        HStack(spacing: 0) {
            // Left — steps + action
            VStack(alignment: .leading, spacing: 24) {
                stepsPanel
                actionArea
                Spacer()
            }.frame(width: 320).padding(24)

            Divider()

            // Right — live log
            logPanel
        }
    }

    private var stepsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Setup").font(.headline)
            StepRow(icon: "🍷", label: "Wine Staging 11.10", sub: "Windows compatibility layer", done: engine.wineInstalled)
            StepRow(icon: "🖥", label: "Windows Prefix", sub: "64-bit Windows 10 environment", done: FileManager.default.fileExists(atPath: WsteamPaths.prefix.appendingPathComponent("system.reg").path))
            StepRow(icon: "⚡️", label: "DXVK", sub: "DirectX → Metal translation", done: engine.dxvkInstalled)
            StepRow(icon: "🎮", label: "Steam for Windows", sub: "Log in to install your games", done: engine.steamInstalled)
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.07), radius: 5)
    }

    private var actionArea: some View {
        VStack(spacing: 12) {
            if case .error(let msg) = engine.stage {
                Text(msg).foregroundStyle(.red).font(.caption).multilineTextAlignment(.leading)
                Button("Try Again") { Task { await engine.runSetup() } }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
            } else if case .downloading(let what) = engine.stage {
                ProgressView(value: engine.downloadProgress) { Text("Downloading \(what)…").font(.caption) }.progressViewStyle(.linear)
            } else if isRunning {
                ProgressView().controlSize(.small)
                Text(stageLabel).font(.caption).foregroundStyle(.secondary)
            } else if engine.wineInstalled && engine.steamInstalled {
                Button("Open Steam →") { engine.launchSteam() }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity).controlSize(.large)
                Button("Go to Library") { engine.stage = .ready }.buttonStyle(.bordered).frame(maxWidth: .infinity)
            } else {
                Button("Install Everything") { Task { await engine.runSetup() } }
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity).controlSize(.large)
                Text("Downloads ~400 MB. Keep window open.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var logPanel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(engine.log) { line in
                        Text(line.text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(line.isError ? Color.red : Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                }.padding(14)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .onChange(of: engine.log.count) { _ in
                if let last = engine.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var isRunning: Bool {
        switch engine.stage {
        case .extracting, .creatingPrefix, .installingSteam, .downloadingSteam: return true
        default: return false
        }
    }
    private var stageLabel: String {
        switch engine.stage {
        case .extracting:      return "Extracting Wine…"
        case .creatingPrefix:  return "Creating Windows prefix…"
        case .downloadingSteam: return "Downloading Steam…"
        case .installingSteam: return "Installing Steam…"
        default: return "Working…"
        }
    }
}

struct StepRow: View {
    let icon: String; let label: String; let sub: String; let done: Bool
    var body: some View {
        HStack(spacing: 12) {
            Text(icon).font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.subheadline.bold())
                Text(sub).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : Color.secondary)
        }
    }
}
