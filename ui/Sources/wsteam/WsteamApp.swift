import SwiftUI

@main
struct WsteamApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("wsteam") {
                Button("Launch Steam") {
                    Task { await store.launchSteam() }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button("Kill Wineserver") {
                    Task { await store.killWineserver() }
                }
                .keyboardShortcut("k", modifiers: [.command, .option])

                Divider()

                Button("Refresh Library") {
                    Task { await store.refreshLibrary() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
