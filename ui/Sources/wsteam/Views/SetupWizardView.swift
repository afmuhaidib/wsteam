import SwiftUI

struct SetupView: View {
    @EnvironmentObject var engine: WineEngine

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
                Text("Windows Steam on macOS via CrossOver").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if engine.steamInstalled {
                Button("Open Steam") { engine.launchSteam() }.buttonStyle(.borderedProminent)
            }
        }.padding(.horizontal, 24).padding(.vertical, 16)
    }

    private var content: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                stepsPanel
                actionArea
                Spacer()
            }.frame(width: 320).padding(24)
            Divider()
            logPanel
        }
    }

    private var stepsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Requirements").font(.headline)
            StepRow(icon: "🍷", label: "CrossOver", sub: "codeweavers.com — runs Windows apps", done: engine.cxAvailable)
            StepRow(icon: "🎮", label: "Steam in CrossOver", sub: "Install Steam inside a CrossOver bottle", done: engine.steamInstalled)
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
                Button("Check Again") { Task { await engine.runSetup() } }
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
            } else if case .checking = engine.stage {
                ProgressView().controlSize(.small)
                Text("Checking…").font(.caption).foregroundStyle(.secondary)
            } else if engine.steamInstalled {
                Button("Open Steam →") { engine.launchSteam() }
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity).controlSize(.large)
                Button("Go to Library") { engine.stage = .ready }
                    .buttonStyle(.bordered).frame(maxWidth: .infinity)
            } else {
                Button("Check Setup") { Task { await engine.runSetup() } }
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity).controlSize(.large)
                if !engine.cxAvailable {
                    Link("Get CrossOver →", destination: URL(string: "https://www.codeweavers.com/crossover")!)
                        .font(.caption).frame(maxWidth: .infinity)
                }
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
