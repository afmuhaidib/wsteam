import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if !store.daemonRunning {
                DaemonOfflineView()
            } else if store.status == nil {
                ProgressView("Connecting...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !(store.status?.wineInstalled ?? false) {
                SetupWizardView()
            } else {
                LibraryView()
            }
        }
        .alert("Error", isPresented: .init(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.clearError() } }
        )) {
            Button("OK") { store.clearError() }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .task {
            await store.checkDaemon()
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        List {
            Section("wsteam") {
                NavigationLink {
                    LibraryView()
                } label: {
                    Label("Library", systemImage: "gamecontroller")
                }

                NavigationLink {
                    StatusView()
                } label: {
                    Label("Status", systemImage: "info.circle")
                }

                NavigationLink {
                    SetupWizardView()
                } label: {
                    Label("Setup", systemImage: "gearshape")
                }
            }

            Section("Actions") {
                Button {
                    Task { await store.launchSteam() }
                } label: {
                    Label("Launch Steam", systemImage: "play.fill")
                }
                .buttonStyle(.plain)

                Button {
                    Task { await store.refreshLibrary() }
                } label: {
                    Label("Refresh Library", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)

                Button {
                    Task { await store.killWineserver() }
                } label: {
                    Label("Kill Wineserver", systemImage: "xmark.octagon")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    }
}

struct DaemonOfflineView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            Text("Daemon not running")
                .font(.title2.bold())

            Text("Start the daemon to continue.")
                .foregroundStyle(.secondary)

            Button("Start Daemon") {
                store.startDaemon()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
