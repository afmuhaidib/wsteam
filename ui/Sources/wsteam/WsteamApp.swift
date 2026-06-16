import SwiftUI

@main
struct WsteamApp: App {
    @StateObject private var engine = WineEngine()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(engine)
                .frame(minWidth: 860, minHeight: 580)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("wsteam") {
                Button("Open Steam") { engine.launchSteam() }.keyboardShortcut("s", modifiers: [.command,.shift])
                Button("Kill Wineserver") { engine.killWineserver() }.keyboardShortcut("k", modifiers: [.command,.option])
                Button("Open Mods Folder") { engine.openFolder(WsteamPaths.steamapps ?? WsteamPaths.base) }.keyboardShortcut("m", modifiers: [.command,.shift])
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var engine: WineEngine
    var body: some View {
        switch engine.stage {
        case .idle:           SetupView()
        case .ready:          LibraryView()
        case .error:          SetupView()
        default:              SetupView()
        }
    }
}
