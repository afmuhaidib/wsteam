import SwiftUI

struct StatusView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let s = store.status {
                    statusGrid(s)
                } else {
                    ProgressView("Loading status...")
                }
            }
            .padding(24)
        }
        .navigationTitle("System Status")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await store.refreshStatus() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .task { await store.refreshStatus() }
    }

    private func statusGrid(_ s: StatusPayload) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Components")
                .font(.title2.bold())

            StatusRow(label: "Wine Crossover",
                      value: s.wineVersion.isEmpty ? "Not installed" : "v\(s.wineVersion)",
                      ok: s.wineInstalled)

            StatusRow(label: "Wine Prefix",
                      value: s.prefixExists ? "Ready" : "Not created",
                      ok: s.prefixExists)

            StatusRow(label: "Steam",
                      value: s.steamInstalled ? "Installed" : "Not installed",
                      ok: s.steamInstalled)

            StatusRow(label: "DXVK",
                      value: s.dxvkInstalled ? "Installed" : "Not installed",
                      ok: s.dxvkInstalled)

            StatusRow(label: "MoltenVK",
                      value: s.moltenVkInstalled ? "Installed" : "Not installed",
                      ok: s.moltenVkInstalled)

            Divider()

            StatusRow(label: "Daemon Version", value: "v\(s.daemonVersion)", ok: true)
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 6)
    }
}

struct StatusRow: View {
    let label: String
    let value: String
    let ok: Bool

    var body: some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)

            Text(label)
                .frame(width: 160, alignment: .leading)

            Text(value)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .font(.subheadline)
    }
}
