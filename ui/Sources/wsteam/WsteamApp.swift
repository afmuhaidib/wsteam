import SwiftUI

@main
struct WsteamApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("wsteam") {
                Button("Open Steam") { Task { await store.launchSteam() } }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Refresh Library") { Task { await store.refreshLibrary() } }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Open Mods Folder") { Task { await store.openSteamFolder() } }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Divider()
                Button("Kill Wineserver") { Task { await store.killWineserver() } }
                    .keyboardShortcut("k", modifiers: [.command, .option])
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        switch store.appState {
        case .launching:    LaunchingView()
        case .needsSetup:   SetupWizardView()
        case .ready:        MainAppView()
        }
    }
}

struct LaunchingView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
            Text("wsteam").font(.largeTitle.bold())
            ProgressView("Starting…")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
