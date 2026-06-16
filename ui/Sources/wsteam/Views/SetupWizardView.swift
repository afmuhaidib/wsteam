import SwiftUI

struct SetupWizardView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 64)).foregroundStyle(.blue)
            Text("Welcome to wsteam").font(.largeTitle.bold())
            Text("Downloads Wine, Steam, DXVK and MoltenVK (~1 GB).\nAfter setup, log into Steam and install your games.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)

            stepList

            switch store.setupProgress {
            case .idle:
                Button("Install Everything") { Task { await store.runFullSetup() } }
                    .buttonStyle(.borderedProminent).controlSize(.extraLarge)
            case .running(let step, let pct):
                VStack(spacing: 12) {
                    ProgressView(value: pct / 100).progressViewStyle(.linear).frame(maxWidth: 400)
                    Text(step).font(.subheadline)
                    Text("Do not close this window — downloading…").font(.caption).foregroundStyle(.secondary)
                }
            case .done:
                VStack(spacing: 12) {
                    Label("Done!", systemImage: "checkmark.circle.fill").font(.title2.bold()).foregroundStyle(.green)
                    Button("Open Steam & log in") { Task { await store.launchSteam() } }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
            case .failed(let msg):
                VStack(spacing: 12) {
                    Label("Failed", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                    Text(msg).foregroundStyle(.red).multilineTextAlignment(.center)
                    Button("Try Again") { Task { await store.boot() } }
                        .buttonStyle(.borderedProminent)
                }
            }
            Spacer()
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 14) {
            row("🍷", "Wine Crossover 24", "Windows compatibility layer", store.status?.wineInstalled)
            row("🎮", "Steam for Windows", "Full Steam client inside Wine", store.status?.steamInstalled)
            row("⚡️", "DXVK + MoltenVK", "DirectX → Vulkan → Metal for best perf", store.status?.dxvkInstalled)
        }
        .padding(20)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 6)
    }

    private func row(_ icon: String, _ title: String, _ sub: String, _ done: Bool?) -> some View {
        HStack(spacing: 14) {
            Text(icon).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(sub).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: done == true ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done == true ? Color.green : Color.secondary)
        }
    }
}
