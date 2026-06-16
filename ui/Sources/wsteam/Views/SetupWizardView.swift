import SwiftUI

struct SetupWizardView: View {
    @EnvironmentObject var store: AppStore
    @State private var currentStep = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                header

                if case .running(let step, let pct) = store.setupProgress {
                    runningView(step: step, pct: pct)
                } else if case .done = store.setupProgress {
                    doneView
                } else if case .failed(let msg) = store.setupProgress {
                    failedView(msg)
                } else {
                    readyView
                }
            }
            .padding(40)
        }
        .navigationTitle("Setup")
        .frame(maxWidth: 640, maxHeight: .infinity)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue)

            Text("wsteam Setup")
                .font(.largeTitle.bold())

            Text("Downloads Wine, Steam, DXVK and MoltenVK to run Windows games on your Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var readyView: some View {
        VStack(spacing: 24) {
            stepList

            Button("Start Setup") {
                Task { await store.runFullSetup() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
        }
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 16) {
            SetupStepRow(icon: "🍷", title: "Wine Crossover",
                         subtitle: "Compatibility layer that runs Windows programs",
                         status: stepStatus(for: store.status?.wineInstalled))

            SetupStepRow(icon: "🎮", title: "Steam for Windows",
                         subtitle: "Full Steam client inside Wine",
                         status: stepStatus(for: store.status?.steamInstalled))

            SetupStepRow(icon: "⚡️", title: "DXVK + MoltenVK",
                         subtitle: "Translates DirectX → Vulkan → Metal for best performance",
                         status: stepStatus(for: store.status?.dxvkInstalled))
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 6)
    }

    private func stepStatus(for installed: Bool?) -> StepStatus {
        guard let installed else { return .pending }
        return installed ? .done : .pending
    }

    private func runningView(step: String, pct: Double) -> some View {
        VStack(spacing: 20) {
            ProgressView(value: pct / 100)
                .progressViewStyle(.linear)

            Text(step)
                .font(.headline)

            Text("This downloads several hundred MB. Do not close this window.")
                .foregroundStyle(.secondary)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var doneView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Setup Complete!")
                .font(.title.bold())

            Text("Launch Steam to log in and download your games.")
                .foregroundStyle(.secondary)

            Button("Launch Steam") {
                Task { await store.launchSteam() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func failedView(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)

            Text("Setup Failed")
                .font(.title.bold())

            Text(msg)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Try Again") {
                store.setupProgress = .idle
                Task { await store.runFullSetup() }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

enum StepStatus { case pending, running, done }

struct SetupStepRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let status: StepStatus

    var body: some View {
        HStack(spacing: 16) {
            Text(icon).font(.title)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            switch status {
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .running:
                ProgressView().controlSize(.small)
            case .pending:
                Image(systemName: "circle").foregroundStyle(.tertiary)
            }
        }
    }
}
