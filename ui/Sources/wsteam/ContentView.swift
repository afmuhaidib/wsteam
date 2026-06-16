import SwiftUI

struct MainAppView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        NavigationSplitView {
            Sidebar()
        } detail: {
            LibraryView()
        }
        .alert("Error", isPresented: .init(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.clearError() } }
        )) {
            Button("OK") { store.clearError() }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        List {
            Section("Library") {
                Label("Games", systemImage: "gamecontroller").bold()
            }

            Section("Steam") {
                Button { Task { await store.launchSteam() } } label: {
                    Label("Open Steam", systemImage: "play.fill")
                }.buttonStyle(.plain)

                Button { Task { await store.refreshLibrary() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }.buttonStyle(.plain)
            }

            Section("Folders") {
                Button { Task { await store.openSteamFolder() } } label: {
                    Label("Games / Mods", systemImage: "folder.badge.gearshape")
                }.buttonStyle(.plain).help("steamapps/common — drop mods here")

                Button { Task { await store.openPrefixFolder() } } label: {
                    Label("Wine C:\\", systemImage: "internaldrive")
                }.buttonStyle(.plain).help("Full Windows drive_c")
            }

            Section("System") {
                NavigationLink { SetupWizardView() } label: {
                    Label("Setup", systemImage: "gearshape")
                }
                NavigationLink { StatusView() } label: {
                    Label("Status", systemImage: "info.circle")
                }
                Button { Task { await store.killWineserver() } } label: {
                    Label("Kill Wineserver", systemImage: "xmark.octagon")
                }.buttonStyle(.plain).foregroundStyle(.red)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    }
}
